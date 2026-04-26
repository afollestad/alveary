import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testEmptyThreadStateHero() {
        assertMacSnapshot(
            EmptyThreadState(
                setupPhase: nil,
                isCancellingInitialSetup: false
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_thread_hero"
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
