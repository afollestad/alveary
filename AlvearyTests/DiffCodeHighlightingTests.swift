import SwiftUI
import XCTest

@testable import Alveary

final class DiffCodeHighlightingTests: XCTestCase {
    func testClassifiesGitPatchLines() {
        let source = """
        diff --git a/README.md b/README.md
        index 1234567..89abcde 100644
        --- a/README.md
        +++ b/README.md
        @@ -1,2 +1,3 @@
         The site is static.
        -This is the source of my personal website.
        +This is the source for my personal website.
        +It is published with GitHub Pages.
        """

        XCTAssertEqual(
            DiffCodeHighlighting.lineKinds(in: source),
            [
                .fileHeader, .fileHeader, .fileHeader, .fileHeader,
                .hunkHeader,
                .context, .deleted, .added, .added
            ]
        )
    }

    /// The shape a model writes when it quotes a diff in chat: a bare path, an abbreviated hunk
    /// marker, and change lines. `DiffParser` finds nothing here because there is no `diff --git`.
    func testClassifiesAHeaderlessFragmentAndPromotesItsPathLine() {
        let source = """
        scripts/scroll-to-experience.js
        @@
         (function () {
        +    // Keep the shortcut inert when its target is not present.
             var btn = document.getElementById('scroll-to-experience');
        """

        XCTAssertEqual(
            DiffCodeHighlighting.lineKinds(in: source),
            [.fileHeader, .hunkHeader, .context, .added, .context]
        )
    }

    func testProseAboveAHunkHeaderStaysContext() {
        let source = """
        Here is the change I made:
        @@ -1 +1 @@
        -old
        +new
        """

        XCTAssertEqual(
            DiffCodeHighlighting.lineKinds(in: source),
            [.context, .hunkHeader, .deleted, .added]
        )
    }

    /// A quoted patch that kept its headers is parsed by `DiffParser`, so the rows carry the line
    /// numbers it computed and the git header noise collapses into one file row.
    func testRowsOfAGitPatchCarryLineNumbersFromDiffParser() {
        let source = """
        diff --git a/README.md b/README.md
        index 1234567..89abcde 100644
        --- a/README.md
        +++ b/README.md
        @@ -1,2 +1,2 @@
         The site is static.
        -Old line.
        +New line.
        """

        let rows = DiffCodeHighlighting.rows(in: source)

        XCTAssertTrue(DiffCodeHighlighting.showsLineNumbers(in: rows))
        XCTAssertEqual(rows.map(\.kind), [.fileHeader, .hunkHeader, .context, .deleted, .added])
        XCTAssertEqual(rows.map(\.text), [
            "README.md",
            "@@ -1,2 +1,2 @@",
            "The site is static.",
            "Old line.",
            "New line."
        ])
        XCTAssertEqual(rows.map(\.oldNumber), [nil, nil, 1, 2, nil])
        XCTAssertEqual(rows.map(\.newNumber), [nil, nil, 1, nil, 2])
    }

    /// The numbers are the file's own, not a count from one: the hunk header states where each
    /// side starts and `DiffParser` walks from there.
    func testRowNumbersStartWhereTheHunkHeaderSaysRatherThanAtOne() {
        let source = """
        diff --git a/site.js b/site.js
        @@ -42,3 +117,3 @@ function boot() {
           setup();
        -  legacy();
        +  modern();
        """

        let rows = DiffCodeHighlighting.rows(in: source)

        XCTAssertEqual(rows.map(\.oldNumber), [nil, nil, 42, 43, nil])
        XCTAssertEqual(rows.map(\.newNumber), [nil, nil, 117, nil, 118])
    }

    /// The same diff after a model retyped it: `DiffParser` sees no file, so the rows come from the
    /// classifier and the number columns stay empty rather than starting from a guess.
    func testRowsOfARetypedFragmentStripMarkersAndCarryNoNumbers() {
        let source = """
        README.md
        @@
        -Old line.
        +New line.
        """

        let rows = DiffCodeHighlighting.rows(in: source)

        XCTAssertFalse(DiffCodeHighlighting.showsLineNumbers(in: rows))
        XCTAssertEqual(rows.map(\.kind), [.fileHeader, .hunkHeader, .deleted, .added])
        XCTAssertEqual(rows.map(\.text), ["README.md", "@@", "Old line.", "New line."])
        XCTAssertEqual(rows.map(\.marker), ["", "", "-", "+"])
    }

    func testDetectsAnUnlabeledBlockThatCarriesAHunkHeader() {
        let source = "@@ -1 +1 @@\n-old\n+new"

        XCTAssertTrue(
            DiffCodeHighlighting.rendersAsDiff(language: "", isRecognizedLanguage: false, source: source)
        )
        XCTAssertTrue(
            DiffCodeHighlighting.rendersAsDiff(language: "diff", isRecognizedLanguage: false, source: "")
        )
    }

    func testLeavesUnlabeledProseAndKnownLanguagesAlone() {
        XCTAssertFalse(
            DiffCodeHighlighting.rendersAsDiff(
                language: "",
                isRecognizedLanguage: false,
                source: "- first bullet\n- second bullet"
            )
        )
        XCTAssertFalse(
            DiffCodeHighlighting.rendersAsDiff(
                language: "swift",
                isRecognizedLanguage: true,
                source: "@@ -1 +1 @@\n-let a = 1\n+let a = 2"
            )
        )
    }

    func testHighlightingTintsChangedRowsAndKeepsTheSourceVerbatim() {
        let source = "@@ -1 +1 @@\n-old\n+new\n unchanged"

        let highlighted = SyntaxHighlighter.highlighted(source, language: "diff", colorScheme: .dark)

        XCTAssertEqual(String(highlighted.characters), source)
        let tinted = highlighted.runs.compactMap { run in
            run.backgroundColor.map { _ in String(highlighted[run.range].characters) }
        }
        XCTAssertEqual(tinted, ["@@ -1 +1 @@", "-", "old", "+", "new"])
    }

    func testLineNumberedToolOutputIsNotReadAsADiff() {
        let source = "1\t@@ -1 +1 @@\n2\t-old\n3\t+new"

        let highlighted = SyntaxHighlighter.highlighted(
            source,
            language: "",
            colorScheme: .dark,
            preserveLineNumberPrefixes: true
        )

        XCTAssertTrue(highlighted.runs.allSatisfy { $0.backgroundColor == nil })
    }
}
