import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testEmptyThreadProjectOptionsSortDisambiguateAndSelect() {
        let beta = Project(path: "/tmp/beta", name: "Beta")
        let laterDuplicate = Project(path: "/tmp/z-alveary", name: "alveary")
        let selectedDuplicate = Project(path: "/tmp/a-alveary", name: "Alveary")

        let options = emptyThreadProjectOptions(
            projects: [beta, laterDuplicate, selectedDuplicate],
            selectedProjectPath: selectedDuplicate.path
        )

        XCTAssertEqual(options.map(\.project.path), [selectedDuplicate.path, laterDuplicate.path, beta.path])
        XCTAssertEqual(options.map(\.showsDisambiguatingPath), [true, true, false])
        XCTAssertEqual(options.map(\.isSelected), [true, false, false])
        XCTAssertEqual(options.first?.displayPath, selectedDuplicate.path)
    }

    func testEmptyThreadProjectIdentityPresentationIncludesFullNameAndPath() {
        let presentation = emptyThreadProjectIdentityPresentation(
            name: "Alveary",
            path: "/Users/alice/Development/alveary"
        )

        XCTAssertEqual(presentation.helpText, "Alveary\n/Users/alice/Development/alveary")
        XCTAssertEqual(presentation.accessibilityValue, "Alveary, /Users/alice/Development/alveary")
    }

    func testEmptyThreadStateHero() throws {
        let fixture = try makeEmptyThreadFixture()
        assertMacSnapshot(
            EmptyThreadState(
                setupPhase: nil,
                isCancellingInitialSetup: false,
                thread: fixture.thread,
                projects: fixture.projects
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_thread_hero"
        )
    }

    func testEmptyThreadStateHeroDark() throws {
        let fixture = try makeEmptyThreadFixture()
        assertMacSnapshot(
            EmptyThreadState(
                setupPhase: nil,
                isCancellingInitialSetup: false,
                thread: fixture.thread,
                projects: fixture.projects
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_thread_hero_dark",
            colorScheme: .dark
        )
    }

    func testEmptyThreadStateHeroNarrowLongProjectName() throws {
        let fixture = try makeEmptyThreadFixture(selectsLongProject: true)
        assertMacSnapshot(
            EmptyThreadState(
                setupPhase: nil,
                isCancellingInitialSetup: false,
                thread: fixture.thread,
                projects: fixture.projects
            ),
            size: CGSize(width: 420, height: 560),
            named: "empty_thread_hero_narrow_long_project",
            precision: 0.9, perceptualPrecision: 0.9, forceFixedScale: true
        )
    }

    func testEmptyThreadStateMaterializedHeroUsesStaticProjectLabel() throws {
        let fixture = try makeEmptyThreadFixture(isDraft: false)
        assertMacSnapshot(
            EmptyThreadState(
                setupPhase: nil,
                isCancellingInitialSetup: false,
                thread: fixture.thread,
                projects: fixture.projects
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_thread_hero_materialized"
        )
    }

    func testEmptyTaskStateHero() throws {
        let fixture = try makeEmptyTaskFixture()
        assertMacSnapshot(
            EmptyThreadState(
                setupPhase: nil,
                isCancellingInitialSetup: false,
                thread: fixture.thread
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_task_hero"
        )
    }

    func testEmptyTaskStateHeroDark() throws {
        let fixture = try makeEmptyTaskFixture()
        assertMacSnapshot(
            EmptyThreadState(
                setupPhase: nil,
                isCancellingInitialSetup: false,
                thread: fixture.thread
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_task_hero_dark",
            colorScheme: .dark
        )
    }

    func testEmptyTaskStateHeroNarrow() throws {
        let fixture = try makeEmptyTaskFixture()
        assertMacSnapshot(
            EmptyThreadState(
                setupPhase: nil,
                isCancellingInitialSetup: false,
                thread: fixture.thread
            ),
            size: CGSize(width: 420, height: 560),
            named: "empty_task_hero_narrow"
        )
    }

    func testEmptyThreadStateCreatingWorktree() {
        assertMacSnapshot(
            EmptyThreadState(
                setupPhase: .creatingWorktree,
                isCancellingInitialSetup: false
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_thread_creating_worktree"
        )
    }

    func testEmptyThreadStateCancellingInitialSetup() {
        assertMacSnapshot(
            EmptyThreadState(
                setupPhase: .creatingWorktree,
                isCancellingInitialSetup: true
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_thread_cancelling_initial_setup"
        )
    }

    func testProjectTrustPrompt() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let project = Project(path: "/Users/alice/Development/../Development/Alveary", name: "Alveary")
        let thread = AgentThread(name: "New thread", project: project)
        context.insert(project)
        context.insert(thread)
        try context.save()

        assertMacSnapshot(
            ProjectTrustPromptView(
                prompt: ProjectTrustPrompt(
                    threadID: thread.persistentModelID,
                    canonicalProjectPath: project.path,
                    projectName: project.name,
                    providerID: "claude"
                ),
                onTrust: {},
                onDeny: {}
            ),
            size: CGSize(width: 900, height: 560),
            named: "project_trust_prompt"
        )
    }

    func testProjectTrustPromptDisplayPathAbbreviatesHomeDirectory() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let project = Project(path: NSHomeDirectory() + "/Development/af.codes", name: "af.codes")
        let thread = AgentThread(name: "New thread", project: project)
        context.insert(project)
        context.insert(thread)
        try context.save()

        let prompt = ProjectTrustPrompt(
            threadID: thread.persistentModelID,
            canonicalProjectPath: project.path,
            projectName: project.name,
            providerID: "claude"
        )

        XCTAssertEqual(prompt.displayProjectPath, "~/Development/af.codes")
        XCTAssertEqual(prompt.canonicalProjectPath, NSHomeDirectory() + "/Development/af.codes")
    }
}

private extension SnapshotTests {
    func makeEmptyThreadFixture(
        selectsLongProject: Bool = false,
        isDraft: Bool = true
    ) throws -> EmptyThreadFixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let project = Project(path: "/Users/alice/Development/alveary", name: "alveary")
        let duplicate = Project(path: "/Users/alice/Archives/alveary", name: "alveary")
        let longProject = Project(
            path: "/Users/alice/Development/a-very-long-project-name-for-truncation-that-keeps-going",
            name: "a-very-long-project-name-for-truncation-that-keeps-going"
        )
        let thread = AgentThread(
            name: "New thread",
            isDraft: isDraft,
            project: selectsLongProject ? longProject : project
        )
        let conversation = Conversation(provider: "claude", thread: thread)
        context.insert(project)
        context.insert(duplicate)
        context.insert(longProject)
        context.insert(thread)
        context.insert(conversation)
        try context.save()
        return EmptyThreadFixture(
            container: container,
            thread: thread,
            projects: [project, duplicate, longProject]
        )
    }

    func makeEmptyTaskFixture() throws -> EmptyThreadFixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let thread = AgentThread(
            name: "New task",
            isDraft: true,
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/Users/alice/Library/Application Support/com.afollestad.alveary/TaskWorkspaces/Private/task",
                grantedRoots: ["/Users/alice/Documents/References"],
                ownershipStrategy: .privateOwned,
                ownershipMarkerID: UUID().uuidString.lowercased()
            )
        )
        let conversation = Conversation(provider: "codex", thread: thread)
        context.insert(thread)
        context.insert(conversation)
        try context.save()
        return EmptyThreadFixture(container: container, thread: thread, projects: [])
    }
}

private struct EmptyThreadFixture {
    let container: ModelContainer
    let thread: AgentThread
    let projects: [Project]
}
