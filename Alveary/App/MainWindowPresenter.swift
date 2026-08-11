@preconcurrency import AppKit
import Foundation

/// The single owner of "bring Alveary forward", including re-creating the window after the user
/// closes it.
///
/// The app now outlives its last window, so revealing it can mean two different things: order the
/// existing window front, or ask SwiftUI to build the scene again. Only the view tree can do the
/// latter — `ContentView` registers `@Environment(\.openWindow)` here at mount, and that action
/// stays valid after the window closes.
@MainActor
final class MainWindowPresenter {
    /// The `Window("Alveary", id:)` scene id.
    static let sceneID = "main"
    /// The title that scene gives its window; the app has other windows (the DEBUG raw-transcript
    /// one, system panels) that must not be mistaken for it.
    private static let windowTitle = "Alveary"

    private var openMainWindow: (@MainActor () -> Void)?

    func register(openMainWindow: @escaping @MainActor () -> Void) {
        self.openMainWindow = openMainWindow
    }

    /// The scene's window, or `nil` when the user has closed it.
    ///
    /// Deliberately strict — no `NSApp.mainWindow`/`keyWindow` fallback, because treating a panel
    /// as the main window would leave a closed scene un-recreated.
    var mainWindow: NSWindow? {
        NSApp.windows.first { window in
            window.title == Self.windowTitle && window.canBecomeKey
        }
    }

    func activate() {
        NSApp.unhide(nil)
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            openMainWindow?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Re-creates the window only when the scene is closed.
    ///
    /// Background flows that need the window to exist (app-shot capture routes through
    /// `ContentView`) call this instead of `activate()`, so a capture taken while Alveary is
    /// merely behind another app still does not steal focus.
    func activateIfWindowClosed() {
        guard mainWindow == nil else {
            return
        }
        activate()
    }
}
