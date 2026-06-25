@preconcurrency import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum AppShotPermission: CaseIterable, Sendable {
    case accessibility
    case inputMonitoring
    case screenRecording

    var title: String {
        switch self {
        case .accessibility:
            return "Accessibility"
        case .inputMonitoring:
            return "Input Monitoring"
        case .screenRecording:
            return "Screen Recording"
        }
    }

    var isAllowed: Bool {
        switch self {
        case .accessibility:
            return Self.accessibilityProbeIsAllowed()
        case .inputMonitoring:
            return CGPreflightListenEventAccess()
        case .screenRecording:
            return Self.screenRecordingProbeIsAllowed()
        }
    }

    fileprivate var settingsAnchor: String {
        switch self {
        case .accessibility:
            return "Privacy_Accessibility"
        case .inputMonitoring:
            return "Privacy_ListenEvent"
        case .screenRecording:
            return "Privacy_ScreenCapture"
        }
    }

    private static func accessibilityProbeIsAllowed() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.contains { runningApplication in
            guard runningApplication.processIdentifier != currentProcessIdentifier,
                  runningApplication.activationPolicy == .regular else {
                return false
            }

            let applicationElement = AXUIElementCreateApplication(runningApplication.processIdentifier)
            var windows: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(
                applicationElement,
                kAXWindowsAttribute as CFString,
                &windows
            )
            return error == .success
        }
    }

    private static func screenRecordingProbeIsAllowed() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        // Screen Recording preflight can stay false after System Settings changes until restart.
        // Readable foreign window titles are also gated by Screen Recording and do not prompt.
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            CGWindowID(0)
        ) as? [[String: Any]] else {
            return false
        }
        return windowInfo.contains { hasReadableForeignWindowMetadata($0) }
    }

    static func hasReadableForeignWindowMetadata(_ windowInfo: [String: Any]) -> Bool {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        guard let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue,
              layer == 0,
              let ownerProcessIdentifier = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.intValue,
              ownerProcessIdentifier != currentProcessIdentifier else {
            return false
        }

        return windowInfo.keys.contains(kCGWindowName as String)
    }
}

struct AppShotPermissionSnapshot: Equatable, Sendable {
    var accessibilityAllowed: Bool
    var inputMonitoringAllowed: Bool
    var screenRecordingAllowed: Bool

    static var current: AppShotPermissionSnapshot {
        makeCurrent()
    }

    static func makeCurrent(
        accessibilityAllowed: Bool? = nil,
        inputMonitoringAllowed: Bool? = nil,
        screenRecordingAllowed: Bool? = nil
    ) -> AppShotPermissionSnapshot {
        AppShotPermissionSnapshot(
            accessibilityAllowed: accessibilityAllowed ?? AppShotPermission.accessibility.isAllowed,
            inputMonitoringAllowed: inputMonitoringAllowed ?? AppShotPermission.inputMonitoring.isAllowed,
            screenRecordingAllowed: screenRecordingAllowed ?? AppShotPermission.screenRecording.isAllowed
        )
    }

    func isAllowed(_ permission: AppShotPermission) -> Bool {
        switch permission {
        case .accessibility:
            return accessibilityAllowed
        case .inputMonitoring:
            return inputMonitoringAllowed
        case .screenRecording:
            return screenRecordingAllowed
        }
    }
}

@MainActor
enum AppShotPermissionRequester {
    @discardableResult
    static func openSettings(for permission: AppShotPermission) -> Bool {
        for url in settingsURLs(for: permission) where NSWorkspace.shared.open(url) {
            return true
        }
        return false
    }

    private static func settingsURLs(for permission: AppShotPermission) -> [URL] {
        [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(permission.settingsAnchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsAnchor)"
        ]
        .compactMap(URL.init(string:))
    }
}

extension AppShotCaptureError {
    var missingPermission: AppShotPermission? {
        switch self {
        case .accessibilityPermissionMissing:
            return .accessibility
        case .screenRecordingPermissionMissing:
            return .screenRecording
        case .disabled,
             .noTargetWindow,
             .noReliableScreenCaptureMatch,
             .screenshotEncodingFailed,
             .unsupportedProvider,
             .claudeScreenshotUnreadable:
            return nil
        }
    }
}

#if DEBUG
@MainActor
enum AppShotPermissionDiagnostics {
    static func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report(), forType: .string)
    }

    static func report() -> String {
        let bundleURL = Bundle.main.bundleURL
        let executableURL = Bundle.main.executableURL
        let snapshot = AppShotPermissionSnapshot.current
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        let foreignWindows = foreignWindowMetadataSummary()

        return """
        # App Shot Permission Diagnostics

        Bundle identifier: \(Bundle.main.bundleIdentifier ?? "<nil>")
        Bundle URL: \(bundleURL.path)
        Executable URL: \(executableURL?.path ?? "<nil>")
        Process identifier: \(processIdentifier)
        Running app executable: \(NSRunningApplication.current.executableURL?.path ?? "<nil>")

        ## Shared Permission Snapshot
        Accessibility: \(snapshot.accessibilityAllowed)
        Input Monitoring: \(snapshot.inputMonitoringAllowed)
        Screen Recording: \(snapshot.screenRecordingAllowed)

        ## Raw Permission Probes
        AXIsProcessTrusted: \(AXIsProcessTrusted())
        Accessibility fallback: \(AppShotPermission.accessibility.isAllowed)
        CGPreflightListenEventAccess: \(CGPreflightListenEventAccess())
        CGPreflightScreenCaptureAccess: \(CGPreflightScreenCaptureAccess())
        Screen Recording fallback: \(AppShotPermission.screenRecording.isAllowed)
        Foreign windows with readable name metadata: \(foreignWindows.readableCount)
        Foreign candidate windows: \(foreignWindows.candidateCount)

        ## Code Signing
        \(codeSigningReport(for: bundleURL))
        """
    }

    private static func foreignWindowMetadataSummary() -> (candidateCount: Int, readableCount: Int) {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            CGWindowID(0)
        ) as? [[String: Any]] else {
            return (0, 0)
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let candidates = windowInfo.filter { info in
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  let ownerProcessIdentifier = (info[kCGWindowOwnerPID as String] as? NSNumber)?.intValue else {
                return false
            }
            return ownerProcessIdentifier != currentProcessIdentifier
        }
        return (
            candidateCount: candidates.count,
            readableCount: candidates.filter { AppShotPermission.hasReadableForeignWindowMetadata($0) }.count
        )
    }

    private static func codeSigningReport(for bundleURL: URL) -> String {
        [
            runCodesign(arguments: ["-dv", "--verbose=4", bundleURL.path]),
            runCodesign(arguments: ["-d", "-r-", bundleURL.path])
        ]
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runCodesign(arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "codesign \(arguments.joined(separator: " ")) failed: \(error.localizedDescription)"
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? "<invalid codesign output>"
    }
}
#endif
