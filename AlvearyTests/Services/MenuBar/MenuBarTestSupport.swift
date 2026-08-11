import AppKit
import Foundation
import SwiftData

@testable import Alveary

/// Stands in for `NSStatusBar.system` so tests exercise the real install/uninstall lifecycle
/// without putting an icon in the runner's menu bar.
@MainActor
final class FakeStatusItemFactory {
    private(set) var madeItems: [NSStatusItem] = []
    private(set) var removedItems: [NSStatusItem] = []

    var makeStatusItem: MenuBarController.MakeStatusItem {
        { [weak self] in
            let item = NSStatusItem()
            self?.madeItems.append(item)
            return item
        }
    }

    var removeStatusItem: MenuBarController.RemoveStatusItem {
        { [weak self] item in
            self?.removedItems.append(item)
        }
    }
}

@MainActor
struct MenuBarControllerTestFixture {
    let statusItemFactory = FakeStatusItemFactory()
    let notificationRouter = NotificationRouter()
    let commandRouter = MenuBarCommandRouter()
    let mainWindowPresenter = MainWindowPresenter()
    let notificationCenter = NotificationCenter()
    let settingsService: InMemorySettingsService
    let recentThreadsProvider: MenuBarRecentThreadsProvider
    let terminateCount = TerminateCounter()
    let container: ModelContainer
    let context: ModelContext

    init(settings: AppSettings = AppSettings()) throws {
        settingsService = InMemorySettingsService(current: settings)
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        recentThreadsProvider = MenuBarRecentThreadsProvider(modelContext: context)
    }

    func makeController() -> MenuBarController {
        MenuBarController(
            recentThreadsProvider: recentThreadsProvider,
            notificationRouter: notificationRouter,
            commandRouter: commandRouter,
            mainWindowPresenter: mainWindowPresenter,
            settingsService: settingsService,
            notificationCenter: notificationCenter,
            makeStatusItem: statusItemFactory.makeStatusItem,
            removeStatusItem: statusItemFactory.removeStatusItem,
            terminate: terminateCount.record
        )
    }

    func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 100_000 + offset)
    }

    func insertThread(name: String, conversationID: String, modifiedAt: Date) {
        let thread = AgentThread(name: name, mode: .task)
        thread.modifiedAt = modifiedAt
        context.insert(thread)
        let conversation = Conversation(id: conversationID, isMain: true)
        conversation.thread = thread
        context.insert(conversation)
        try? context.save()
    }

    @MainActor
    final class TerminateCounter {
        private(set) var count = 0

        func record() {
            count += 1
        }
    }
}
