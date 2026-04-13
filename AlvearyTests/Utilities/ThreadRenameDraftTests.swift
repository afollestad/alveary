import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ThreadRenameDraftTests: XCTestCase {
    func testInitPopulatesFromThread() throws {
        let container = try ModelContainer(
            for: AgentThread.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let thread = AgentThread(name: "Refactor Chat Input")
        context.insert(thread)
        try context.save()

        let draft = ThreadRenameDraft(thread: thread)
        XCTAssertEqual(draft.currentDisplayName, "Refactor Chat Input")
        XCTAssertEqual(draft.title, "Refactor Chat Input")
        XCTAssertTrue(draft.canSave)
        XCTAssertEqual(draft.persistedName, "Refactor Chat Input")
    }

    func testCanSaveIsFalseForBlankTitle() throws {
        let container = try ModelContainer(
            for: AgentThread.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        try context.save()

        var draft = ThreadRenameDraft(thread: thread)
        draft.title = "   "
        XCTAssertFalse(draft.canSave)
        XCTAssertNil(draft.persistedName)
    }

    func testTrimmedTitleStripsWhitespace() throws {
        let container = try ModelContainer(
            for: AgentThread.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        try context.save()

        var draft = ThreadRenameDraft(thread: thread)
        draft.title = "  New Name  "
        XCTAssertEqual(draft.trimmedTitle, "New Name")
        XCTAssertEqual(draft.persistedName, "New Name")
    }
}
