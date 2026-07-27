@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitComposerAttachmentStripViewTests {
    func testAppShotRemoveButtonAcceptsClicksAcrossItsWholeCircle() throws {
        let appShot = try appShotAttachment(
            id: "edge-app-shot",
            filename: "edge-app-shot.png",
            size: NSSize(width: 400, height: 200)
        )
        let mounted = configuredMountedStrip(attachments: [.appShot(appShot)], width: 500)
        let strip = mounted.strip
        let cardFrame = try XCTUnwrap(strip.appShotCardFramesForTesting.first)

        // Cards sit at a non-zero origin inside the strip, so a hit test that compares raw
        // superview coordinates against card-space rects shifts the button's live region by that
        // origin and leaves its right and top edges dead.
        XCTAssertGreaterThan(cardFrame.minX, 0)
        XCTAssertGreaterThan(cardFrame.minY, 0)
        assertRemoveButtonCircleIsFullyClickable(
            in: strip,
            buttonRect: appShotRemoveButtonRect(in: cardFrame),
            expectedID: appShot.id
        )
    }

    func testImageRemoveButtonAcceptsClicksAcrossItsWholeCircle() throws {
        let image = try localImageAttachment(
            id: "edge-image",
            filename: "edge-image.png",
            size: NSSize(width: 120, height: 120)
        )
        let mounted = configuredMountedStrip(attachments: [.image(image)], width: 500)
        let strip = mounted.strip
        let tileFrame = try XCTUnwrap(strip.imageTileFramesForTesting.first)

        assertRemoveButtonCircleIsFullyClickable(
            in: strip,
            buttonRect: imageRemoveButtonRect(in: tileFrame),
            expectedID: image.id
        )
    }

    func testFileRemoveButtonAcceptsClicksAcrossItsWholeCircle() throws {
        let file = try localFileAttachment(filename: "edge-file.pdf")
        let mounted = configuredMountedStrip(attachments: [.file(file)], width: 500)
        let strip = mounted.strip
        let chipFrame = try XCTUnwrap(strip.fileChipFramesForTesting.first)

        assertRemoveButtonCircleIsFullyClickable(
            in: strip,
            buttonRect: fileRemoveButtonRect(in: chipFrame),
            expectedID: file.id
        )
    }

    /// Clicks the button's center and each of its four edges, which is where an origin-shifted hit
    /// region goes dead while the center keeps working.
    private func assertRemoveButtonCircleIsFullyClickable(
        in strip: AppKitComposerAttachmentStripView,
        buttonRect: NSRect,
        expectedID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let inset: CGFloat = 1.5
        let probes: [(String, NSPoint)] = [
            ("center", NSPoint(x: buttonRect.midX, y: buttonRect.midY)),
            ("leading", NSPoint(x: buttonRect.minX + inset, y: buttonRect.midY)),
            ("trailing", NSPoint(x: buttonRect.maxX - inset, y: buttonRect.midY)),
            ("top", NSPoint(x: buttonRect.midX, y: buttonRect.minY + inset)),
            ("bottom", NSPoint(x: buttonRect.midX, y: buttonRect.maxY - inset))
        ]

        for (name, point) in probes {
            var removedIDs: [String] = []
            var openedIDs: [String] = []
            strip.onRemoveAttachment = { removedIDs.append($0.testingID) }
            strip.onOpenAttachment = { openedIDs.append($0.testingID) }

            strip.hitTest(point)?.mouseUp(with: mouseEvent(at: strip.convert(point, to: nil)))

            XCTAssertEqual(removedIDs, [expectedID], "\(name) edge did not remove", file: file, line: line)
            XCTAssertTrue(openedIDs.isEmpty, "\(name) edge opened instead of removing", file: file, line: line)
        }
    }
}
