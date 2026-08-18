import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// `create_thread`'s inherited sidebar placement: a spawn naming no `section` lands beside the
/// calling thread — its custom section, or its project nesting plus that folder's grant — while
/// an explicit `section` stays the override.
@MainActor
extension ThreadHostToolServiceTests {
    /// "Create a thread" from a sectioned caller means one beside it, so an omitted `section`
    /// inherits the caller's own.
    func testCreateThreadInheritsTheCallersSection() async throws {
        let fixture = try ThreadHostToolFixture()
        try await fixture.moveSourceTaskIntoSection(named: "Research")

        let result = await fixture.create(arguments: [:])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try object(result.structuredContent)["section"], .string("Research"))
        XCTAssertEqual(try fixture.createdThread(in: result).customSection?.name, "Research")
    }

    /// Explicit task mode asks for a workspace, not a placement, so the sidebar default still
    /// inherits.
    func testCreateThreadInheritsTheCallersSectionWithExplicitTaskMode() async throws {
        let fixture = try ThreadHostToolFixture()
        try await fixture.moveSourceTaskIntoSection(named: "Research")

        let result = await fixture.create(arguments: ["mode": .string("task")])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try fixture.createdThread(in: result).customSection?.name, "Research")
    }

    /// `Tasks` stays the explicit opt-out — now of the inherited section, not just of a named one.
    func testCreateThreadTasksOverridesTheInheritedSection() async throws {
        let fixture = try ThreadHostToolFixture()
        try await fixture.moveSourceTaskIntoSection(named: "Research")

        let result = await fixture.create(arguments: ["section": .string("Tasks")])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try object(result.structuredContent)["section"], .string("Tasks"))
        XCTAssertNil(try fixture.createdThread(in: result).customSection)
    }

    func testCreateThreadNamedSectionOverridesTheInheritedSection() async throws {
        let fixture = try ThreadHostToolFixture()
        try await fixture.moveSourceTaskIntoSection(named: "Research")
        _ = await fixture.createSection(named: "Reading")

        let result = await fixture.create(arguments: ["section": .string("Reading")])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try fixture.createdThread(in: result).customSection?.name, "Reading")
    }

    /// Nesting mirrors the sidebar's Task-to-Project drop: a task spawn from a project-mode
    /// caller renders under that project and is granted its folder.
    func testCreateThreadNestsATaskSpawnUnderAProjectModeCallersProject() async throws {
        let fixture = try ThreadHostToolFixture()
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = try fixture.reassignSourceProject(path: folder.path, named: "Realized")

        let result = await fixture.create(arguments: ["mode": .string("task")])

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["workspace_kind"], .string("task"))
        XCTAssertEqual(content["project_path"], .string(project.path))
        XCTAssertEqual(content["granted_roots"], .array([.string(project.path)]))
        XCTAssertNil(content["section"])
        XCTAssertTrue(result.text.contains("shown under \(project.path)"), result.text)

        let created = try fixture.createdThread(in: result)
        XCTAssertEqual(created.effectiveMode, .task)
        XCTAssertEqual(created.project?.path, project.path)
        XCTAssertNil(created.customSection)
        XCTAssertEqual(created.taskWorkspaceDescriptor?.grantedRoots, [project.path])
    }

    func testCreateThreadInheritsAProjectNestedTaskCallersNesting() async throws {
        let fixture = try ThreadHostToolFixture()
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = try fixture.nestSourceTaskUnderProject(path: folder.path, named: "Nest")

        let result = await fixture.create(arguments: [:])

        XCTAssertFalse(result.isError, result.text)
        let created = try fixture.createdThread(in: result)
        XCTAssertEqual(created.effectiveMode, .task)
        XCTAssertEqual(created.project?.path, project.path)
        XCTAssertEqual(created.taskWorkspaceDescriptor?.grantedRoots, [project.path])
    }

    /// An explicit `section` opts out of nesting entirely: membership instead of the project, and
    /// no folder grant riding along.
    func testCreateThreadSectionOverridesTheInheritedNesting() async throws {
        let fixture = try ThreadHostToolFixture()
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try fixture.nestSourceTaskUnderProject(path: folder.path, named: "Nest")
        _ = await fixture.createSection(named: "Research")

        for (sectionName, expectedSection) in [("Research", "Research"), ("Tasks", nil)] {
            let result = await fixture.create(arguments: ["section": .string(sectionName)])

            XCTAssertFalse(result.isError, result.text)
            let created = try fixture.createdThread(in: result)
            XCTAssertEqual(created.customSection?.name, expectedSection, sectionName)
            XCTAssertNil(created.project, sectionName)
            XCTAssertEqual(created.taskWorkspaceDescriptor?.grantedRoots, [], sectionName)
        }
    }

    /// An inherited default the request never named must not fail the create: a nesting project
    /// whose folder is gone falls back to the plain `Tasks` list, grantless.
    func testCreateThreadFallsBackToTasksWhenTheInheritedProjectFolderIsMissing() async throws {
        let fixture = try ThreadHostToolFixture()
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-missing-\(UUID().uuidString)", isDirectory: true).path
        _ = try fixture.nestSourceTaskUnderProject(path: missingPath, named: "Missing")

        let result = await fixture.create(arguments: [:])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try object(result.structuredContent)["section"], .string("Tasks"))
        let created = try fixture.createdThread(in: result)
        XCTAssertNil(created.project)
        XCTAssertNil(created.customSection)
        XCTAssertEqual(created.taskWorkspaceDescriptor?.grantedRoots, [])
    }

    /// The snapshot predates the defaults resolver's suspension; a section deleted across it
    /// falls back to `Tasks` instead of failing the create, unlike an explicitly named one.
    func testCreateThreadFallsBackToTasksWhenTheInheritedSectionVanishesMidCall() async throws {
        let removal = MidResolveMutationBox()
        let fixture = try ThreadHostToolFixture(
            providerDiscovery: MidResolveMutatingProviderDiscoveryStub { removal.run() }
        )
        try await fixture.moveSourceTaskIntoSection(named: "Research")
        let sectionID = try XCTUnwrap(fixture.thread.customSection?.id)
        removal.action = { [modelContext = fixture.modelContext] in
            guard let section = modelContext.resolveSidebarSection(id: sectionID) else {
                return
            }
            modelContext.delete(section)
            try? modelContext.save()
        }

        let result = await fixture.create(arguments: [:])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try object(result.structuredContent)["section"], .string("Tasks"))
        XCTAssertNil(try fixture.createdThread(in: result).customSection)
    }
}

extension ThreadHostToolFixture {
    /// Makes the calling conversation's thread a Task living in a custom section, the state an
    /// inherited-section spawn starts from.
    func moveSourceTaskIntoSection(named name: String) async throws {
        try makeSourceThreadATask()
        _ = await createSection(named: name)
        _ = await moveThread(threadID: conversation.id, toSection: name)
    }

    /// Points the project-mode source thread at a project whose folder really exists, because the
    /// nesting grant reads the file system.
    func reassignSourceProject(path: String, named name: String) throws -> Project {
        let project = Project(path: path, name: name)
        modelContext.insert(project)
        thread.project = project
        try modelContext.save()
        return project
    }

    /// The sidebar's Task-to-Project drop's end state — a Task rendering under a project — minus
    /// the grant, which an inherited-nesting spawn is expected to add for itself.
    func nestSourceTaskUnderProject(path: String, named name: String) throws -> Project {
        try makeSourceThreadATask()
        let project = Project(path: path, name: name)
        modelContext.insert(project)
        thread.project = project
        try modelContext.save()
        return project
    }
}

/// Host state can change while the defaults resolver awaits provider discovery; this stub is that
/// suspension, running a main-actor mutation midway so a snapshot the handler already took can go
/// stale in the only window where it can.
private actor MidResolveMutatingProviderDiscoveryStub: AgentCLIKit.AgentProviderDiscoveryService {
    private let statuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] = [
        .codex: AgentCLIKit.AgentProviderStatus(
            providerId: .codex,
            installation: .installed,
            setup: .ready,
            modelOptions: AgentModelOptionTestFixtures.codexModelOptions
        )
    ]
    private let mutate: @MainActor () -> Void

    init(mutate: @escaping @MainActor () -> Void) {
        self.mutate = mutate
    }

    func providerStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        await mutate()
        return statuses
    }

    func installedProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        await mutate()
        return statuses
    }

    func availableProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        await mutate()
        return statuses
    }

    func modelOptions(for providerId: AgentCLIKit.AgentProviderID) async -> [AgentCLIKit.AgentModelOption] {
        statuses[providerId]?.modelOptions ?? []
    }

    func stableProviderOrdering() async -> [AgentCLIKit.AgentProviderID] {
        [.codex]
    }
}

/// Bridges a fixture-owned mutation into the stub, which has to exist before the fixture does.
@MainActor
private final class MidResolveMutationBox {
    var action: () -> Void = {}

    func run() {
        action()
    }
}
