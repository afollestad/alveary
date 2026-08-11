import Foundation
import Observation

enum MenuBarCommandKind: Equatable, Sendable {
    case newThread
    case openSettings
}

/// A menu bar pick waiting for the root to act on it. The `id` makes two identical picks
/// distinct values, so choosing the same item twice in a row still fires — the same reason
/// `AppState.CommandRequest` carries one.
struct MenuBarCommandRequest: Equatable, Sendable, Identifiable {
    let id: UUID
    let kind: MenuBarCommandKind
}

/// Carries status-menu picks to the root, which owns `AppState`.
///
/// `MenuBarController` lives in AppKit-land and cannot reach `AppState`, so it enqueues here and
/// `ContentView` drains it — the same shape as `NotificationRouter`. Enqueuing before the window
/// mounts is fine: `ContentView.onAppear` replays whatever is pending.
@MainActor
@Observable
final class MenuBarCommandRouter {
    private(set) var pendingCommand: MenuBarCommandRequest?

    func requestNewThread() {
        pendingCommand = MenuBarCommandRequest(id: UUID(), kind: .newThread)
    }

    func requestOpenSettings() {
        pendingCommand = MenuBarCommandRequest(id: UUID(), kind: .openSettings)
    }

    func clearPendingIfMatches(_ request: MenuBarCommandRequest) {
        guard pendingCommand == request else {
            return
        }
        pendingCommand = nil
    }
}
