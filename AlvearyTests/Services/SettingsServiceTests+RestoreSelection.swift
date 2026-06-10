import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SettingsServiceTests {
    func testUserDefaultsSettingsServiceRestoreSelectionUpdateDoesNotNotify() throws {
        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(defaults: defaults)
        let container = try makeModelContainer()
        let context = ModelContext(container)
        let project = Project(path: "/tmp/\(UUID().uuidString)", name: "Fixture")
        let conversation = Conversation(title: "Main", provider: "claude")
        let thread = AgentThread(name: "Primary", project: project, conversations: [conversation])
        project.threads.append(thread)
        context.insert(project)
        try context.save()

        let expectation = expectation(description: "restore selection does not notify")
        expectation.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: .appSettingsChanged,
            object: service,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        service.updateRestoreSelection(
            threadID: thread.persistentModelID,
            conversationID: conversation.persistentModelID
        )

        wait(for: [expectation], timeout: 0.1)
        let reloadedService = UserDefaultsSettingsService(defaults: defaults)
        XCTAssertEqual(reloadedService.current.lastOpenThreadID, thread.persistentModelID)
        XCTAssertEqual(reloadedService.current.lastOpenConversationID, conversation.persistentModelID)
    }

    func testUserDefaultsSettingsServiceNormalUpdateStillNotifies() throws {
        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(defaults: defaults)

        let expectation = expectation(description: "settings update notifies")
        let observer = NotificationCenter.default.addObserver(
            forName: .appSettingsChanged,
            object: service,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        service.update {
            $0.branchPrefix = "feature/"
        }

        wait(for: [expectation], timeout: 0.5)
    }
}
