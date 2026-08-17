@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptToolDetailViewTests {
    /// Regression: the markdown tool content view hands its measurer the same
    /// `imageBaseURL` its renderer resolves with. Without it, a local image in
    /// a markdown tool detail measured the 16:9 fallback while drawing its
    /// real box, so the reported height clipped or overshot the content.
    func testMarkdownDetailMeasuresLocalImageAtItsRealAspectRatio() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try appMarkdownTestPNGData(width: 200, height: 150)
            .write(to: directoryURL.appendingPathComponent("fixture.png"))

        let view = AppKitTranscriptToolDetailsView()
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        view.configure(.init(tool: markdownImageDetailTool(baseURL: directoryURL)))
        view.layoutSubtreeIfNeeded()

        let imageView = try XCTUnwrap(view.descendants(of: AppKitMarkdownImageBlockView.self).first)
        XCTAssertEqual(imageView.displaySizeForTesting, CGSize(width: 200, height: 150))
        // The content view's reported height is measurer-driven: image height
        // plus the 20pt vertical chrome, not a 16:9 slab of the content width.
        let contentView = try XCTUnwrap(view.descendants(of: AppKitMarkdownView.self).first?.superview)
        XCTAssertEqual(contentView.intrinsicContentSize.height, 170, accuracy: 0.5)
    }

    /// `Read` ignores `previewOverride`: its snapshot derives content, language,
    /// and base URL from the tool itself, so the fixture routes the base through
    /// the input `file_path` the way a real transcript does.
    private func markdownImageDetailTool(baseURL: URL) -> ToolEntry {
        ToolEntry(
            id: "markdown-image-detail-1",
            name: "Read",
            summary: "Read `notes.md`",
            input: #"{"file_path":"\#(baseURL.path)/notes.md"}"#,
            output: "![Fixture](fixture.png)",
            stderr: nil,
            isComplete: true,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
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
