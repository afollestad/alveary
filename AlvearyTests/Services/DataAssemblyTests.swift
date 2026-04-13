import Knit
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class DataAssemblyTests: XCTestCase {
    func testPersistentStoreURLUsesAlvearyScopedLocation() {
        let applicationSupportDirectory = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)

        let storeURL = DataAssembly.persistentStoreURL(in: applicationSupportDirectory)

        XCTAssertEqual(storeURL.path, "/tmp/Application Support/Alveary/Alveary.store")
    }

    func testResolvesContainerAndPersistsEveryModelType() throws {
        let assembler = makeAssembler()
        let context = assembler.resolver.modelContext()

        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let thread = AgentThread(name: "Phase 1")
        let conversation = Conversation(provider: "claude")
        let event = ConversationEventRecord(
            conversationId: conversation.id,
            type: "message",
            role: "assistant",
            content: "Hello"
        )

        project.threads.append(thread)
        thread.conversations.append(conversation)
        conversation.events.append(event)

        context.insert(project)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AgentThread>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Conversation>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConversationEventRecord>()), 1)
    }

    func testProjectPathIsUnique() throws {
        let assembler = makeAssembler()
        let context = assembler.resolver.modelContext()

        context.insert(Project(path: "/tmp/alveary-project", name: "One"))
        try context.save()

        context.insert(Project(path: "/tmp/../tmp/alveary-project", name: "Two"))
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 1)
    }

    func testDeletingProjectCascadesThroughThreadConversationAndEvents() throws {
        let assembler = makeAssembler()
        let context = assembler.resolver.modelContext()

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
        let assembler = makeAssembler()
        let firstContext = assembler.resolver.modelContext()
        let secondContext = assembler.resolver.modelContext()

        XCTAssertTrue(firstContext === secondContext)
    }

    private func makeAssembler() -> ScopedModuleAssembler<Resolver> {
        ScopedModuleAssembler<Resolver>([
            AppAssembly(),
            DataAssembly(isStoredInMemoryOnly: true)
        ])
    }
}
