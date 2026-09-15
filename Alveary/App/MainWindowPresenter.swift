@preconcurrency import AppKit
import Foundation

/// The single owner of "bring Alveary forward", including re-creating the window after the user
/// closes it.
///
/// The app now outlives its last window, so revealing it can mean two different things: order the
/// existing window front, or ask SwiftUI to build the scene again. Only the view tree can do the
/// latter — `ContentView` registers the resolved `OpenWindowAction` here at mount and keeps it
/// separate from the window registration so closing the window does not discard the opener.
@MainActor
final class MainWindowPresenter {
    /// The `Window("Alveary", id:)` scene id.
    static let sceneID = "main"
    private var openMainWindow: (@MainActor () -> Void)?

    /// Only the main scene's bridge registers a window, and it unregisters on close even if
    /// SwiftUI retains that window. `NSApp.windows` and `canBecomeKey` still include such closed
    /// windows; visibility also cannot distinguish a closed scene from a hidden or minimized one.
    private(set) weak var mainWindow: NSWindow?

    func register(openMainWindow: @escaping @MainActor () -> Void) {
        self.openMainWindow = openMainWindow
    }

    func register(window: NSWindow) {
        mainWindow = window
    }

    /// A replaced scene can finish closing or detaching after its successor has registered.
    func unregister(window: NSWindow) {
        guard mainWindow === window else {
            return
        }
        mainWindow = nil
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
