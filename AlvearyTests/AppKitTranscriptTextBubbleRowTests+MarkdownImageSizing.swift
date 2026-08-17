@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptTextBubbleRowTests {
    /// A source that declares no dimensions still reserves its real box, so the
    /// row height is the image height rather than a 16:9 slab.
    func testAssistantBubbleRowHeightWrapsLocalImageAspectRatio() throws {
        let imageURL = try transcriptTemporaryPNGURL(width: 200, height: 150)
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 700, height: 800)
        row.configure(
            .init(
                id: "assistant-local-image",
                role: .assistant,
                markdown: "![Local](\(imageURL.lastPathComponent))",
                bubbleMaxWidth: 420,
                markdownBaseURL: imageURL.deletingLastPathComponent()
            )
        )
        row.layoutSubtreeIfNeeded()

        let imageView = try XCTUnwrap(row.descendants(of: AppKitMarkdownImageBlockView.self).first)
        XCTAssertEqual(imageView.displaySizeForTesting, CGSize(width: 200, height: 150))
        XCTAssertEqual(row.intrinsicContentSize.height, 150 + (chatBubbleVerticalPadding * 2), accuracy: 1)
    }

    /// Correct sizing means a short banner stops tripping the collapse the fixed
    /// 16:9 box used to force on every image.
    func testAssistantBubbleDoesNotCollapseAShortWideImage() throws {
        let imageURL = try transcriptTemporaryPNGURL(width: 1_600, height: 400)
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 700, height: 800)
        row.configure(
            .init(
                id: "assistant-banner-image",
                role: .assistant,
                markdown: "![Banner](\(imageURL.lastPathComponent))",
                bubbleMaxWidth: 420,
                markdownBaseURL: imageURL.deletingLastPathComponent()
            )
        )
        row.layoutSubtreeIfNeeded()

        let expectedWidth = 420 - (chatBubbleHorizontalPadding * 2)
        let imageView = try XCTUnwrap(row.descendants(of: AppKitMarkdownImageBlockView.self).first)
        XCTAssertEqual(imageView.displaySizeForTesting.width, expectedWidth, accuracy: 0.5)
        XCTAssertLessThan(imageView.displaySizeForTesting.height, collapsedMaxHeight)
        XCTAssertEqual(row.expansionButtonFrameForTesting, .zero)
    }

    /// A tall screenshot is not capped; the bubble's own collapse keeps it from
    /// dominating the transcript.
    func testAssistantBubbleCollapsesATallImageBehindShowMore() throws {
        let imageURL = try transcriptTemporaryPNGURL(width: 200, height: 600)
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 700, height: 900)
        row.configure(
            .init(
                id: "assistant-tall-image",
                role: .assistant,
                markdown: "![Tall](\(imageURL.lastPathComponent))",
                bubbleMaxWidth: 420,
                markdownBaseURL: imageURL.deletingLastPathComponent()
            )
        )
        row.layoutSubtreeIfNeeded()

        let imageView = try XCTUnwrap(row.descendants(of: AppKitMarkdownImageBlockView.self).first)
        XCTAssertEqual(imageView.displaySizeForTesting, CGSize(width: 200, height: 600))
        XCTAssertNotEqual(row.expansionButtonFrameForTesting, .zero)
        XCTAssertLessThan(row.intrinsicContentSize.height, 600)
    }

    private func transcriptTemporaryPNGURL(width: Int, height: Int) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let fileURL = directoryURL.appendingPathComponent("fixture.png")
        try appMarkdownTestPNGData(width: width, height: height).write(to: fileURL)
        return fileURL
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
