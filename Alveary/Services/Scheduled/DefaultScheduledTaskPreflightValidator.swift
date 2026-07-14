import AgentCLIKit
import Foundation

struct DefaultScheduledTaskPreflightValidator: Sendable {
    typealias ProviderStatusLoader = @Sendable (AgentProviderID, URL?) async -> AgentProviderStatus?
    typealias RootCanonicalizer = @Sendable ([String], String?) throws -> [String]
    typealias DirectoryAccessChecker = @Sendable (String, Bool) -> Bool
    typealias DirectoryIdentityLoader = @Sendable (String) throws -> TaskWorkspaceFileSystemIdentity
    typealias WorktreeFeasibilityChecker = @Sendable (
        String,
        String?,
        String?,
        TaskWorkspaceFileSystemIdentity
    ) async throws -> Void

    private let loadProviderStatus: ProviderStatusLoader
    private let canonicalizeRoots: RootCanonicalizer
    private let checkDirectoryAccess: DirectoryAccessChecker
    private let loadDirectoryIdentity: DirectoryIdentityLoader
    private let checkWorktreeFeasibility: WorktreeFeasibilityChecker

    static func directoryIsAccessible(
        at path: String,
        requiresWriteAccess: Bool,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isReadableFile(atPath: path),
              fileManager.isExecutableFile(atPath: path) else {
            return false
        }
        return !requiresWriteAccess || fileManager.isWritableFile(atPath: path)
    }

    init(
        providerDiscovery: any AgentProviderDiscoveryService,
        workspaceOwnershipService: any TaskWorkspaceOwnershipService,
        worktreeManager: any WorktreeManager,
        fileManager: FileManager = .default
    ) {
        let fileManagerBox = ScheduledTaskFileManagerBox(fileManager)
        self.loadProviderStatus = { providerID, projectURL in
            await providerDiscovery.providerStatuses(projectURL: projectURL)[providerID]
        }
        self.canonicalizeRoots = { roots, primaryRoot in
            try workspaceOwnershipService.canonicalizeGrants(
                roots,
                excludingPrimaryRoot: primaryRoot
            )
        }
        self.loadDirectoryIdentity = { path in
            try workspaceOwnershipService.directoryIdentity(at: path)
        }
        self.checkDirectoryAccess = { path, requiresWriteAccess in
            Self.directoryIsAccessible(
                at: path,
                requiresWriteAccess: requiresWriteAccess,
                fileManager: fileManagerBox.value
            )
        }
        self.checkWorktreeFeasibility = { projectPath, baseRef, remoteName, projectIdentity in
            try await worktreeManager.validateCreation(
                projectPath: projectPath,
                baseRef: baseRef,
                remoteName: remoteName,
                expectedProjectIdentity: projectIdentity
            )
        }
    }

    init(
        loadProviderStatus: @escaping ProviderStatusLoader,
        canonicalizeRoots: @escaping RootCanonicalizer,
        checkDirectoryAccess: @escaping DirectoryAccessChecker,
        loadDirectoryIdentity: @escaping DirectoryIdentityLoader,
        checkWorktreeFeasibility: @escaping WorktreeFeasibilityChecker
    ) {
        self.loadProviderStatus = loadProviderStatus
        self.canonicalizeRoots = canonicalizeRoots
        self.checkDirectoryAccess = checkDirectoryAccess
        self.loadDirectoryIdentity = loadDirectoryIdentity
        self.checkWorktreeFeasibility = checkWorktreeFeasibility
    }

    func validate(_ snapshot: ScheduledTaskPreflightSnapshot) async -> ScheduledTaskPreflightOutcome {
        do {
            let projectPath = try validateWorkspace(snapshot)
            try validateSchedule(snapshot)
            let workspaceIdentities = try captureWorkspaceIdentities(
                snapshot,
                projectPath: projectPath
            )
            if snapshot.workspaceKind == .project,
               snapshot.workspaceStrategy == .worktree {
                guard let projectPath,
                      let projectIdentity = workspaceIdentities.projectRoot?.identity else {
                    throw ScheduledTaskPreflightValidationError.workspaceRootsChanged
                }
                do {
                    try await checkWorktreeFeasibility(
                        projectPath,
                        snapshot.projectBaseRef,
                        snapshot.projectRemoteName,
                        projectIdentity
                    )
                } catch {
                    throw ScheduledTaskPreflightValidationError.worktreeUnavailable(error.localizedDescription)
                }
            }

            guard let providerID = AgentProviderID(rawValue: snapshot.providerID) else {
                throw ScheduledTaskPreflightValidationError.unsupportedProvider(snapshot.providerID)
            }
            let projectURL = projectPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            guard let status = await loadProviderStatus(providerID, projectURL),
                  status.isReadyInProject else {
                throw ScheduledTaskPreflightValidationError.providerUnavailable(snapshot.providerID)
            }
            try validateProviderSettings(snapshot, status: status)
            let revalidatedProjectPath = try validateWorkspace(snapshot)
            let revalidatedIdentities = try captureWorkspaceIdentities(
                snapshot,
                projectPath: revalidatedProjectPath
            )
            guard revalidatedIdentities == workspaceIdentities else {
                throw ScheduledTaskPreflightValidationError.workspaceRootsChanged
            }
            return .ready(workspaceIdentities)
        } catch {
            return .invalid(reason: error.localizedDescription)
        }
    }
}

private final class ScheduledTaskFileManagerBox: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}

private extension DefaultScheduledTaskPreflightValidator {
    func validateSchedule(_ snapshot: ScheduledTaskPreflightSnapshot) throws {
        try ScheduledTaskRecurrenceCalculator().validate(
            snapshot.recurrence,
            timeZoneIdentifier: snapshot.timeZoneIdentifier
        )
    }

    func validateWorkspace(_ snapshot: ScheduledTaskPreflightSnapshot) throws -> String? {
        let projectPath: String?
        switch snapshot.workspaceKind {
        case .privateWorkspace:
            guard snapshot.projectPath == nil else {
                throw ScheduledTaskPreflightValidationError.unexpectedProjectWorkspace
            }
            projectPath = nil
        case .project:
            guard let configuredPath = snapshot.projectPath else {
                throw ScheduledTaskPreflightValidationError.missingProjectWorkspace
            }
            let canonicalPaths = try canonicalizeRoots([configuredPath], nil)
            guard canonicalPaths.count == 1,
                  canonicalPaths[0] == configuredPath else {
                throw ScheduledTaskPreflightValidationError.invalidProjectWorkspace(configuredPath)
            }
            projectPath = canonicalPaths[0]
            guard checkDirectoryAccess(canonicalPaths[0], true) else {
                throw ScheduledTaskPreflightValidationError.inaccessibleWorkspace(canonicalPaths[0])
            }
        }

        let canonicalGrants = try canonicalizeRoots(snapshot.grantedRoots, projectPath)
        guard canonicalGrants == snapshot.grantedRoots else {
            throw ScheduledTaskPreflightValidationError.invalidFolderGrants
        }
        guard canonicalGrants.allSatisfy({ checkDirectoryAccess($0, false) }) else {
            throw ScheduledTaskPreflightValidationError.inaccessibleFolderGrant
        }
        return projectPath
    }

    func captureWorkspaceIdentities(
        _ snapshot: ScheduledTaskPreflightSnapshot,
        projectPath: String?
    ) throws -> ScheduledTaskWorkspaceIdentitySnapshot {
        do {
            return try ScheduledTaskWorkspaceIdentitySnapshot(
                workspaceKind: snapshot.workspaceKind,
                projectPath: projectPath,
                grantedRootPaths: snapshot.grantedRoots,
                identityAtPath: loadDirectoryIdentity
            )
        } catch {
            throw ScheduledTaskPreflightValidationError.workspaceRootsChanged
        }
    }

    func validateProviderSettings(
        _ snapshot: ScheduledTaskPreflightSnapshot,
        status: AgentProviderStatus
    ) throws {
        let supportedPermissionModes = AppSettings.supportedPermissionModes(forProvider: snapshot.providerID)
        guard supportedPermissionModes.contains(snapshot.permissionMode) else {
            throw ScheduledTaskPreflightValidationError.unsupportedPermissionMode(snapshot.permissionMode)
        }

        guard !status.modelOptions.isEmpty else {
            return
        }
        guard let selectedModel = AgentModelOptionSelection.option(
            in: status.modelOptions,
            matching: snapshot.model
        ) else {
            throw ScheduledTaskPreflightValidationError.unsupportedModel(snapshot.model ?? "default")
        }
        let supportedEfforts = selectedModel.supportedEffortOptions
        guard supportedEfforts.isEmpty || supportedEfforts.contains(where: { $0.value == snapshot.effort }) else {
            throw ScheduledTaskPreflightValidationError.unsupportedEffort(snapshot.effort)
        }
    }
}

private enum ScheduledTaskPreflightValidationError: LocalizedError {
    case unsupportedProvider(String)
    case providerUnavailable(String)
    case unexpectedProjectWorkspace
    case missingProjectWorkspace
    case invalidProjectWorkspace(String)
    case inaccessibleWorkspace(String)
    case invalidFolderGrants
    case inaccessibleFolderGrant
    case workspaceRootsChanged
    case worktreeUnavailable(String)
    case unsupportedPermissionMode(String)
    case unsupportedModel(String)
    case unsupportedEffort(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let providerID):
            return "The scheduled task provider is unsupported: \(providerID)."
        case .providerUnavailable(let providerID):
            return "The scheduled task provider is not ready: \(providerID)."
        case .unexpectedProjectWorkspace:
            return "A private scheduled task cannot retain a Project workspace."
        case .missingProjectWorkspace:
            return "The scheduled task Project workspace is missing."
        case .invalidProjectWorkspace(let path):
            return "The scheduled task Project workspace is invalid: \(path)."
        case .inaccessibleWorkspace(let path):
            return "The scheduled task workspace is not accessible: \(path)."
        case .invalidFolderGrants:
            return "The scheduled task folder grants are no longer canonical."
        case .inaccessibleFolderGrant:
            return "A scheduled task folder grant is no longer accessible."
        case .workspaceRootsChanged:
            return "The scheduled task workspace or folder access changed during preflight."
        case .worktreeUnavailable(let reason):
            return "The scheduled task worktree cannot be created: \(reason)"
        case .unsupportedPermissionMode(let mode):
            return "The scheduled task permission mode is unsupported: \(mode)."
        case .unsupportedModel(let model):
            return "The scheduled task model is unavailable: \(model)."
        case .unsupportedEffort(let effort):
            return "The scheduled task effort is unavailable: \(effort)."
        }
    }
}
