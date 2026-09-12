import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension BlockInputComposerBridgeControllerTests {
    func testFileCompletionAggregatesRootsAndLabelsAmbiguousNames() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/app", workspaceRoots: ["/tmp/library"]),
            loadFileCompletions: {
                ["/tmp/app/README.md", "/tmp/library/README.md", "/tmp/library/README.md", "/tmp/outside/README.md"]
            },
            loadSkillCompletions: { [] }
        )
        let suggestions = await provider.suggestions(for: completionContext(trigger: .mention, query: "README", rawQuery: "README"))
        XCTAssertEqual(Set(suggestions.map(\.title)), ["app/README.md", "library/README.md"])
        XCTAssertEqual(Set(suggestions.map(\.id)), ["/tmp/app/README.md", "/tmp/library/README.md"])
        XCTAssertTrue(suggestions.allSatisfy { $0.insertionText.contains("](/tmp/") })
        let relative = await provider.suggestions(for: completionContext(
            trigger: .mention, query: "README", rawQuery: "./README",
            fileQuery: BlockInputCompletionFileQuery(directoryReference: .current, levelsUp: 0, remainder: "README")
        ))
        XCTAssertEqual(relative.map(\.id), ["/tmp/app/README.md"])
    }

    func testAbsoluteFileCompletionWithSpacesRoundTripsThroughTranscriptLinks() async throws {
        let roots = ["/tmp/first/shared", "/tmp/second/shared"]
        let paths = roots.map { $0 + "/Read [me] (1).md" }
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: roots[0], workspaceRoots: [roots[1]]),
            loadFileCompletions: { paths }, loadSkillCompletions: { [] }
        )
        let suggestions = await provider.suggestions(for: completionContext(trigger: .mention, query: "Read", rawQuery: "Read"))
        XCTAssertEqual(Set(suggestions.map(\.title)).count, 2)
        for suggestion in suggestions {
            let document = BlockInputDocument(markdown: suggestion.insertionText)
            let rendered = try AppMarkdownParser(baseURL: URL(fileURLWithPath: "/tmp/unrelated")).attributedString(for: document.markdown)
            let link = try XCTUnwrap(rendered.runs.compactMap(\.link).first)
            let destination = ChatTranscriptView.resolveMarkdownLinkURL(link, workingDirectory: "/tmp/unrelated")
            XCTAssertEqual(destination.path, suggestion.id)
        }
    }

}
