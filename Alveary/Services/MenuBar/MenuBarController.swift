@preconcurrency import AppKit
import Foundation

/// Owns Alveary's system menu bar status item.
///
/// Every action routes through the injected routers and `MainWindowPresenter`; the controller
/// never touches `AppState`, which only the view tree can see. The status-item factory pair is
/// the test seam — hosted tests and unit tests run the real install/uninstall lifecycle against
/// a fake, so no icon lands in a test runner's menu bar.
@MainActor
final class MenuBarController: NSObject {
    typealias MakeStatusItem = @MainActor () -> NSStatusItem
    typealias RemoveStatusItem = @MainActor (NSStatusItem) -> Void

    /// The one place the asset catalog name appears.
    static let templateImageName = "AlvearyMenuBarTemplate"

    let recentThreadsProvider: MenuBarRecentThreadsProvider
    let notificationRouter: NotificationRouter
    let commandRouter: MenuBarCommandRouter
    let mainWindowPresenter: MainWindowPresenter
    let terminate: @MainActor () -> Void

    private let settingsService: any SettingsService
    private let notificationCenter: NotificationCenter
    private let makeStatusItem: MakeStatusItem
    private let removeStatusItem: RemoveStatusItem
    private var statusItem: NSStatusItem?
    private var settingsObserver: NSObjectProtocol?

    init(
        recentThreadsProvider: MenuBarRecentThreadsProvider,
        notificationRouter: NotificationRouter,
        commandRouter: MenuBarCommandRouter,
        mainWindowPresenter: MainWindowPresenter,
        settingsService: any SettingsService,
        notificationCenter: NotificationCenter = .default,
        makeStatusItem: @escaping MakeStatusItem = { NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) },
        removeStatusItem: @escaping RemoveStatusItem = { NSStatusBar.system.removeStatusItem($0) },
        terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        self.recentThreadsProvider = recentThreadsProvider
        self.notificationRouter = notificationRouter
        self.commandRouter = commandRouter
        self.mainWindowPresenter = mainWindowPresenter
        self.settingsService = settingsService
        self.notificationCenter = notificationCenter
        self.makeStatusItem = makeStatusItem
        self.removeStatusItem = removeStatusItem
        self.terminate = terminate
        super.init()
    }

    var isInstalled: Bool {
        statusItem != nil
    }

    /// Applies the current setting and keeps following it, so the toggle takes effect live.
    func start() {
        applySettings()
        guard settingsObserver == nil else {
            return
        }
        settingsObserver = notificationCenter.addObserver(
            forName: .appSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applySettings()
            }
        }
    }

    /// Synchronous, because shutdown must not queue a `Task` hop (see `Alveary/App/AGENTS.md`).
    func stop() {
        if let settingsObserver {
            notificationCenter.removeObserver(settingsObserver)
        }
        settingsObserver = nil
        uninstall()
    }

    func applySettings() {
        if settingsService.current.showsMenuBarIcon {
            install()
        } else {
            uninstall()
        }
    }

    func install() {
        guard statusItem == nil else {
            return
        }
        let item = makeStatusItem()
        if let button = item.button {
            let image = NSImage(named: Self.templateImageName)
            image?.isTemplate = true
            button.image = image
            button.setAccessibilityLabel("Alveary")
            button.toolTip = "Alveary"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func uninstall() {
        guard let statusItem else {
            return
        }
        statusItem.menu?.delegate = nil
        statusItem.menu = nil
        removeStatusItem(statusItem)
        self.statusItem = nil
    }
}
