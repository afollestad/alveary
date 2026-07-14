import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

final class ScheduledTaskPreflightValidatorTests: XCTestCase {
    func testReadyProjectWorktreeValidatesProviderWorkspaceAndRepository() async {
        let recorder = PreflightValidationRecorder()
        let validator = makeValidator(recorder: recorder)
        let snapshot = makeSnapshot()

        let outcome = await validator.validate(snapshot)
        let worktreeConfigs = await recorder.worktreeConfigs
        let projectURLs = await recorder.projectURLs
        let projectPaths = projectURLs.map(\.path)

        XCTAssertEqual(outcome, .ready(expectedIdentities(for: snapshot)))
        XCTAssertEqual(
            worktreeConfigs,
            [.init(
                path: "/tmp/project",
                baseRef: "main",
                remoteName: "upstream",
                projectIdentity: Self.identity(at: "/tmp/project")
            )]
        )
        XCTAssertEqual(projectPaths, ["/tmp/project"])
    }

    func testUnavailableProviderIsInvalid() async {
        let validator = makeValidator(loadProviderStatus: { _, _ in nil })

        let outcome = await validator.validate(makeSnapshot())

        XCTAssertEqual(
            outcome,
            ScheduledTaskPreflightOutcome.invalid(reason: "The scheduled task provider is not ready: claude.")
        )
    }

    func testNoncanonicalOrMissingGrantIsInvalid() async {
        let validator = makeValidator(
            canonicalizeRoots: { roots, _ in Array(roots.map(CanonicalPath.normalize).reversed()) },
            checkDirectoryAccess: { path, _ in path != "/tmp/grant-b" }
        )
        let snapshot = makeSnapshot(grantedRoots: ["/tmp/grant-a", "/tmp/grant-b"])

        let outcome = await validator.validate(snapshot)

        XCTAssertEqual(
            outcome,
            ScheduledTaskPreflightOutcome.invalid(reason: "The scheduled task folder grants are no longer canonical.")
        )
    }

    func testUnsupportedProviderSettingsAreInvalid() async {
        let status = Self.makeReadyProviderStatus(
            modelOptions: [
                AgentModelOption(
                    providerId: .claude,
                    id: "sonnet",
                    model: "claude-sonnet",
                    label: "Sonnet",
                    isDefault: true,
                    supportedEffortOptions: [AgentProviderOption(
                        value: "high",
                        label: "High",
                        description: "Use high reasoning effort."
                    )]
                )
            ]
        )
        let validator = makeValidator(loadProviderStatus: { _, _ in status })

        let modelOutcome = await validator.validate(makeSnapshot(model: "missing"))
        let effortOutcome = await validator.validate(makeSnapshot(model: "claude-sonnet", effort: "low"))
        let permissionOutcome = await validator.validate(makeSnapshot(permissionMode: "not-a-mode"))

        XCTAssertEqual(
            modelOutcome,
            ScheduledTaskPreflightOutcome.invalid(reason: "The scheduled task model is unavailable: missing.")
        )
        XCTAssertEqual(
            effortOutcome,
            ScheduledTaskPreflightOutcome.invalid(reason: "The scheduled task effort is unavailable: low.")
        )
        XCTAssertEqual(
            permissionOutcome,
            ScheduledTaskPreflightOutcome.invalid(reason: "The scheduled task permission mode is unsupported: not-a-mode.")
        )
    }

    func testWorktreeFeasibilityFailureIsInvalid() async {
        let validator = makeValidator(checkWorktreeFeasibility: { _, _, _, _ in
            throw GitError.notARepository
        })

        let outcome = await validator.validate(makeSnapshot())

        XCTAssertEqual(
            outcome,
            ScheduledTaskPreflightOutcome.invalid(
                reason: "The scheduled task worktree cannot be created: This project is not a Git repository"
            )
        )
    }

    func testProjectWorktreeRequiresWritableSourceWorkspace() async {
        let validator = makeValidator(
            checkDirectoryAccess: { _, requiresWriteAccess in requiresWriteAccess }
        )
        let snapshot = makeSnapshot(grantedRoots: [])

        let outcome = await validator.validate(snapshot)

        XCTAssertEqual(outcome, .ready(expectedIdentities(for: snapshot)))
    }

    func testSamePathDirectoryReplacementDuringAsyncPreflightIsInvalid() async {
        let identitySource = PreflightIdentitySource()
        let validator = makeValidator(
            loadProviderStatus: { _, _ in
                identitySource.replaceDirectories()
                return Self.makeReadyProviderStatus()
            },
            loadDirectoryIdentity: identitySource.identity(at:)
        )

        let outcome = await validator.validate(makeSnapshot())

        XCTAssertEqual(
            outcome,
            .invalid(reason: "The scheduled task workspace or folder access changed during preflight.")
        )
    }

    func testProjectSymlinkAliasIsInvalidEvenWhenItResolvesToTheSameDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduledProjectAlias-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("Project", isDirectory: true)
        let alias = root.appendingPathComponent("ProjectAlias", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: project.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = await makeValidator().validate(makeSnapshot(projectPath: alias.path))

        XCTAssertEqual(
            outcome,
            .invalid(reason: "The scheduled task Project workspace is invalid: \(alias.path).")
        )
    }

    func testFolderGrantSymlinkAliasIsInvalidEvenWhenItResolvesToTheSameDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduledGrantAlias-\(UUID().uuidString)", isDirectory: true)
        let grant = root.appendingPathComponent("Grant", isDirectory: true)
        let alias = root.appendingPathComponent("GrantAlias", isDirectory: true)
        try FileManager.default.createDirectory(at: grant, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: grant.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = await makeValidator().validate(makeSnapshot(grantedRoots: [alias.path]))

        XCTAssertEqual(
            outcome,
            .invalid(reason: "The scheduled task folder grants are no longer canonical.")
        )
    }

    func testDirectoryAccessRequiresSearchPermission() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("ScheduledSearchPermission-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? fileManager.removeItem(at: directory)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.path)

        XCTAssertFalse(
            DefaultScheduledTaskPreflightValidator.directoryIsAccessible(
                at: directory.path,
                requiresWriteAccess: false,
                fileManager: fileManager
            )
        )
    }
}

private extension ScheduledTaskPreflightValidatorTests {
    func makeValidator(
        recorder: PreflightValidationRecorder = PreflightValidationRecorder(),
        loadProviderStatus: DefaultScheduledTaskPreflightValidator.ProviderStatusLoader? = nil,
        canonicalizeRoots: @escaping DefaultScheduledTaskPreflightValidator.RootCanonicalizer = { roots, primaryRoot in
            roots.map(CanonicalPath.normalize).filter { $0 != primaryRoot }
        },
        checkDirectoryAccess: @escaping DefaultScheduledTaskPreflightValidator.DirectoryAccessChecker = { _, _ in true },
        loadDirectoryIdentity: @escaping DefaultScheduledTaskPreflightValidator.DirectoryIdentityLoader = { path in
            ScheduledTaskPreflightValidatorTests.identity(at: path)
        },
        checkWorktreeFeasibility: DefaultScheduledTaskPreflightValidator.WorktreeFeasibilityChecker? = nil
    ) -> DefaultScheduledTaskPreflightValidator {
        let resolvedStatusLoader = loadProviderStatus ?? { _, projectURL in
            await recorder.record(projectURL: projectURL)
            return Self.makeReadyProviderStatus()
        }
        return DefaultScheduledTaskPreflightValidator(
            loadProviderStatus: resolvedStatusLoader,
            canonicalizeRoots: canonicalizeRoots,
            checkDirectoryAccess: checkDirectoryAccess,
            loadDirectoryIdentity: loadDirectoryIdentity,
            checkWorktreeFeasibility: checkWorktreeFeasibility ?? { path, baseRef, remoteName, projectIdentity in
                await recorder.record(
                    worktreeConfig: .init(
                        path: path,
                        baseRef: baseRef,
                        remoteName: remoteName,
                        projectIdentity: projectIdentity
                    )
                )
            }
        )
    }

    func makeSnapshot(
        model: String? = nil,
        effort: String = "high",
        permissionMode: String = "default",
        projectPath: String = "/tmp/project",
        grantedRoots: [String] = ["/tmp/grant"]
    ) -> ScheduledTaskPreflightSnapshot {
        ScheduledTaskPreflightSnapshot(
            definitionID: "definition",
            definitionRevision: 1,
            scheduledOccurrenceAt: Date(timeIntervalSince1970: 1_700_000_000),
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "claude",
            model: model,
            effort: effort,
            permissionMode: permissionMode,
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectPath,
            projectBaseRef: "main",
            projectRemoteName: "upstream",
            grantedRoots: grantedRoots
        )
    }

    static func makeReadyProviderStatus(
        modelOptions: [AgentModelOption] = []
    ) -> AgentProviderStatus {
        AgentProviderStatus(
            providerId: .claude,
            installation: .installed,
            isEnabled: true,
            setup: .ready,
            modelOptions: modelOptions
        )
    }

    func expectedIdentities(
        for snapshot: ScheduledTaskPreflightSnapshot
    ) -> ScheduledTaskWorkspaceIdentitySnapshot {
        let projectRoot = snapshot.projectPath.map { path in
            ScheduledTaskRootIdentitySnapshot(path: path, identity: Self.identity(at: path))
        }
        let grantedRoots = snapshot.grantedRoots.map { path in
            ScheduledTaskRootIdentitySnapshot(path: path, identity: Self.identity(at: path))
        }
        return ScheduledTaskWorkspaceIdentitySnapshot(
            projectRoot: projectRoot,
            grantedRoots: grantedRoots
        )
    }

    static func identity(at path: String) -> TaskWorkspaceFileSystemIdentity {
        TaskWorkspaceFileSystemIdentity(
            systemNumber: 1,
            fileNumber: UInt64(path.utf8.reduce(0) { $0 + Int($1) })
        )
    }
}

private actor PreflightValidationRecorder {
    struct WorktreeConfig: Equatable {
        let path: String
        let baseRef: String?
        let remoteName: String?
        let projectIdentity: TaskWorkspaceFileSystemIdentity
    }

    private(set) var projectURLs: [URL] = []
    private(set) var worktreeConfigs: [WorktreeConfig] = []

    func record(projectURL: URL?) {
        if let projectURL {
            projectURLs.append(projectURL)
        }
    }

    func record(worktreeConfig: WorktreeConfig) {
        worktreeConfigs.append(worktreeConfig)
    }
}

private final class PreflightIdentitySource: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 1

    func identity(at path: String) -> TaskWorkspaceFileSystemIdentity {
        lock.withLock {
            TaskWorkspaceFileSystemIdentity(
                systemNumber: generation,
                fileNumber: UInt64(path.utf8.reduce(0) { $0 + Int($1) })
            )
        }
    }

    func replaceDirectories() {
        lock.withLock {
            generation += 1
        }
    }
}
