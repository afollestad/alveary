@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptNoteAndErrorRowTests: XCTestCase {
    func testPlanModeTranscriptNoteRendersToolLeadingTextWithoutIcon() throws {
        let note = AppKitTranscriptNoteView()
        note.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        note.configure(.init(kind: .enteredPlanMode))
        note.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(note.descendants(of: NSTextField.self).first)
        XCTAssertEqual(label.stringValue, "Entered plan mode")
        XCTAssertEqual(label.accessibilityLabel(), "Entered plan mode")
        let expectedColor = transcriptInlineToolRowColor.resolved(for: note.appKitRenderingAppearance)
        let expectedFont = TranscriptTypography().nsFont(.inlineToolText)
        let labelColor = try XCTUnwrap(label.foregroundColorForTesting?.resolved(for: note.appKitRenderingAppearance))
        let labelFont = try XCTUnwrap(label.fontForTesting)
        XCTAssertEqual(note.descendants(of: NSImageView.self).count, 0)
        XCTAssertEqual(label.visibleTextMinX, 0, accuracy: 0.5)
        XCTAssertEqual(label.frame.minY, transcriptInlineToolRowVerticalPadding, accuracy: 0.5)
        XCTAssertEqual(labelColor, expectedColor)
        XCTAssertEqual(labelFont.pointSize, expectedFont.pointSize, accuracy: 0.5)
        XCTAssertEqual(labelFont.weightForTesting, expectedFont.weightForTesting)
    }

    func testTranscriptNoteTextColorMatchesToolRowsInDarkMode() throws {
        let note = AppKitTranscriptNoteView()
        note.appearance = NSAppearance(named: .darkAqua)
        note.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        note.configure(.init(kind: .interrupted))
        note.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(note.descendants(of: NSTextField.self).first)
        let expectedColor = transcriptInlineToolRowColor.resolved(for: note.appKitRenderingAppearance)
        let labelColor = try XCTUnwrap(label.foregroundColorForTesting?.resolved(for: note.appKitRenderingAppearance).usingColorSpace(.sRGB))
        let expectedSRGBColor = try XCTUnwrap(expectedColor.usingColorSpace(.sRGB))
        XCTAssertEqual(labelColor, expectedSRGBColor)
    }

    func testSessionHandoffInProgressTranscriptNoteStaysCentered() throws {
        let note = AppKitTranscriptNoteView()
        note.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        note.configure(.init(kind: .sessionHandoffInProgress))
        note.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(note.descendants(of: NSTextField.self).first)
        XCTAssertEqual(label.stringValue, "Handing off session...")
        XCTAssertEqual(label.frame.midX, note.bounds.midX, accuracy: 0.5)
    }

    func testSessionHandoffTranscriptNoteStaysCentered() throws {
        let note = AppKitTranscriptNoteView()
        note.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        note.configure(.init(kind: .sessionHandoff))
        note.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(note.descendants(of: NSTextField.self).first)
        XCTAssertEqual(label.stringValue, "Session handed off")
        XCTAssertEqual(label.frame.midX, note.bounds.midX, accuracy: 0.5)
    }

    func testSessionForkedTranscriptNoteStaysCentered() throws {
        let note = AppKitTranscriptNoteView()
        note.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        note.configure(.init(kind: .sessionForked))
        note.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(note.descendants(of: NSTextField.self).first)
        XCTAssertEqual(label.stringValue, "Forked from session")
        XCTAssertEqual(label.accessibilityLabel(), "Forked from session")
        XCTAssertEqual(label.frame.midX, note.bounds.midX, accuracy: 0.5)
    }

    func testInterruptedTranscriptNoteTrailsUserBubbleBoundary() throws {
        let note = AppKitTranscriptNoteView()
        note.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        note.configure(.init(kind: .interrupted))
        note.layoutSubtreeIfNeeded()

        let userBubble = AppKitTranscriptTextBubbleRowView()
        userBubble.frame = note.bounds
        userBubble.configure(.init(role: .user, markdown: "Interrupted", bubbleMaxWidth: 320))
        userBubble.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(note.descendants(of: NSTextField.self).first)
        XCTAssertEqual(label.visibleTextMaxX, userBubble.bubbleFrameForTesting.maxX, accuracy: 0.5)
        XCTAssertEqual(label.frame.minY, transcriptInlineToolRowVerticalPadding, accuracy: 0.5)
    }

    func testTranscriptNoteRendersFullSessionHandoffText() throws {
        let note = AppKitTranscriptNoteView()
        note.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        note.configure(.init(kind: .sessionHandoff))
        note.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(note.descendants(of: NSTextField.self).first)
        XCTAssertEqual(label.stringValue, "Session handed off")
        XCTAssertEqual(label.frame.width, label.naturalCellWidth, accuracy: 0.5)
    }

    func testSteeredConversationTranscriptNoteUsesToolLeadingAlignment() throws {
        let note = AppKitTranscriptNoteView()
        note.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        note.configure(.init(kind: .steeredConversation))
        note.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(note.descendants(of: NSTextField.self).first)
        XCTAssertEqual(label.stringValue, "Steered conversation")
        XCTAssertEqual(label.visibleTextMinX, 0, accuracy: 0.5)
        XCTAssertEqual(label.frame.minY, transcriptInlineToolRowVerticalPadding, accuracy: 0.5)
    }

    func testTranscriptNoteRendersContextCompactionText() throws {
        let note = AppKitTranscriptNoteView()
        note.frame = NSRect(x: 0, y: 0, width: 360, height: 120)
        note.configure(.init(kind: .contextCompactionStarted))
        note.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(note.descendants(of: NSTextField.self).first)
        XCTAssertEqual(label.stringValue, "Automatically compacting context")

        note.configure(.init(kind: .contextCompactionCompleted))
        note.layoutSubtreeIfNeeded()

        XCTAssertEqual(label.stringValue, "Automatically compacted context")
    }

    func testTranscriptNoteHeightInvalidatesWhenTextWraps() {
        let note = AppKitTranscriptNoteView()
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
    var foregroundColorForTesting: NSColor? {
        attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    }

    var fontForTesting: NSFont? {
        attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    }

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

private extension NSFont {
    var weightForTesting: Int {
        NSFontManager.shared.weight(of: self)
    }
}
