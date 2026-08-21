import Foundation
import SwiftUI

/// Point size of the SwiftUI chevron. AppKit sizes its own glyph from the slot width instead, so
/// this one number has no Core counterpart.
private let appMarkdownDetailsChevronFontSize: CGFloat = 10

/// A GitHub `<details>` disclosure.
///
/// Expansion is seeded from `AppMarkdownDetailsExpansionStore` rather than starting at the block's
/// `open` attribute every time, because comment rows recycle: the Changes tab's `LazyVStack`
/// discards row state once a row leaves the realized window, and a reader who opened a disclosure
/// then scrolled the diff would find it shut on the way back.
struct AppMarkdownDetailsBlockView: View {
    let block: AppMarkdownDetailsBlock
    let taskStateNamespace: String
    let path: String
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    var baseURL: URL?

    @State private var isExpanded: Bool

    init(
        block: AppMarkdownDetailsBlock,
        taskStateNamespace: String,
        path: String,
        inlineCodeStyle: AppMarkdownInlineCodeStyle,
        baseURL: URL? = nil
    ) {
        self.block = block
        self.taskStateNamespace = taskStateNamespace
        self.path = path
        self.inlineCodeStyle = inlineCodeStyle
        self.baseURL = baseURL
        _isExpanded = State(
            initialValue: AppMarkdownDetailsExpansionStore.value(
                for: AppMarkdownDetailsExpansionStore.key(namespace: taskStateNamespace, path: path),
                defaultValue: block.isInitiallyOpen
            )
        )
    }

    var body: some View {
        // `bodySpacing` is spent inside the `if`, never as stack spacing: a `VStack` with a
        // non-zero spacing would hold that gap open under a collapsed disclosure.
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded, !block.blocks.isEmpty {
                AppMarkdownBlockList(
                    blocks: block.blocks,
                    taskStateNamespace: taskStateNamespace,
                    pathPrefix: path,
                    inlineCodeStyle: inlineCodeStyle,
                    baseURL: baseURL
                )
                .padding(.top, AppMarkdownDetailsMetrics.bodySpacing)
                .padding(.leading, AppMarkdownDetailsMetrics.bodyIndent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appExpansionAnimationOverride(value: isExpanded)
    }

    /// A disclosure with nothing to reveal draws its summary but takes no click, matching
    /// `AppKitMarkdownDetailsHeaderView.isEnabled`. Building the toggle and disabling it would not
    /// do: `AppHeaderToggle` activates through an AppKit mouse target that SwiftUI's `.disabled`
    /// does not reach.
    @ViewBuilder
    private var header: some View {
        if block.blocks.isEmpty {
            headerContent.opacity(AppMarkdownDetailsMetrics.inertHeaderOpacity)
        } else {
            AppHeaderToggle(fillsWidth: false, action: toggle) {
                headerContent
            }
            .help(isExpanded ? "Collapse section" : "Expand section")
            .accessibilityLabel(summaryAccessibilityLabel)
            .accessibilityValue(isExpanded ? "expanded" : "collapsed")
            .accessibilityAddTraits(.isButton)
        }
    }

    private var headerContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppMarkdownDetailsMetrics.chevronSpacing) {
            Image(systemName: "chevron.right")
                .font(.system(size: appMarkdownDetailsChevronFontSize, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: AppMarkdownDetailsMetrics.chevronWidth)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))

            AppMarkdownInlineText(content: block.summary, inlineCodeStyle: inlineCodeStyle)
        }
        // The renderer turns selection on for the whole document, and a selectable `Text`
        // swallows the click that should open the disclosure — the same reason task checkboxes
        // opt out.
        .textSelection(.disabled)
    }

    private var summaryAccessibilityLabel: String {
        let text = String(block.summary.characters)
        return text.isEmpty ? AppMarkdownDetailsSyntaxParser.defaultSummary : text
    }

    private func toggle() {
        withAnimation(appExpansionAnimation) {
            isExpanded.toggle()
        }
        AppMarkdownDetailsExpansionStore.set(
            isExpanded,
            for: AppMarkdownDetailsExpansionStore.key(namespace: taskStateNamespace, path: path)
        )
    }
}
