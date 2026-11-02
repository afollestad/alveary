@preconcurrency import AppKit
import Foundation

/// Owns Alveary's system menu bar status item.
///
/// Every action routes through the injected routers and `MainWindowPresenter`; the controller
/// never touches `AppState`, which only the view tree can see. The status-item factory pair is
/// the test seam — hosted tests and unit tests run the real install/uninstall lifecycle against
/// a fake, so no icon lands in a test runner's menu bar.
///
/// It also drives `reviewRequestsMonitor` from the same settings and badges the icon from it.
@MainActor
final class MenuBarController: NSObject {
    typealias MakeStatusItem = @MainActor () -> NSStatusItem
    typealias RemoveStatusItem = @MainActor (NSStatusItem) -> Void

    /// The one place the asset catalog name appears.
    static let templateImageName = "AlvearyMenuBarTemplate"

    let recentThreadsProvider: MenuBarRecentThreadsProvider
    let reviewRequestsMonitor: MenuBarReviewRequestsMonitor
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
        reviewRequestsMonitor: MenuBarReviewRequestsMonitor,
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
        self.reviewRequestsMonitor = reviewRequestsMonitor
        self.notificationRouter = notificationRouter
        self.commandRouter = commandRouter
        self.mainWindowPresenter = mainWindowPresenter
        self.settingsService = settingsService
        self.notificationCenter = notificationCenter
        self.makeStatusItem = makeStatusItem
        self.removeStatusItem = removeStatusItem
        self.terminate = terminate
        super.init()
        reviewRequestsMonitor.onChange = { [weak self] in
            self?.updateStatusButton()
        }
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
        reviewRequestsMonitor.stop()
        uninstall()
    }

    func applySettings() {
        let settings = settingsService.current
        if settings.showsMenuBarIcon {
            install()
        } else {
            uninstall()
        }
        reviewRequestsMonitor.configure(
            isActive: Self.listsPullRequestsNeedingReview(settings),
            interval: settings.menuBarPullRequestRefreshInterval.duration
        )
    }

    /// The section needs somewhere to show — the icon — and the pull-request integration itself,
    /// which gates every automatic load.
    static func listsPullRequestsNeedingReview(_ settings: AppSettings) -> Bool {
        settings.showsMenuBarIcon
            && settings.menuBarShowsPullRequestsNeedingReview
            && settings.pullRequestsEnabled
    }

    /// A sleep can outlast the poll interval, and the network is not back the instant the
    /// machine wakes, so `AppDelegate`'s delayed wake refresh asks for a fresh read.
    func refreshAfterWake() {
        reviewRequestsMonitor.refreshNow()
    }

    func install() {
        guard statusItem == nil else {
            return
        }
        let item = makeStatusItem()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusButton()
    }

    /// What the status button shows: badged, and saying why in its accessibility label and
    /// tooltip, while any listed pull request waits on the viewer.
    struct StatusButtonPresentation: Equatable {
        let isBadged: Bool
        let label: String
    }

    var statusButtonPresentation: StatusButtonPresentation {
        let count = reviewRequestsMonitor.visibleSummaries.count
        guard count > 0 else {
            return StatusButtonPresentation(isBadged: false, label: "Alveary")
        }
        let waiting = count == 1 ? "1 pull request needs" : "\(count) pull requests need"
        return StatusButtonPresentation(isBadged: true, label: "Alveary — \(waiting) review")
    }

    func updateStatusButton() {
        guard let button = statusItem?.button else {
            return
        }
        let presentation = statusButtonPresentation
        button.image = MenuBarStatusIcon.image(badged: presentation.isBadged)
        button.setAccessibilityLabel(presentation.label)
        button.toolTip = presentation.label
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
