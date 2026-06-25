import XCTest

@testable import Alveary

@MainActor
struct SnapshotSidebarFixture {
    let fixture: SidebarTestFixture
    let project: Project
    let emptyProject: Project
    let activeThread: AgentThread
    let pinnedThread: AgentThread?
}

@MainActor
func makeSidebarSnapshotFixture(includePinnedThread: Bool = false) async throws -> SnapshotSidebarFixture {
    let fixture = try SidebarTestFixture()
    let project = Project(path: "/tmp/alveary", name: "Alveary")
    let activeThread = AgentThread(name: "Refactor Chat Input", project: project)
    let archivedThread = AgentThread(name: "Audit Diff Watcher", archivedAt: Date(timeIntervalSince1970: 1_713_000_000), project: project)
    let activeConversation = Conversation(id: "main", title: "Main", provider: "claude", thread: activeThread)
    let archivedConversation = Conversation(id: "archive", title: "Main", provider: "claude", thread: archivedThread)
    activeThread.conversations = [activeConversation]
    archivedThread.conversations = [archivedConversation]
    project.threads = [activeThread, archivedThread]
    let pinnedThread: AgentThread?
    if includePinnedThread {
        let thread = AgentThread(
            name: "Use 3 tools",
            isPinned: true,
            modifiedAt: Date(timeIntervalSince1970: 1_713_000_100),
            project: project
        )
        let conversation = Conversation(id: "pinned", title: "Main", provider: "claude", thread: thread)
        thread.conversations = [conversation]
        project.threads.append(thread)
        pinnedThread = thread
    } else {
        pinnedThread = nil
    }

    let secondaryProject = Project(path: "/tmp/tools", name: "Tools")

    fixture.context.insert(project)
    fixture.context.insert(activeThread)
    fixture.context.insert(archivedThread)
    fixture.context.insert(activeConversation)
    fixture.context.insert(archivedConversation)
    if let pinnedThread {
        fixture.context.insert(pinnedThread)
        pinnedThread.conversations.forEach(fixture.context.insert)
    }
    fixture.context.insert(secondaryProject)
    try fixture.context.save()
    await fixture.agentsManager.setStatus(.busy, for: activeConversation.id)
    if let pinnedConversationID = pinnedThread?.conversations.first?.id {
        await fixture.agentsManager.setStatus(.waitingForUser, for: pinnedConversationID)
    }

    return SnapshotSidebarFixture(
        fixture: fixture,
        project: project,
        emptyProject: secondaryProject,
        activeThread: activeThread,
        pinnedThread: pinnedThread
    )
}
