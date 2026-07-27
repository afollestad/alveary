@preconcurrency import AppKit
import ApplicationServices
import Foundation
import Observation

struct AppShotWindowTarget: @unchecked Sendable {
    let appName: String
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let windowTitle: String
    let windowBounds: CGRect?
    let axWindow: AXUIElement
}

/// The app an app shot would capture right now, described for display before any capture runs.
///
/// `icon` comes straight from `NSRunningApplication`, which AppKit already holds for a live
/// process, so publishing it costs no LaunchServices query and no bundle read. Display surfaces
/// scale it to their own slot instead of mutating the image.
struct AppShotAttachableApp: Equatable {
    let appName: String
    let bundleIdentifier: String
    let icon: NSImage?

    /// The icon is derived from the same running app, so identity alone decides equality.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.appName == rhs.appName && lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

enum AppShotCaptureError: LocalizedError, Equatable {
    case disabled
    case accessibilityPermissionMissing
    case screenRecordingPermissionMissing
    case noTargetWindow
    case noReliableScreenCaptureMatch
    case screenshotEncodingFailed
    case unsupportedProvider(String)
    case claudeScreenshotUnreadable(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "App shots are disabled in Settings."
        case .accessibilityPermissionMissing:
            return "Alveary needs Accessibility permission to read the target window."
        case .screenRecordingPermissionMissing:
            return "Alveary needs Screen Recording permission to capture the target window."
        case .noTargetWindow:
            return "No non-Alveary window is available for an app shot."
        case .noReliableScreenCaptureMatch:
            return "Could not reliably match the Accessibility window to a screen-capture window."
        case .screenshotEncodingFailed:
            return "Could not encode the app-shot screenshot."
        case .unsupportedProvider(let providerID):
            return "App shots are not supported for \(providerID)."
        case .claudeScreenshotUnreadable(let path):
            return "Claude cannot read the app-shot screenshot at \(path)."
        }
    }
}

@MainActor
@Observable
final class AppShotTargetTracker {
    // Refreshed on every activation, so keeping it untracked avoids per-app-switch observation work
    // for a value no view can read.
    @ObservationIgnored private var lastNonAlvearyTarget: AppShotWindowTarget?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    private let workspace: NSWorkspace
    private let bundleIdentifier: String

    /// The app an app shot would capture right now, or `nil` when no window is available.
    private(set) var attachableApp: AppShotAttachableApp?

    init(
        workspace: NSWorkspace = .shared,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.afollestad.alveary"
    ) {
        self.workspace = workspace
        self.bundleIdentifier = bundleIdentifier
    }

    func start() {
        guard activationObserver == nil else {
            return
        }
        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.recordIfNonAlveary(app)
            }
        }
        terminationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let processIdentifier = app.processIdentifier
            Task { @MainActor in
                self?.forgetTargetIfTerminated(processIdentifier: processIdentifier)
            }
        }
        if let frontmost = workspace.frontmostApplication {
            recordIfNonAlveary(frontmost)
        }
    }

    func stop() {
        for observer in [activationObserver, terminationObserver].compactMap({ $0 }) {
            workspace.notificationCenter.removeObserver(observer)
        }
        activationObserver = nil
        terminationObserver = nil
        // Without observers the candidate can no longer be kept current, so do not keep publishing it.
        lastNonAlvearyTarget = nil
        attachableApp = nil
    }

    func targetForCapture() -> AppShotWindowTarget? {
        if let frontmost = workspace.frontmostApplication,
           frontmost.bundleIdentifier != bundleIdentifier,
           let target = target(for: frontmost) {
            store(target, for: frontmost)
            return target
        }
        return lastNonAlvearyTarget
    }

    private func recordIfNonAlveary(_ app: NSRunningApplication) {
        guard app.bundleIdentifier != bundleIdentifier,
              let target = target(for: app) else {
            return
        }
        store(target, for: app)
    }

    /// Caches the capture target and republishes the display-facing candidate.
    ///
    /// The candidate is only reassigned when its identity actually changes. Observation fires on
    /// every set and app activation fires on every app switch, so an unguarded assignment would
    /// re-render every observing view each time the user alt-tabs.
    private func store(_ target: AppShotWindowTarget, for app: NSRunningApplication) {
        // The capture target always takes the freshest window; only the display candidate is guarded.
        lastNonAlvearyTarget = target
        let candidate = AppShotAttachableApp(
            appName: target.appName,
            bundleIdentifier: target.bundleIdentifier,
            icon: app.icon
        )
        guard attachableApp != candidate else {
            return
        }
        attachableApp = candidate
    }

    private func forgetTargetIfTerminated(processIdentifier: pid_t) {
        guard lastNonAlvearyTarget?.processIdentifier == processIdentifier else {
            return
        }
        lastNonAlvearyTarget = nil
        attachableApp = nil
    }

    private func target(for app: NSRunningApplication) -> AppShotWindowTarget? {
        guard let bundleIdentifier = app.bundleIdentifier else {
            return nil
        }
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        let window = Self.copyAttribute(kAXFocusedWindowAttribute, from: applicationElement) as AXUIElement?
            ?? Self.firstWindow(from: applicationElement)
        guard let window else {
            return nil
        }
        let title = (Self.copyAttribute(kAXTitleAttribute, from: window) as String?) ?? ""
        return AppShotWindowTarget(
            appName: app.localizedName ?? bundleIdentifier,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: app.processIdentifier,
            windowTitle: title,
            windowBounds: Self.windowBounds(window),
            axWindow: window
        )
    }

    nonisolated static func copyAttribute<T>(_ attribute: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return nil
        }
        return value as? T
    }

    private static func firstWindow(from applicationElement: AXUIElement) -> AXUIElement? {
        let windows = copyAttribute(kAXWindowsAttribute, from: applicationElement) as [AXUIElement]?
        return windows?.first
    }

    private static func windowBounds(_ window: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(kAXPositionAttribute, from: window) as AXValue?,
              let sizeValue = copyAttribute(kAXSizeAttribute, from: window) as AXValue? else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue, .cgPoint, &position)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
