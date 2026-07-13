import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ContentViewDraftRoutingTests: XCTestCase {
    func testNewThreadProjectResolverUsesPersistedLastActiveProjectWithoutCurrentContext() throws {
        let fixture = try DraftRoutingFixture()

        let resolution = NewThreadProjectResolver.resolve(
            selection: nil,
            previousSelection: nil,
            lastActiveProjectPath: fixture.persistedProject.path,
            modelContext: fixture.context
        )

        XCTAssertEqual(resolution.project?.persistentModelID, fixture.persistedProject.persistentModelID)
        XCTAssertEqual(resolution.lastActiveProjectPath, fixture.persistedProject.path)
    }

    func testNewThreadProjectResolverPrefersCurrentProjectAndThreadOverPersistedProject() throws {
        let fixture = try DraftRoutingFixture()

        let projectResolution = NewThreadProjectResolver.resolve(
            selection: .project(fixture.selectedProject),
            previousSelection: nil,
            lastActiveProjectPath: fixture.persistedProject.path,
            modelContext: fixture.context
        )
        let threadResolution = NewThreadProjectResolver.resolve(
            selection: .thread(fixture.selectedThread),
            previousSelection: nil,
            lastActiveProjectPath: fixture.persistedProject.path,
            modelContext: fixture.context
        )

        XCTAssertEqual(projectResolution.project?.persistentModelID, fixture.selectedProject.persistentModelID)
        XCTAssertEqual(projectResolution.lastActiveProjectPath, fixture.selectedProject.path)
        XCTAssertEqual(threadResolution.project?.persistentModelID, fixture.selectedProject.persistentModelID)
        XCTAssertEqual(threadResolution.lastActiveProjectPath, fixture.selectedProject.path)
    }

    func testNewThreadProjectResolverUsesSettingsBookmarkContext() throws {
        let fixture = try DraftRoutingFixture()

        let projectResolution = NewThreadProjectResolver.resolve(
            selection: .settings,
            previousSelection: .projectPath(fixture.selectedProject.path),
            lastActiveProjectPath: fixture.persistedProject.path,
            modelContext: fixture.context
        )
        let threadResolution = NewThreadProjectResolver.resolve(
            selection: .settings,
            previousSelection: .threadId(fixture.selectedThread.persistentModelID),
            lastActiveProjectPath: fixture.persistedProject.path,
            modelContext: fixture.context
        )

        XCTAssertEqual(projectResolution.project?.persistentModelID, fixture.selectedProject.persistentModelID)
        XCTAssertEqual(threadResolution.project?.persistentModelID, fixture.selectedProject.persistentModelID)
    }

    func testTaskModeSelectionAndBookmarkDoNotChooseAttachedProject() throws {
        let fixture = try DraftRoutingFixture()
        let task = AgentThread(
            name: "Attached task",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: fixture.selectedProject.path,
                ownershipStrategy: .projectLocal,
                sourceProjectPath: fixture.selectedProject.path
            ),
            project: fixture.selectedProject
        )
        fixture.selectedProject.threads.append(task)
        fixture.context.insert(task)
        try fixture.context.save()

        let selectedResolution = NewThreadProjectResolver.resolve(
            selection: .thread(task),
            previousSelection: nil,
            lastActiveProjectPath: fixture.persistedProject.path,
            modelContext: fixture.context
        )
        let bookmarkResolution = NewThreadProjectResolver.resolve(
            selection: .settings,
            previousSelection: .threadId(task.persistentModelID),
            lastActiveProjectPath: fixture.persistedProject.path,
            modelContext: fixture.context
        )

        XCTAssertEqual(selectedResolution.project?.persistentModelID, fixture.persistedProject.persistentModelID)
        XCTAssertEqual(bookmarkResolution.project?.persistentModelID, fixture.persistedProject.persistentModelID)
    }

    func testNewThreadProjectResolverRewritesStalePathToDeterministicFallback() throws {
        let (container, context) = try makeProjectSelectionContainer()
        let laterPath = Project(path: "/tmp/z-alveary", name: "alveary")
        let earlierPath = Project(path: "/tmp/a-alveary", name: "Alveary")
        let laterName = Project(path: "/tmp/beta", name: "Beta")
        context.insert(laterPath)
        context.insert(earlierPath)
        context.insert(laterName)
        try context.save()

        let resolution = NewThreadProjectResolver.resolve(
            selection: nil,
            previousSelection: nil,
            lastActiveProjectPath: "/tmp/deleted-project",
            modelContext: context
        )

        withExtendedLifetime(container) {
            XCTAssertEqual(resolution.project?.persistentModelID, earlierPath.persistentModelID)
            XCTAssertEqual(resolution.lastActiveProjectPath, "/tmp/a-alveary")
        }
    }

    func testNewThreadProjectResolverReturnsNoProjectWithoutCreatingDraft() throws {
        let (container, context) = try makeProjectSelectionContainer()

        let resolution = NewThreadProjectResolver.resolve(
            selection: nil,
            previousSelection: nil,
            lastActiveProjectPath: "/tmp/deleted-project",
            modelContext: context
        )

        let threads = try context.fetch(FetchDescriptor<AgentThread>())
        withExtendedLifetime(container) {
            XCTAssertNil(resolution.project)
            XCTAssertNil(resolution.lastActiveProjectPath)
            XCTAssertTrue(threads.isEmpty)
            XCTAssertEqual(
                NewThreadCommandPresentation.noProjectMessage,
                "Add a project before starting a new thread."
            )
        }
    }

    func testLastActiveProjectPathDecodeDefaultAndWhitespaceNormalization() throws {
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).normalized()
        let whitespace = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"lastActiveProjectPath":"   "}"#.utf8)
        ).normalized()

        XCTAssertNil(missing.lastActiveProjectPath)
        XCTAssertNil(whitespace.lastActiveProjectPath)
    }

    func testDiffCommitTargetResolverRoutesDraftThreadThroughProject() throws {
        let fixture = try DraftRoutingFixture(isDraft: true, worktreePath: "/tmp/worktree")
        fixture.appState.selectedSidebarItem = .thread(fixture.selectedThread)

        let snapshot = DiffGitCommitTargetSnapshotResolver.resolve(
            selection: fixture.appState.selectedSidebarItem,
            modelContext: fixture.context,
            appState: fixture.appState,
            activeDirectory: fixture.selectedProject.path
        )

        XCTAssertEqual(snapshot?.directory, fixture.selectedProject.path)
        XCTAssertEqual(snapshot?.targetName, fixture.selectedProject.name)
        XCTAssertEqual(snapshot?.baseBranch, "develop")
        XCTAssertEqual(snapshot?.remoteName, "upstream")
        XCTAssertEqual(snapshot?.generationRoute, .project(directory: fixture.selectedProject.path))
    }

    func testDefaultShellContextRoutesDraftThroughProjectWithoutThreadMetadata() throws {
        let fixture = try DraftRoutingFixture(isDraft: true, worktreePath: "/tmp/worktree")

        let context = TerminalDefaultShellContextResolver.resolve(
            selection: .thread(fixture.selectedThread),
            modelContext: fixture.context
        )

        XCTAssertEqual(context.title, "Shell")
        XCTAssertNil(context.threadID)
        XCTAssertNil(context.threadName)
        XCTAssertEqual(context.currentDirectory, fixture.selectedProject.path)
    }
}

@MainActor
private struct DraftRoutingFixture {
    let container: ModelContainer
    let context: ModelContext
    let appState: AppState
    let selectedProject: Project
    let selectedThread: AgentThread
    let persistedProject: Project

    init(isDraft: Bool = false, worktreePath: String? = nil) throws {
        let (container, context) = try makeProjectSelectionContainer()
        let selectedProject = Project(
            path: "/tmp/selected",
            name: "Selected",
            remoteName: "upstream",
            baseRef: "develop"
        )
        let selectedThread = AgentThread(
            name: "Selected thread",
            worktreePath: worktreePath,
            isDraft: isDraft,
            project: selectedProject
        )
        selectedProject.threads.append(selectedThread)
        let persistedProject = Project(path: "/tmp/persisted", name: "Persisted")
        context.insert(selectedProject)
        context.insert(persistedProject)
        try context.save()

        self.container = container
        self.context = context
        self.appState = AppState()
        self.selectedProject = selectedProject
        self.selectedThread = selectedThread
        self.persistedProject = persistedProject
    }
}

@MainActor
private func makeProjectSelectionContainer() throws -> (ModelContainer, ModelContext) {
    let container = try ModelContainer(
        for: Project.self,
        AgentThread.self,
        Conversation.self,
        ConversationEventRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return (container, ModelContext(container))
}
