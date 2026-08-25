@preconcurrency import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testComposerPlusMenuCompactContent() {
        assertMacSnapshot(
            ComposerPlusMenuSnapshot(),
            size: CGSize(width: 244, height: 121),
            named: "composer_plus_menu_compact_content",
            colorScheme: .dark
        )
    }

    func testComposerPlusMenuWithAppShotRowContent() {
        assertMacSnapshot(
            ComposerPlusMenuSnapshot(appShotAppName: "Xcode", appShotAppIcon: composerPlusMenuAppShotIcon()),
            size: CGSize(width: 244, height: 157),
            named: "composer_plus_menu_app_shot_row_content",
            colorScheme: .dark
        )
    }
}

private struct ComposerPlusMenuSnapshot: NSViewControllerRepresentable {
    var appShotAppName: String?
    var appShotAppIcon: NSImage?

    func makeNSViewController(context: Context) -> ComposerPlusMenuViewController {
        ComposerPlusMenuViewController(configuration: .init(
            isGoalModeArmed: false,
            isGoalModeToggleEnabled: true,
            goalModeDisabledTooltip: nil,
            isPlanModeEnabled: true,
            isPlanModeToggleEnabled: true,
            planModeDisabledTooltip: nil,
            onAddPhotosAndFiles: {},
            appShotAppName: appShotAppName,
            appShotAppIcon: appShotAppIcon,
            onAttachAppShot: {},
            onPlanModeChange: { _ in },
            onGoalModeChange: { _ in }
        ))
    }

    func updateNSViewController(_ controller: ComposerPlusMenuViewController, context: Context) {}
}

/// Solid-color stand-in for a real app icon so the baseline does not depend on installed apps.
@MainActor
private func composerPlusMenuAppShotIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 128, height: 128))
    image.lockFocus()
    appearanceStableFixtureFillColor(.systemIndigo).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 128, height: 128), xRadius: 26, yRadius: 26).fill()
    image.unlockFocus()
    return image
}
