@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptNoteAndErrorRowTests: XCTestCase {
    func testCenteredNoteRendersKindTextAndIsCentered() throws {
        let note = AppKitTranscriptCenteredNoteView()
        note.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        note.configure(.init(kind: .enteredPlanMode))
        note.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(note.descendants(of: NSTextField.self).first)
        XCTAssertEqual(label.stringValue, "Entered plan mode")
        XCTAssertEqual(label.accessibilityLabel(), "Entered plan mode")
        let icon = try XCTUnwrap(note.descendants(of: NSImageView.self).first)
        let expectedColor = transcriptInlineToolRowColor.resolved(for: note.appKitRenderingAppearance)
        XCTAssertEqual(note.intrinsicContentSize.height, 48)
        XCTAssertEqual((icon.frame.minX + label.visibleTextMaxX) / 2, note.bounds.midX, accuracy: 1)
        XCTAssertEqual(label.textColor?.resolved(for: note.appKitRenderingAppearance), expectedColor)
        XCTAssertEqual(icon.contentTintColor?.resolved(for: note.appKitRenderingAppearance), expectedColor)
        XCTAssertEqual(label.visibleTextMinX - icon.frame.maxX, 6, accuracy: 0.5)
        XCTAssertEqual(icon.frame.size, NSSize(width: 16, height: 16))
        XCTAssertEqual(icon.frame.midY, label.frame.midY, accuracy: 1)
        XCTAssertTrue(String(describing: icon.symbolConfiguration).contains("rendering style: Monochrome"))
    }

    func testCenteredNoteIconTintMatchesLabelInDarkMode() throws {
        let note = AppKitTranscriptCenteredNoteView()
        note.appearance = NSAppearance(named: .darkAqua)
        note.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        note.configure(.init(kind: .interrupted))
        note.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(note.descendants(of: NSTextField.self).first)
        let icon = try XCTUnwrap(note.descendants(of: NSImageView.self).first)
        let expectedColor = transcriptInlineToolRowColor.resolved(for: note.appKitRenderingAppearance)
        let labelColor = try XCTUnwrap(label.textColor?.resolved(for: note.appKitRenderingAppearance).usingColorSpace(.sRGB))
        let iconColor = try XCTUnwrap(icon.contentTintColor?.resolved(for: note.appKitRenderingAppearance).usingColorSpace(.sRGB))
        let expectedSRGBColor = try XCTUnwrap(expectedColor.usingColorSpace(.sRGB))
        XCTAssertEqual(labelColor, expectedSRGBColor)
        XCTAssertEqual(iconColor, expectedSRGBColor)
    }

    func testCenteredNoteRendersFullSessionHandoffText() throws {
        let note = AppKitTranscriptCenteredNoteView()
        note.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        note.configure(.init(kind: .sessionHandoff))
        note.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(note.descendants(of: NSTextField.self).first)
        XCTAssertEqual(label.stringValue, "Session handoff")
        XCTAssertGreaterThan(label.frame.width, 100)
    }

    func testCenteredNoteRendersContextCompactionText() throws {
        let note = AppKitTranscriptCenteredNoteView()
        note.frame = NSRect(x: 0, y: 0, width: 360, height: 120)
        note.configure(.init(kind: .contextCompactionStarted))
        note.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(note.descendants(of: NSTextField.self).first)
        XCTAssertEqual(label.stringValue, "Automatically compacting context")

        note.configure(.init(kind: .contextCompactionCompleted))
        note.layoutSubtreeIfNeeded()

        XCTAssertEqual(label.stringValue, "Automatically compacted context")
    }

    func testCenteredNoteHeightInvalidatesWhenTextWraps() {
        let note = AppKitTranscriptCenteredNoteView()
        var invalidated = false
        note.onHeightInvalidated = {
            invalidated = true
        }
        note.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
        note.configure(.init(kind: .enteredPlanMode))
        note.layoutSubtreeIfNeeded()
        let wideHeight = note.intrinsicContentSize.height
        invalidated = false

        note.frame = NSRect(x: 0, y: 0, width: 70, height: 160)
        note.layoutSubtreeIfNeeded()

        XCTAssertTrue(invalidated)
        XCTAssertGreaterThan(note.intrinsicContentSize.height, wideHeight)
    }

    func testErrorBannerRespectsBubbleMaxWidthAndStyling() throws {
        let banner = AppKitTranscriptErrorBannerView()
        banner.frame = NSRect(x: 0, y: 0, width: 520, height: 200)
        banner.configure(.init(message: "Something failed.", bubbleMaxWidth: 320))
        banner.layoutSubtreeIfNeeded()

        let bannerSurface = try XCTUnwrap(banner.subviews.first)
        let label = try XCTUnwrap(banner.descendants(of: NSTextField.self).first)
        let icon = try XCTUnwrap(banner.descendants(of: NSImageView.self).first)

        XCTAssertEqual(bannerSurface.frame.width, 320)
        XCTAssertEqual(label.stringValue, "Something failed.")
        XCTAssertEqual(label.accessibilityLabel(), "Something failed.")
        XCTAssertEqual(icon.frame.size, NSSize(width: 16, height: 16))
        XCTAssertEqual(bannerSurface.layer?.borderWidth, 1)
    }

    func testErrorBannerSurfaceUsesFlippedCoordinatesForChildren() throws {
        let banner = AppKitTranscriptErrorBannerView()
        banner.frame = NSRect(x: 0, y: 0, width: 520, height: 200)
        banner.configure(.init(message: "Something failed.", bubbleMaxWidth: 320))
        banner.layoutSubtreeIfNeeded()

        let bannerSurface = try XCTUnwrap(banner.subviews.first)
        let label = try XCTUnwrap(banner.descendants(of: NSTextField.self).first)
        let icon = try XCTUnwrap(banner.descendants(of: NSImageView.self).first)

        XCTAssertTrue(bannerSurface.isFlipped)
        XCTAssertEqual(icon.frame.minY, 10, accuracy: 1)
        XCTAssertEqual(label.frame.minY, 10, accuracy: 1)
    }

    func testErrorBannerHeightInvalidatesWhenMessageWraps() {
        let banner = AppKitTranscriptErrorBannerView()
        var invalidated = false
        banner.onHeightInvalidated = {
            invalidated = true
        }
        banner.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
        banner.configure(.init(message: "Short failure.", bubbleMaxWidth: 360))
        banner.layoutSubtreeIfNeeded()
        let shortHeight = banner.intrinsicContentSize.height
        invalidated = false

        banner.configure(
            .init(
                message: "This failure message is intentionally long enough to wrap into multiple lines in the AppKit transcript error banner.",
                bubbleMaxWidth: 180
            )
        )
        banner.layoutSubtreeIfNeeded()

        XCTAssertTrue(invalidated)
        XCTAssertGreaterThan(banner.intrinsicContentSize.height, shortHeight)
    }
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}

private extension NSTextField {
    var visibleTextMinX: CGFloat {
        frame.minX + textHorizontalInset / 2
    }

    var visibleTextMaxX: CGFloat {
        frame.maxX - textHorizontalInset / 2
    }

    var textHorizontalInset: CGFloat {
        max(naturalCellWidth - attributedNaturalWidth, 0)
    }

    var naturalCellWidth: CGFloat {
        let unconstrainedBounds = NSRect(
            x: 0,
            y: 0,
            width: CGFloat.greatestFiniteMagnitude / 2,
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        return ceil(cell?.cellSize(forBounds: unconstrainedBounds).width ?? fittingSize.width)
    }

    var attributedNaturalWidth: CGFloat {
        let rect = attributedStringValue.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude / 2, height: CGFloat.greatestFiniteMagnitude / 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.width)
    }
}
