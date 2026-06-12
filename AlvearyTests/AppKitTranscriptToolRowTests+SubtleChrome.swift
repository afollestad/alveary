@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptToolRowTests {
    func testHeaderSummaryUsesMutedInlineToolTypography() throws {
        let header = AppKitTranscriptToolHeaderRowView()
        header.appearance = NSAppearance(named: .aqua)
        var settings = AppSettings()
        settings.chatFontSize = 18
        settings.codeFontSize = 24
        let typography = TranscriptTypography(settings: settings)
        header.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        header.configure(
            .init(
                summary: "Running `swift test`",
                leadingIcon: .genericTool,
                phase: .success,
                typography: typography
            )
        )
        header.layoutSubtreeIfNeeded()

        let textStorage = try XCTUnwrap(header.descendantsForSubtleChromeTests(of: NSTextField.self).first?.attributedStringValue)
        let plainRange = (textStorage.string as NSString).range(of: "Running")
        let codeRange = (textStorage.string as NSString).range(of: "swift test")
        let plainFont = try XCTUnwrap(textStorage.attribute(.font, at: plainRange.location, effectiveRange: nil) as? NSFont)
        let codeFont = try XCTUnwrap(textStorage.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont)
        let plainColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: plainRange.location, effectiveRange: nil) as? NSColor)
        let codeColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: codeRange.location, effectiveRange: nil) as? NSColor)
        let codeBackground = try XCTUnwrap(textStorage.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil) as? NSColor)
        let expectedColor = transcriptInlineToolRowColor.resolved(for: header.appKitRenderingAppearance)
        let expectedBackground = transcriptInlineToolRowColor.appKitResolvedColor(in: header, alpha: 0.08)

        XCTAssertEqual(plainFont.pointSize, typography.size(for: .inlineToolText))
        XCTAssertEqual(codeFont.pointSize, typography.size(for: .inlineToolText))
        XCTAssertEqual(plainColor.resolved(for: header.appKitRenderingAppearance), expectedColor)
        XCTAssertEqual(codeColor.resolved(for: header.appKitRenderingAppearance), expectedColor)
        XCTAssertEqual(codeBackground.resolved(for: header.appKitRenderingAppearance), expectedBackground)
    }

    func testHeaderChromeUsesMutedInlineToolMetricsAndColor() throws {
        let header = AppKitTranscriptToolHeaderRowView()
        header.appearance = NSAppearance(named: .aqua)
        var settings = AppSettings()
        settings.chatFontSize = 18
        let typography = TranscriptTypography(settings: settings)
        let metrics = transcriptInlineToolRowMetrics(for: typography)
        header.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        header.configure(
            .init(
                summary: "Notebook read",
                leadingIcon: .document,
                phase: .error,
                isExpanded: false,
                typography: typography
            )
        )
        header.layoutSubtreeIfNeeded()

        let icon = try XCTUnwrap(header.descendantsForSubtleChromeTests(of: NSImageView.self).first)
        let statusView = try XCTUnwrap(header.descendantsForSubtleChromeTests(of: AppKitTranscriptToolStatusIndicatorView.self).first)
        let expectedColor = transcriptInlineToolRowColor.resolved(for: header.appKitRenderingAppearance)

        XCTAssertEqual(icon.frame.width, metrics.controlSize)
        XCTAssertEqual(metrics.iconTextSpacing, 3)
        XCTAssertEqual(metrics.textStatusSpacing, 3)
        XCTAssertEqual(metrics.leadingIconSize, typography.size(for: .inlineToolIndicator) + 2)
        XCTAssertEqual(metrics.statusIconSize, typography.size(for: .inlineToolIndicator) - 2)
        XCTAssertEqual(header.leadingIconSystemNameForTesting, "doc.text")
        XCTAssertEqual(icon.contentTintColor?.resolved(for: header.appKitRenderingAppearance), expectedColor)
        XCTAssertEqual(statusView.frame.width, metrics.controlSize)
        XCTAssertNil(statusView.statusSymbolSystemNameForTesting)
        XCTAssertEqual(statusView.statusSymbolPointSizeForTesting, metrics.statusIconSize)

        header.setDisclosureHoveredForTesting(true)
        XCTAssertEqual(statusView.statusSymbolSystemNameForTesting, "chevron.right")
        XCTAssertEqual(statusView.statusSymbolTintColorForTesting?.resolved(for: header.appKitRenderingAppearance), expectedColor)
    }

    func testHeaderChromeUsesBrighterSharedColorInDarkMode() throws {
        let header = AppKitTranscriptToolHeaderRowView()
        header.appearance = NSAppearance(named: .darkAqua)
        header.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        header.configure(
            .init(
                summary: "Notebook read",
                leadingIcon: .document,
                phase: .success
            )
        )
        header.layoutSubtreeIfNeeded()

        let textStorage = try XCTUnwrap(header.descendantsForSubtleChromeTests(of: NSTextField.self).first?.attributedStringValue)
        let plainRange = (textStorage.string as NSString).range(of: "Notebook")
        let plainColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: plainRange.location, effectiveRange: nil) as? NSColor)
        let icon = try XCTUnwrap(header.descendantsForSubtleChromeTests(of: NSImageView.self).first)
        let statusView = try XCTUnwrap(header.descendantsForSubtleChromeTests(of: AppKitTranscriptToolStatusIndicatorView.self).first)
        let expectedColor = transcriptInlineToolRowColor.resolved(for: header.appKitRenderingAppearance)

        XCTAssertEqual(expectedColor, NSColor.secondaryLabelColor.resolved(for: header.appKitRenderingAppearance))
        XCTAssertEqual(plainColor.resolved(for: header.appKitRenderingAppearance), expectedColor)
        XCTAssertEqual(icon.contentTintColor?.resolved(for: header.appKitRenderingAppearance), expectedColor)
        XCTAssertNil(statusView.statusSymbolSystemNameForTesting)
    }

    func testToolNamesUseSemanticLeadingIconKinds() {
        let readTool = semanticIconTool(name: "Read", summary: "Reading AGENTS.md")
        let listTool = semanticIconTool(name: "LS", summary: "Listing directory")
        let grepTool = semanticIconTool(name: "Grep", summary: "Searching for pattern")
        let globTool = semanticIconTool(name: "Glob", summary: "Searching for files")
        let editTool = semanticIconTool(name: "Edit", summary: "Editing AGENTS.md")
        let writeTool = semanticIconTool(name: "Write", summary: "Writing notes.md")

        XCTAssertEqual(readTool.transcriptLeadingIconKind, .read)
        XCTAssertEqual(listTool.transcriptLeadingIconKind, .folder)
        XCTAssertEqual(grepTool.transcriptLeadingIconKind, .search)
        XCTAssertEqual(globTool.transcriptLeadingIconKind, .search)
        XCTAssertEqual(editTool.transcriptLeadingIconKind, .edit)
        XCTAssertEqual(writeTool.transcriptLeadingIconKind, .write)
        XCTAssertEqual(ToolEntry.transcriptGroupLeadingIconKind(for: [readTool]), .read)
        XCTAssertEqual(ToolEntry.transcriptGroupLeadingIconKind(for: [listTool]), .folder)
        XCTAssertEqual(ToolEntry.transcriptGroupLeadingIconKind(for: [listTool, grepTool]), .search)
        XCTAssertEqual(ToolEntry.transcriptGroupLeadingIconKind(for: [editTool]), .edit)
        XCTAssertEqual(ToolEntry.transcriptGroupLeadingIconKind(for: [writeTool]), .write)
    }

    func testSemanticLeadingIconKindsUseExpectedSFSymbols() {
        assertHeaderIcon(.read, summary: "Read AGENTS.md", renders: "magnifyingglass")
        assertHeaderIcon(.folder, summary: "Listed directory", renders: "folder")
        assertHeaderIcon(.search, summary: "Searched for pattern", renders: "magnifyingglass")
        assertHeaderIcon(.edit, summary: "Edited AGENTS.md", renders: "pencil")
        assertHeaderIcon(.write, summary: "Wrote notes.md", renders: "pencil")
        assertHeaderIcon(.subAgent, summary: "Explored 1 sub-agent", renders: "hat.widebrim")
    }
}

@MainActor
private func assertHeaderIcon(_ kind: TranscriptToolLeadingIconKind, summary: String, renders systemName: String) {
    let header = AppKitTranscriptToolHeaderRowView()
    header.configure(
        .init(
            summary: summary,
            leadingIcon: kind,
            phase: .success
        )
    )
    XCTAssertEqual(header.leadingIconSystemNameForTesting, systemName)
}

private func semanticIconTool(name: String, summary: String) -> ToolEntry {
    ToolEntry(
        id: "tool-1",
        name: name,
        summary: summary,
        input: #"{"command":"echo hi"}"#,
        output: nil,
        stderr: nil,
        isComplete: false,
        isInterrupted: false,
        isImage: false,
        noOutputExpected: false,
        isError: false
    )
}

private extension NSView {
    func descendantsForSubtleChromeTests<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendantsForSubtleChromeTests(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
