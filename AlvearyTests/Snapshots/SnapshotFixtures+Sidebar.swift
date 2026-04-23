import XCTest

@testable import Alveary

@MainActor
struct SnapshotSidebarFixture {
    let fixture: SidebarTestFixture
    let project: Project
    let emptyProject: Project
    let activeThread: AgentThread
}

@MainActor
func makeSidebarSnapshotFixture() async throws -> SnapshotSidebarFixture {
    let fixture = try SidebarTestFixture()
    let project = Project(path: "/tmp/alveary", name: "Alveary")
    let activeThread = AgentThread(name: "Refactor Chat Input", project: project)
    let archivedThread = AgentThread(name: "Audit Diff Watcher", archivedAt: Date(timeIntervalSince1970: 1_713_000_000), project: project)
    let activeConversation = Conversation(id: "main", title: "Main", provider: "claude", thread: activeThread)
    let archivedConversation = Conversation(id: "archive", title: "Main", provider: "claude", thread: archivedThread)
    activeThread.conversations = [activeConversation]
    archivedThread.conversations = [archivedConversation]
    project.threads = [activeThread, archivedThread]

    let secondaryProject = Project(path: "/tmp/tools", name: "Tools")

    fixture.context.insert(project)
    fixture.context.insert(activeThread)
    fixture.context.insert(archivedThread)
    fixture.context.insert(activeConversation)
    fixture.context.insert(archivedConversation)
    fixture.context.insert(secondaryProject)
    try fixture.context.save()
    await fixture.agentsManager.setStatus(.busy, for: activeConversation.id)

    return SnapshotSidebarFixture(
        fixture: fixture,
        project: project,
        emptyProject: secondaryProject,
        activeThread: activeThread
    )
}
