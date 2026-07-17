@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitComposerAttachmentStripViewTests: XCTestCase {
    func testStripContentMatchesEditorHorizontalInsetAndBackground() throws {
        let imageAttachment = try localImageAttachment(
            id: "plain-image",
            filename: "plain-image.png",
            size: NSSize(width: 120, height: 120)
        )
        let strip = AppKitComposerAttachmentStripView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))

        strip.configure([.image(imageAttachment)])
        strip.frame.size.height = strip.measuredHeight(width: 320)
        strip.layoutSubtreeIfNeeded()

        let imageFrame = try XCTUnwrap(strip.imageTileFramesForTesting.first)
        XCTAssertEqual(imageFrame.minX, AppKitChatComposerEditorController.editorHorizontalPadding, accuracy: 0.5)
        XCTAssertFalse(strip.isOpaque)
        XCTAssertEqual(BlockInputComposerStyle.imagePreviewStripBackgroundColor, .windowBackgroundColor)
    }

    func testMixedAttachmentRowBottomAlignsItems() throws {
        let imageAttachment = try localImageAttachment(
            id: "plain-image",
            filename: "plain-image.png",
            size: NSSize(width: 120, height: 120)
        )
        let fileAttachment = try localFileAttachment(filename: "Oliver's Genetic Report.pdf")
        let appShot = try appShotAttachment(
            id: "app-shot",
            filename: "app-shot.png",
            size: NSSize(width: 400, height: 200)
        )
        let strip = AppKitComposerAttachmentStripView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))

        strip.configure([.image(imageAttachment), .file(fileAttachment), .appShot(appShot)])
        strip.frame.size.height = strip.measuredHeight(width: 900)
        strip.layoutSubtreeIfNeeded()

        let imageFrame = try XCTUnwrap(strip.imageTileFramesForTesting.first)
        let fileFrame = try XCTUnwrap(strip.fileChipFramesForTesting.first)
        let appShotFrame = try XCTUnwrap(strip.appShotCardFramesForTesting.first)
        XCTAssertEqual(appShotFrame.width, 320, accuracy: 0.5)
        XCTAssertEqual(appShotFrame.height, AppKitAppShotAttachmentCardView.composerMaximumSize.height, accuracy: 0.5)
        XCTAssertEqual(imageFrame.maxY, appShotFrame.maxY, accuracy: 0.5)
        XCTAssertEqual(fileFrame.maxY, appShotFrame.maxY, accuracy: 0.5)
        XCTAssertGreaterThan(imageFrame.minY, appShotFrame.minY)
    }

    func testAppShotCardUsesActualImageAspectRatioWhenMeasuring() throws {
        let appShot = try appShotAttachment(
            id: "wide-app-shot",
            filename: "wide-app-shot.png",
            size: NSSize(width: 400, height: 200)
        )
        let strip = AppKitComposerAttachmentStripView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))

        strip.configure([.appShot(appShot)])
        strip.frame.size.height = strip.measuredHeight(width: 500)
        strip.layoutSubtreeIfNeeded()

        let appShotFrame = try XCTUnwrap(strip.appShotCardFramesForTesting.first)
        XCTAssertEqual(appShotFrame.width / appShotFrame.height, 2, accuracy: 0.01)
        XCTAssertEqual(appShotFrame.width, 320, accuracy: 0.5)
        XCTAssertEqual(appShotFrame.height, AppKitAppShotAttachmentCardView.composerMaximumSize.height, accuracy: 0.5)
    }

    func testTallAppShotCardCapsHeightAndPreservesAspectRatioWhenMeasuring() throws {
        let appShot = try appShotAttachment(
            id: "tall-app-shot",
            filename: "tall-app-shot.png",
            size: NSSize(width: 200, height: 400)
        )
        let strip = AppKitComposerAttachmentStripView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))

        strip.configure([.appShot(appShot)])
        strip.frame.size.height = strip.measuredHeight(width: 500)
        strip.layoutSubtreeIfNeeded()

        let appShotFrame = try XCTUnwrap(strip.appShotCardFramesForTesting.first)
        XCTAssertEqual(appShotFrame.width / appShotFrame.height, 0.5, accuracy: 0.01)
        XCTAssertEqual(appShotFrame.width, 80, accuracy: 0.5)
        XCTAssertEqual(appShotFrame.height, AppKitAppShotAttachmentCardView.composerMaximumSize.height, accuracy: 0.5)
    }

    func testNarrowStripWrapsAttachmentsIntoRows() throws {
        let imageAttachment = try localImageAttachment(
            id: "plain-image",
            filename: "narrow-image.png",
            size: NSSize(width: 120, height: 120)
        )
        let fileAttachment = try localFileAttachment(filename: "report.pdf")
        let appShot = try appShotAttachment(
            id: "narrow-app-shot",
            filename: "narrow-app-shot.png",
            size: NSSize(width: 400, height: 200)
        )
        let strip = AppKitComposerAttachmentStripView(frame: NSRect(x: 0, y: 0, width: 360, height: 600))

        strip.configure([.image(imageAttachment), .file(fileAttachment), .appShot(appShot)])
        strip.frame.size.height = strip.measuredHeight(width: 360)
        strip.layoutSubtreeIfNeeded()

        let imageFrame = try XCTUnwrap(strip.imageTileFramesForTesting.first)
        let fileFrame = try XCTUnwrap(strip.fileChipFramesForTesting.first)
        let appShotFrame = try XCTUnwrap(strip.appShotCardFramesForTesting.first)
        XCTAssertEqual(imageFrame.minY, fileFrame.minY, accuracy: 0.5)
        XCTAssertGreaterThan(appShotFrame.minY, fileFrame.maxY)
        XCTAssertLessThanOrEqual(appShotFrame.maxX, 360)
    }

    func testRemoveButtonClickRemovesImagePreview() throws {
        let imageAttachment = try localImageAttachment(
            id: "plain-image",
            filename: "remove-image.png",
            size: NSSize(width: 120, height: 120)
        )
        let mounted = configuredMountedStrip(attachments: [.image(imageAttachment)], width: 320)
        let strip = mounted.strip
        var removedIDs: [String] = []
        var openedIDs: [String] = []
        strip.onRemoveAttachment = { removedIDs.append($0.testingID) }
        strip.onOpenAttachment = { openedIDs.append($0.testingID) }

        try click(strip, at: imageRemoveButtonCenter(in: XCTUnwrap(strip.imageTileFramesForTesting.first)))

        XCTAssertEqual(removedIDs, [imageAttachment.id])
        XCTAssertTrue(openedIDs.isEmpty)
    }

    func testRemoveButtonClickRemovesFilePreview() throws {
        let fileAttachment = try localFileAttachment(filename: "Oliver's Genetic Report.pdf")
        let mounted = configuredMountedStrip(attachments: [.file(fileAttachment)], width: 320)
        let strip = mounted.strip
        var removedIDs: [String] = []
        var openedIDs: [String] = []
        strip.onRemoveAttachment = { removedIDs.append($0.testingID) }
        strip.onOpenAttachment = { openedIDs.append($0.testingID) }

        try click(strip, at: fileRemoveButtonCenter(in: XCTUnwrap(strip.fileChipFramesForTesting.first)))

        XCTAssertEqual(removedIDs, [fileAttachment.id])
        XCTAssertTrue(openedIDs.isEmpty)
    }

    func testFilePreviewClickOpensFilePreview() throws {
        let fileAttachment = try localFileAttachment(filename: "Home_Inspection_Report.pdf")
        let mounted = configuredMountedStrip(attachments: [.file(fileAttachment)], width: 320)
        let strip = mounted.strip
        var removedIDs: [String] = []
        var openedIDs: [String] = []
        strip.onRemoveAttachment = { removedIDs.append($0.testingID) }
        strip.onOpenAttachment = { openedIDs.append($0.testingID) }

        try click(strip, at: center(of: XCTUnwrap(strip.fileChipFramesForTesting.first)))

        XCTAssertEqual(openedIDs, [fileAttachment.id])
        XCTAssertTrue(removedIDs.isEmpty)
    }

    func testClearingInteractionHandlersDisablesAttachmentOpeningAndRemoval() throws {
        let fileAttachment = try localFileAttachment(filename: "locked.pdf")
        let mounted = configuredMountedStrip(attachments: [.file(fileAttachment)], width: 320)
        let strip = mounted.strip
        var interactionCount = 0
        strip.onOpenAttachment = { _ in interactionCount += 1 }
        strip.onRemoveAttachment = { _ in interactionCount += 1 }

        strip.onOpenAttachment = nil
        strip.onRemoveAttachment = nil
        let chip = try XCTUnwrap(strip.fileChipViews.first)
        chip.mouseUp(with: mouseEvent(at: chip.convert(center(of: chip.bounds), to: nil)))

        XCTAssertEqual(interactionCount, 0)
        XCTAssertEqual(chip.accessibilityRole(), .group)
    }

    func testFilePreviewUsesStandaloneDocumentIconAndSmallerTitle() throws {
        let fileAttachment = try localFileAttachment(filename: "Home_Inspection_Report.pdf")
        let mounted = configuredMountedStrip(attachments: [.file(fileAttachment)], width: 320)
        let strip = mounted.strip
        let chip = try XCTUnwrap(strip.fileChipViews.first)

        XCTAssertNotNil(chip.iconImageForTesting)
        XCTAssertEqual(chip.iconFrameForTesting.width, 28, accuracy: 0.5)
        XCTAssertEqual(chip.iconFrameForTesting.height, 32, accuracy: 0.5)
        XCTAssertEqual(chip.titleFontSizeForTesting, 12, accuracy: 0.1)
        XCTAssertEqual(chip.titleFrameForTesting.minX, 46, accuracy: 0.5)
    }

    func testFilePreviewHitTestingUsesCardAcrossIconAndTitle() throws {
        let fileAttachment = try localFileAttachment(filename: "Home_Inspection_Report.pdf")
        let mounted = configuredMountedStrip(attachments: [.file(fileAttachment)], width: 320)
        let strip = mounted.strip
        let chip = try XCTUnwrap(strip.fileChipViews.first)
        let iconPoint = chip.convert(center(of: chip.iconFrameForTesting), to: strip)
        let titlePoint = chip.convert(center(of: chip.titleFrameForTesting), to: strip)

        XCTAssertTrue(strip.hitTest(iconPoint) === chip)
        XCTAssertTrue(strip.hitTest(titlePoint) === chip)
    }

    func testFilePreviewInvalidatesCursorRectsWhenFrameMoves() throws {
        let fileAttachment = try localFileAttachment(filename: "Home_Inspection_Report.pdf")
        let chip = AppKitFileAttachmentChipView(frame: NSRect(x: 0, y: 0, width: 240, height: 76))
        chip.configure(fileAttachment)
        chip.onOpenAttachment = { _ in }
        let window = CursorInvalidationWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hostView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = hostView
        hostView.addSubview(chip)
        window.invalidatedCursorRectViews.removeAll()

        chip.frame = NSRect(x: 40, y: 12, width: 240, height: 76)

        XCTAssertTrue(window.invalidatedCursorRectViews.contains { $0 === chip })
    }

    func testRemoveButtonClickRemovesAppShotPreview() throws {
        let appShot = try appShotAttachment(
            id: "app-shot",
            filename: "remove-app-shot.png",
            size: NSSize(width: 400, height: 200)
        )
        let mounted = configuredMountedStrip(attachments: [.appShot(appShot)], width: 500)
        let strip = mounted.strip
        var removedIDs: [String] = []
        var openedIDs: [String] = []
        strip.onRemoveAttachment = { removedIDs.append($0.testingID) }
        strip.onOpenAttachment = { openedIDs.append($0.testingID) }

        try click(strip, at: appShotRemoveButtonCenter(in: XCTUnwrap(strip.appShotCardFramesForTesting.first)))

        XCTAssertEqual(removedIDs, [appShot.id])
        XCTAssertTrue(openedIDs.isEmpty)
    }

    func testAppShotRemoveButtonClickUsesCurrentBoundsAfterResize() throws {
        let appShot = try appShotAttachment(
            id: "resized-app-shot",
            filename: "resized-app-shot.png",
            size: NSSize(width: 400, height: 200)
        )
        let card = AppKitAppShotAttachmentCardView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        card.configure(appShot)
        var didRemove = false
        var didOpen = false
        card.onRemoveAttachment = {
            didRemove = true
        }
        card.onOpenAttachment = {
            didOpen = true
        }
        let window = NSWindow(
            contentRect: card.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = card
        card.layoutSubtreeIfNeeded()

        card.setFrameSize(NSSize(width: 80, height: 160))
        let removePoint = appShotRemoveButtonCenter(in: card.bounds)
        card.mouseUp(with: mouseEvent(at: card.convert(removePoint, to: nil)))

        XCTAssertTrue(didRemove)
        XCTAssertFalse(didOpen)
    }

    private func configuredMountedStrip(
        attachments: [ComposerAttachment],
        width: CGFloat
    ) -> (strip: AppKitComposerAttachmentStripView, window: NSWindow) {
        let strip = AppKitComposerAttachmentStripView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        strip.configure(attachments)
        strip.frame.size.height = strip.measuredHeight(width: width)
        let window = NSWindow(
            contentRect: strip.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = strip
        strip.layoutSubtreeIfNeeded()
        return (strip, window)
    }

    private func click(
        _ strip: AppKitComposerAttachmentStripView,
        at point: NSPoint,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let hitView = try XCTUnwrap(strip.hitTest(point), file: file, line: line)
        hitView.mouseUp(with: mouseEvent(at: strip.convert(point, to: nil)))
    }

    private func imageRemoveButtonCenter(in frame: NSRect) -> NSPoint {
        NSPoint(
            x: frame.maxX - BlockInputComposerStyle.imagePreviewRemoveButtonSize.width / 2 - 5,
            y: frame.minY + BlockInputComposerStyle.imagePreviewRemoveButtonSize.height / 2 + 5
        )
    }

    private func fileRemoveButtonCenter(in frame: NSRect) -> NSPoint {
        NSPoint(
            x: frame.maxX - BlockInputComposerStyle.imagePreviewRemoveButtonSize.width / 2 - 8,
            y: frame.minY + BlockInputComposerStyle.imagePreviewRemoveButtonSize.height / 2 + 8
        )
    }

    private func appShotRemoveButtonCenter(in frame: NSRect) -> NSPoint {
        NSPoint(
            x: frame.maxX - BlockInputComposerStyle.imagePreviewRemoveButtonSize.width / 2 - 6,
            y: frame.minY + BlockInputComposerStyle.imagePreviewRemoveButtonSize.height / 2 + 6
        )
    }

    private func center(of frame: NSRect) -> NSPoint {
        NSPoint(x: frame.midX, y: frame.midY)
    }

    private func mouseEvent(at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func localImageAttachment(id: String, filename: String, size: NSSize) throws -> LocalImageAttachment {
        let url = try temporaryPNGURL(named: filename, size: size)
        return LocalImageAttachment(
            id: id,
            fileURL: url,
            label: filename,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func localFileAttachment(filename: String) throws -> LocalFileAttachment {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try Data("PDF".utf8).write(to: url, options: [.atomic])
        return LocalFileAttachment(
            id: filename,
            fileURL: url,
            label: filename,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func appShotAttachment(id: String, filename: String, size: NSSize) throws -> AppShotAttachment {
        let screenshot = try localImageAttachment(id: "\(id)-screenshot", filename: filename, size: size)
        return AppShotAttachment(
            id: id,
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "Preview - Document.pdf",
            screenshot: screenshot,
            axTreeText: "Window",
            focusedElementSummary: "",
            attachmentStoreRoot: FileManager.default.temporaryDirectory
        )
    }

    private func temporaryPNGURL(named filename: String, size: NSSize) throws -> URL {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let pngData = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try pngData.write(to: url, options: [.atomic])
        return url
    }
}

private final class CursorInvalidationWindow: NSWindow {
    var invalidatedCursorRectViews: [NSView] = []

    override func invalidateCursorRects(for view: NSView) {
        invalidatedCursorRectViews.append(view)
        super.invalidateCursorRects(for: view)
    }
}

private extension ComposerAttachment {
    var testingID: String {
        switch self {
        case .image(let image):
            return image.id
        case .file(let file):
            return file.id
        case .appShot(let appShot):
            return appShot.id
        }
    }
}
