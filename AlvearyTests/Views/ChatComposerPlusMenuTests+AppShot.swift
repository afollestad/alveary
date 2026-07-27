import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerPlusMenuTests {
    func testPlusMenuOmitsAppShotRowWhenNoAppIsAttachable() {
        let controller = ComposerPlusMenuViewController(configuration: appShotPlusMenuConfiguration())
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let rows = controller.view.appShotDescendants(of: ComposerPlusMenuRowView.self)
        XCTAssertEqual(rows.count, 3)
        XCTAssertNil(rows.first { $0.accessibilityLabel()?.hasPrefix("Attach ") == true })
        XCTAssertEqual(controller.preferredContentSize, ComposerPlusMenuMetrics.contentSize)
    }

    func testPlusMenuShowsNamedAppShotRowWithSuppliedIcon() throws {
        let icon = appShotStubIcon()
        let controller = ComposerPlusMenuViewController(configuration: appShotPlusMenuConfiguration(
            appShotAppName: "Xcode",
            appShotAppIcon: icon
        ))
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let appShotRow = try XCTUnwrap(
            controller.view.appShotDescendants(of: ComposerPlusMenuRowView.self).first {
                $0.accessibilityLabel() == "Attach Xcode"
            }
        )
        let label = try XCTUnwrap(appShotRow.appShotDescendants(of: NSTextField.self).first)
        XCTAssertEqual(label.stringValue, "Attach Xcode")

        let iconView = try XCTUnwrap(appShotRow.appShotDescendants(of: NSImageView.self).first)
        XCTAssertIdentical(iconView.image, icon)
        // Full-resolution app icons must scale into the shared slot instead of overflowing it.
        XCTAssertEqual(iconView.imageScaling, .scaleProportionallyDown)
    }

    func testPlusMenuPlacesAppShotRowBetweenAddFilesAndDivider() throws {
        let controller = ComposerPlusMenuViewController(configuration: appShotPlusMenuConfiguration(
            appShotAppName: "Xcode",
            appShotAppIcon: appShotStubIcon()
        ))
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let rows = controller.view.appShotDescendants(of: ComposerPlusMenuRowView.self)
        let addFilesRow = try XCTUnwrap(rows.first { $0.accessibilityLabel() == "Add photos and files" })
        let appShotRow = try XCTUnwrap(rows.first { $0.accessibilityLabel() == "Attach Xcode" })
        let divider = try XCTUnwrap(controller.view.appShotDescendants(of: AppKitComposerPopoverDividerView.self).first)

        // The surface is flipped, so increasing `y` runs down the menu.
        XCTAssertGreaterThanOrEqual(appShotRow.frame.minY, addFilesRow.frame.maxY)
        XCTAssertLessThanOrEqual(appShotRow.frame.maxY, divider.frame.minY)
    }

    func testPlusMenuGrowsToFitAppShotRowWithoutClippingLaterRows() throws {
        let controller = ComposerPlusMenuViewController(configuration: appShotPlusMenuConfiguration(
            appShotAppName: "Xcode",
            appShotAppIcon: appShotStubIcon()
        ))
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let expectedGrowth = ComposerPlusMenuMetrics.rowHeight + ComposerPlusMenuMetrics.dividerSpacing
        XCTAssertEqual(
            controller.preferredContentSize.height - ComposerPlusMenuMetrics.contentSize.height,
            expectedGrowth
        )
        XCTAssertEqual(controller.preferredContentSize.width, ComposerPlusMenuMetrics.contentSize.width)

        let planRow = try XCTUnwrap(
            controller.view.appShotDescendants(of: ComposerPlusMenuRowView.self).first {
                $0.accessibilityLabel() == "Toggle plan mode"
            }
        )
        XCTAssertLessThanOrEqual(planRow.frame.maxY, controller.view.bounds.height)
    }

    func testPlusMenuAppShotRowRoutesPressAndKeyboardActivation() throws {
        var attachCount = 0
        let controller = ComposerPlusMenuViewController(configuration: appShotPlusMenuConfiguration(
            appShotAppName: "Xcode",
            appShotAppIcon: appShotStubIcon(),
            onAttachAppShot: { attachCount += 1 }
        ))
        controller.loadViewIfNeeded()

        let appShotRow = try XCTUnwrap(
            controller.view.appShotDescendants(of: ComposerPlusMenuRowView.self).first {
                $0.accessibilityLabel() == "Attach Xcode"
            }
        )

        XCTAssertTrue(appShotRow.accessibilityPerformPress())
        XCTAssertEqual(attachCount, 1)

        appShotRow.keyDown(with: appShotKeyEvent(keyCode: 36))
        appShotRow.keyDown(with: appShotKeyEvent(keyCode: 49))
        XCTAssertEqual(attachCount, 3)
    }

    func testPlusMenuClampsLongAppNamesInsideTheRow() throws {
        let controller = ComposerPlusMenuViewController(configuration: appShotPlusMenuConfiguration(
            appShotAppName: "Visual Studio Code - Insiders",
            appShotAppIcon: appShotStubIcon()
        ))
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(origin: .zero, size: controller.preferredContentSize)
        controller.view.layoutSubtreeIfNeeded()

        let appShotRow = try XCTUnwrap(
            controller.view.appShotDescendants(of: ComposerPlusMenuRowView.self).first {
                $0.accessibilityLabel()?.hasPrefix("Attach ") == true
            }
        )
        let label = try XCTUnwrap(appShotRow.appShotDescendants(of: NSTextField.self).first)

        // A caller-supplied app name must truncate rather than draw past the popover edge.
        XCTAssertLessThanOrEqual(label.frame.maxX, appShotRow.bounds.width)
        XCTAssertEqual(label.lineBreakMode, .byTruncatingTail)
        // The full name stays available to assistive technology even when the text truncates.
        XCTAssertEqual(appShotRow.accessibilityLabel(), "Attach Visual Studio Code - Insiders")
    }

    func testAppShotAttachmentOptionComparesByAppNameOnly() {
        let first = ChatComposerActionRowView.AppShotAttachmentOption(appName: "Xcode", icon: appShotStubIcon())
        let second = ChatComposerActionRowView.AppShotAttachmentOption(appName: "Xcode", icon: appShotStubIcon())
        let other = ChatComposerActionRowView.AppShotAttachmentOption(appName: "Safari", icon: nil)

        // Distinct icon instances for the same app must not read as a change, or the composer
        // would reconfigure on every observation pass.
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, other)
    }
}

private func appShotPlusMenuConfiguration(
    appShotAppName: String? = nil,
    appShotAppIcon: NSImage? = nil,
    onAttachAppShot: @escaping () -> Void = {}
) -> ComposerPlusMenuViewController.Configuration {
    .init(
        isGoalModeArmed: false,
        isGoalModeToggleEnabled: true,
        goalModeDisabledTooltip: nil,
        isPlanModeEnabled: false,
        isPlanModeToggleEnabled: true,
        planModeDisabledTooltip: nil,
        onAddPhotosAndFiles: {},
        appShotAppName: appShotAppName,
        appShotAppIcon: appShotAppIcon,
        onAttachAppShot: onAttachAppShot,
        onPlanModeChange: { _ in },
        onGoalModeChange: { _ in }
    )
}

@MainActor
private func appShotStubIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 128, height: 128))
    image.lockFocus()
    NSColor.systemPurple.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 128, height: 128)).fill()
    image.unlockFocus()
    return image
}

private extension NSView {
    func appShotDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.appShotDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}

private func appShotKeyEvent(keyCode: UInt16) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: keyCode == 49 ? " " : "\r",
        charactersIgnoringModifiers: keyCode == 49 ? " " : "\r",
        isARepeat: false,
        keyCode: keyCode
    ) ?? NSEvent()
}
