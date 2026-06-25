@preconcurrency import AppKit
import ApplicationServices
import Foundation

struct AppShotWindowTarget: @unchecked Sendable {
    let appName: String
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let windowTitle: String
    let windowBounds: CGRect?
    let axWindow: AXUIElement
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
final class AppShotTargetTracker {
    private var lastNonAlvearyTarget: AppShotWindowTarget?
    private var activationObserver: NSObjectProtocol?
    private let workspace: NSWorkspace
    private let bundleIdentifier: String

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
        if let frontmost = workspace.frontmostApplication {
            recordIfNonAlveary(frontmost)
        }
    }

    func stop() {
        if let activationObserver {
            workspace.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    func targetForCapture() -> AppShotWindowTarget? {
        if let frontmost = workspace.frontmostApplication,
           frontmost.bundleIdentifier != bundleIdentifier,
           let target = target(for: frontmost) {
            lastNonAlvearyTarget = target
            return target
        }
        return lastNonAlvearyTarget
    }

    private func recordIfNonAlveary(_ app: NSRunningApplication) {
        guard app.bundleIdentifier != bundleIdentifier,
              let target = target(for: app) else {
            return
        }
        lastNonAlvearyTarget = target
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
