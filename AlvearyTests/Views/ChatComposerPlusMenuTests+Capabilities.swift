import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerPlusMenuTests {
    func testUnavailablePhotoInputShowsOnlyFilesAndExcludesImagesFromPicker() {
        var configuration = ComposerPlusMenuViewController.Configuration(
            isGoalModeArmed: false, isGoalModeToggleEnabled: false, goalModeDisabledTooltip: nil,
            isPlanModeEnabled: false, isPlanModeToggleEnabled: true, planModeDisabledTooltip: nil,
            onAddPhotosAndFiles: {}, onPlanModeChange: { _ in }, onGoalModeChange: { _ in }
        )
        configuration.allowsPhotoAttachments = false
        let controller = ComposerPlusMenuViewController(configuration: configuration)
        controller.loadViewIfNeeded()
        let labels = composerMenuRows(in: controller.view).map { $0.accessibilityLabel() }
        XCTAssertTrue(labels.contains("Add files"))
        XCTAssertFalse(labels.contains("Add photos and files"))
        let image = URL(fileURLWithPath: "/tmp/image.png")
        XCTAssertFalse(ComposerAttachmentOpenPanel.allowsURL(image, allowsPhotoAttachments: false))
        XCTAssertTrue(ComposerAttachmentOpenPanel.allowsURL(image, allowsPhotoAttachments: true))
        XCTAssertTrue(ComposerAttachmentOpenPanel.allowsURL(URL(fileURLWithPath: "/tmp/source.swift"), allowsPhotoAttachments: false))
    }

}

@MainActor
private func composerMenuRows(in view: NSView) -> [ComposerPlusMenuRowView] {
    view.subviews.flatMap { child in
        (child as? ComposerPlusMenuRowView).map { [$0] } ?? composerMenuRows(in: child)
    }
}
