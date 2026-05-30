@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptTextBubbleRowTests {
    func testAssistantBubbleRendersHTMLImageTagAsImageBlock() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 600)
        row.configure(
            .init(
                id: "assistant-image",
                role: .assistant,
                markdown: #"<img src="file:///tmp/photo.jpg" alt="Photo" width="262" height="174" />"#,
                bubbleMaxWidth: 420
            )
        )
        row.layoutSubtreeIfNeeded()

        let imageView = try XCTUnwrap(row.descendants(of: AppKitMarkdownImageBlockView.self).first)
        XCTAssertEqual(imageView.displaySizeForTesting, CGSize(width: 262, height: 174))
        XCTAssertFalse(row.descendants(of: AppKitMarkdownTextView.self).map(\.string).contains { $0.contains("<img") })
        XCTAssertEqual(row.intrinsicContentSize.height, 174 + (chatVerticalPadding * 2), accuracy: 1)
    }

    func testAssistantBubbleCapsWideImagesToContentWidth() throws {
        let bubbleMaxWidth: CGFloat = 420
        let expectedImageWidth = bubbleMaxWidth - (chatBubbleHorizontalPadding * 2)
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        row.configure(
            .init(
                id: "assistant-wide-image",
                role: .assistant,
                markdown: #"<img src="file:///tmp/photo.jpg" alt="Wide photo" width="1200" height="600" />"#,
                bubbleMaxWidth: bubbleMaxWidth
            )
        )
        row.layoutSubtreeIfNeeded()

        let imageView = try XCTUnwrap(row.descendants(of: AppKitMarkdownImageBlockView.self).first)
        XCTAssertEqual(row.bubbleFrameForTesting.width, bubbleMaxWidth, accuracy: 0.5)
        XCTAssertEqual(imageView.displaySizeForTesting.width, expectedImageWidth, accuracy: 0.5)
        XCTAssertLessThanOrEqual(imageView.displaySizeForTesting.width, row.markdownClipFrameForTesting.width + 0.5)
    }

    func testImageBaseURLDoesNotResolveFragmentOnlyLinks() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 600)
        row.configure(
            .init(
                id: "assistant-image-link",
                role: .assistant,
                markdown: """
                See [top](#section).

                ![Diagram](images/diagram.png)
                """,
                bubbleMaxWidth: 420,
                markdownBaseURL: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
            )
        )
        row.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(row.descendants(of: AppKitMarkdownTextView.self).first)
        let link = try XCTUnwrap(linkAttribute(in: textView, matching: "top") as? URL)
        XCTAssertNil(link.scheme)
        XCTAssertEqual(link.relativeString, "#section")
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

@MainActor
private func linkAttribute(in textView: AppKitMarkdownTextView, matching text: String) -> Any? {
    let range = (textView.string as NSString).range(of: text)
    guard range.location != NSNotFound else {
        return nil
    }
    return textView.textStorage?.attribute(.link, at: range.location, effectiveRange: nil)
}
