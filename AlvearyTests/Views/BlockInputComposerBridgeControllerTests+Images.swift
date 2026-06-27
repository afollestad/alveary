import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension BlockInputComposerBridgeControllerTests {
    func testBridgeUsesInlineImageParsingByDefault() {
        let controller = BlockInputComposerBridgeController(configuration: makeImageConfiguration(
            markdown: "Before\n\n![Cat](cat.png)\n\nAfter"
        ))

        XCTAssertTrue(controller.documentStore.document.containsImageBlock)
    }

    func testBridgePreservesMarkdownImageSourceTextForTextLinkPresentation() {
        let markdown = "Before ![Cat](cat.png) after"
        let configuration = makeImageConfiguration(markdown: markdown, imagePresentation: .textLinks)
        let controller = BlockInputComposerBridgeController(configuration: configuration)
        let blockInputConfiguration = controller.blockInputConfiguration(for: configuration)

        XCTAssertFalse(controller.documentStore.document.containsImageBlock)
        XCTAssertEqual(controller.currentMarkdown(), markdown)
        XCTAssertEqual(blockInputConfiguration.imagePresentation, .textLinks)
    }

    func testExternalRevisionPreservesMarkdownImageSourceTextForTextLinkPresentation() {
        let controller = BlockInputComposerBridgeController(configuration: makeImageConfiguration(markdown: "Before"))
        let markdown = "![Cat](cat.png)"

        controller.configure(makeImageConfiguration(
            markdown: markdown,
            markdownRevision: 1,
            imagePresentation: .textLinks
        ))

        XCTAssertFalse(controller.documentStore.document.containsImageBlock)
        XCTAssertEqual(controller.currentMarkdown(), markdown)
    }

    private func makeImageConfiguration(
        markdown: String,
        markdownRevision: Int = 0,
        imagePresentation: BlockInputImagePresentation = .inlineBlocks
    ) -> BlockInputComposerBridgeConfiguration {
        BlockInputComposerBridgeConfiguration(
            markdown: markdown,
            markdownRevision: markdownRevision,
            imagePresentation: imagePresentation,
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/alveary-project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] }
        )
    }
}

private extension BlockInputDocument {
    var containsImageBlock: Bool {
        blocks.contains { block in
            if case .image = block.kind {
                return true
            }
            return false
        }
    }
}
