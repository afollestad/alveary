import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class DataComponentTests: XCTestCase {
    func testPersistentStoreURLUsesAlvearyScopedLocation() {
        let applicationSupportDirectory = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)

        let storeURL = DataComponent.persistentStoreURL(in: applicationSupportDirectory)

        XCTAssertEqual(storeURL.path, "/tmp/Application Support/Alveary/Alveary.store")
    }

    func testResolvesContainerAndPersistsEveryModelType() throws {
        let component = makeComponent()
        let context = component.modelContext

        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let thread = AgentThread(name: "Phase 1")
        let conversation = Conversation(provider: "claude")
        let event = ConversationEventRecord(
            conversationId: conversation.id,
            type: "message",
            role: "assistant",
            content: "Hello"
        )

        XCTAssertFalse(project.isPinned)
        project.isPinned = true
        project.threads.append(thread)
        thread.conversations.append(conversation)
        conversation.events.append(event)

        context.insert(project)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AgentThread>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Conversation>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConversationEventRecord>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Project>()).first?.isPinned, true)
    }

    func testProjectPathIsUnique() throws {
        let component = makeComponent()
        let context = component.modelContext

        context.insert(Project(path: "/tmp/alveary-project", name: "One"))
        try context.save()

        context.insert(Project(path: "/tmp/../tmp/alveary-project", name: "Two"))
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 1)
    }

    func testSidebarOrderFieldsPersistAndAllowNilDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = ModelConfiguration(url: directory.appendingPathComponent("Alveary.store"))
        let regularPath = "/tmp/regular"
        let pinnedPath = "/tmp/pinned"
        try autoreleasepool {
            let container = try ModelContainer(
                for: Project.self,
                AgentThread.self,
                Conversation.self,
                ConversationEventRecord.self,
                configurations: configuration
            )
            let context = container.mainContext
            let regular = Project(path: regularPath, name: "Regular", sidebarSortOrder: 3)
            let pinned = Project(path: pinnedPath, name: "Pinned", isPinned: true, pinnedSortOrder: 1)
            let thread = AgentThread(name: "Thread", isPinned: true, pinnedSortOrder: 2, project: regular)
            regular.threads = [thread]
            context.insert(regular)
            context.insert(pinned)
            try context.save()
        }

        let reopenedContainer = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: configuration
        )
        let reopenedContext = reopenedContainer.mainContext
        let projects = try reopenedContext.fetch(FetchDescriptor<Project>())
        let threads = try reopenedContext.fetch(FetchDescriptor<AgentThread>())

        XCTAssertEqual(projects.first { $0.path == regularPath }?.sidebarSortOrder, 3)
        XCTAssertNil(projects.first { $0.path == regularPath }?.pinnedSortOrder)
        XCTAssertEqual(projects.first { $0.path == pinnedPath }?.pinnedSortOrder, 1)
        XCTAssertNil(projects.first { $0.path == pinnedPath }?.sidebarSortOrder)
        XCTAssertEqual(threads.first?.pinnedSortOrder, 2)
    }

    func testDeletingProjectCascadesThroughThreadConversationAndEvents() throws {
        let component = makeComponent()
        let context = component.modelContext

        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let thread = AgentThread(name: "Phase 1")
        let conversation = Conversation(provider: "claude")
        let event = ConversationEventRecord(
            conversationId: conversation.id,
            type: "message"
        )

        project.threads.append(thread)
        thread.conversations.append(conversation)
        conversation.events.append(event)

        context.insert(project)
        try context.save()

        context.delete(project)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Conversation>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConversationEventRecord>()), 0)
    }

    func testModelContextIsContainerScoped() {
        let component = makeComponent()
        let firstContext = component.modelContext
        let secondContext = component.modelContext

        XCTAssertTrue(firstContext === secondContext)
    }

    private func makeComponent() -> AppComponent {
        AppDI.makeTestComponent(isStoredInMemoryOnly: true)
    }
}
