import Foundation
import SwiftUI

private let toolGroupStatusIndicatorDebounce: Duration = .milliseconds(250)
private let transcriptToolSummarySlashCommandPattern = #"(^|[\s\(\[\{<"'])(/[A-Za-z][A-Za-z0-9_-]*)(?=$|[\s\)\]\}>"'.,;:])"#

/// Parse a tool summary as inline Markdown and apply the same lightweight chip treatment
/// used by transcript text for backticked spans, slash commands, and file mentions.
/// Parsing and run-walking on every body evaluation showed up as a hot path during
/// transcript scrolling, so results are memoized for the lifetime of the session.
@MainActor
private func attributedToolSummary(_ text: String) -> AttributedString {
    AttributedSummaryCache.attributed(text)
}

@MainActor
private enum AttributedSummaryCache {
    static var cache: [String: AttributedString] = [:]
    private static let slashCommandRegex = try? NSRegularExpression(pattern: transcriptToolSummarySlashCommandPattern)

    static func attributed(_ text: String) -> AttributedString {
        if let cached = cache[text] {
            return cached
        }

        let result: AttributedString
        let parser = AppMarkdownParser(
            composerChipProvider: toolSummaryTextChips(in:),
            parsingMode: .inline
        )
        if var attributed = try? parser.attributedString(for: text) {
            applyInlineChipStyle(to: &attributed)
            result = attributed
        } else {
            result = AttributedString(text)
        }

        cache[text] = result
        return result
    }

    private static func applyInlineChipStyle(to attributed: inout AttributedString) {
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].backgroundColor = Color.secondary.opacity(0.18)
        }
    }

    private static func toolSummaryTextChips(in text: String) -> [AppTextEditorChip] {
        let codeRanges = AppMarkdownCodeBlockParser.codeRanges(in: text)
        let excludedRanges = codeRanges.blockRanges + codeRanges.inlineFullRanges
        let source = text as NSString

        var chips = ChatInputFieldTextSupport.fileMentionMatches(in: text).map { match in
            AppTextEditorChip(
                range: match.highlightRange,
                displayText: ChatInputFieldTextSupport.mentionChipDisplayText(for: match.path),
                style: .fileMention
            )
        }

        if let slashCommandRegex {
            let fullRange = NSRange(location: 0, length: source.length)
            chips.append(contentsOf: slashCommandRegex.matches(in: text, range: fullRange).compactMap { match in
                guard match.numberOfRanges >= 3 else {
                    return nil
                }
                let commandRange = match.range(at: 2)
                guard commandRange.location != NSNotFound else {
                    return nil
                }
                return AppTextEditorChip(
                    range: commandRange,
                    displayText: source.substring(with: commandRange),
                    style: .slashCommand
                )
            })
        }

        return chips
            .filter { chip in
                !excludedRanges.contains { NSIntersectionRange($0, chip.range).length > 0 }
            }
            .sorted { $0.range.location < $1.range.location }
    }
}

struct ToolHeaderRow: View {
    let tool: ToolEntry
    let isExpanded: Bool
    var bottomPadding = transcriptToolRowVerticalPadding

    var body: some View {
        TranscriptToolHeaderContent(summary: tool.transcriptDisplaySummary, bottomPadding: bottomPadding) {
            TranscriptToolLeadingIcon(kind: leadingIconKind)
        } status: {
            ToolStatusIndicator(phase: tool.transcriptStatusPhase)
        }
    }

    private var leadingIconKind: TranscriptToolLeadingIconKind {
        switch tool.name {
        case "Bash":
            return .bash
        case "Skill":
            return .symbol(systemName: "book")
        default:
            return .disclosure(isExpanded: isExpanded)
        }
    }
}

struct TranscriptDisclosureHeaderRow: View {
    let summary: String
    let isExpanded: Bool
    let phase: ToolStatusPhase
    var debounceStatus = false
    var bottomPadding = transcriptToolRowVerticalPadding

    var body: some View {
        TranscriptToolHeaderContent(summary: summary, bottomPadding: bottomPadding) {
            TranscriptToolLeadingIcon(kind: .disclosure(isExpanded: isExpanded))
        } status: {
            if debounceStatus {
                DebouncedToolStatusIndicator(phase: phase)
            } else {
                ToolStatusIndicator(phase: phase)
            }
        }
    }
}

struct TranscriptStaticHeaderRow: View {
    let title: String
    let systemImage: String
    var bottomPadding = transcriptToolRowVerticalPadding
    var fillsWidth = true

    var body: some View {
        let content = ViewThatFits(in: .horizontal) {
            row(fixesTitleWidth: true)
            row(fixesTitleWidth: false)
        }
        .padding(.top, transcriptToolRowVerticalPadding)
        .padding(.bottom, bottomPadding)
        .contentShape(Rectangle())

        if fillsWidth {
            content.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content
        }
    }

    private func row(fixesTitleWidth: Bool) -> some View {
        HStack(alignment: .center, spacing: 0) {
            TranscriptToolLeadingIcon(kind: .symbol(systemName: systemImage))

            titleText(fixesWidth: fixesTitleWidth)
        }
    }

    @ViewBuilder
    private func titleText(fixesWidth: Bool) -> some View {
        let text = Text(title)
            .font(.system(size: transcriptToolSummaryFontSize))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, transcriptToolLeadingTextSpacing)

        if fixesWidth {
            text.fixedSize(horizontal: true, vertical: false)
        } else {
            text
        }
    }
}

private struct TranscriptToolHeaderContent<LeadingIcon: View, Status: View>: View {
    let summary: String
    let bottomPadding: CGFloat
    let leadingIcon: LeadingIcon
    let status: Status

    init(
        summary: String,
        bottomPadding: CGFloat = transcriptToolRowVerticalPadding,
        @ViewBuilder leadingIcon: () -> LeadingIcon,
        @ViewBuilder status: () -> Status
    ) {
        self.summary = summary
        self.bottomPadding = bottomPadding
        self.leadingIcon = leadingIcon()
        self.status = status()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(fixesSummaryWidth: true)
            row(fixesSummaryWidth: false)
        }
        .padding(.top, transcriptToolRowVerticalPadding)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func row(fixesSummaryWidth: Bool) -> some View {
        HStack(alignment: .center, spacing: 0) {
            leadingIcon
                .frame(width: transcriptToolIconFrameSize, height: transcriptToolIconFrameSize, alignment: .center)

            summaryText(fixesWidth: fixesSummaryWidth)

            status
                .frame(width: transcriptToolStatusFrameSize, height: transcriptToolStatusFrameSize, alignment: .center)
                .padding(.leading, transcriptToolTextStatusSpacing)
        }
    }

    @ViewBuilder
    private func summaryText(fixesWidth: Bool) -> some View {
        let text = Text(attributedToolSummary(summary))
            .font(.system(size: transcriptToolSummaryFontSize))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, transcriptToolLeadingTextSpacing)

        if fixesWidth {
            text.fixedSize(horizontal: true, vertical: false)
        } else {
            text
        }
    }
}

enum TranscriptToolLeadingIconKind: Equatable {
    case disclosure(isExpanded: Bool)
    case bash
    case symbol(systemName: String)
}

struct TranscriptToolLeadingIcon: View {
    let kind: TranscriptToolLeadingIconKind

    var body: some View {
        Image(systemName: systemName)
            .font(iconFont)
            .foregroundStyle(.primary)
            .rotationEffect(.degrees(rotationDegrees))
            .frame(width: transcriptToolIconFrameSize, height: transcriptToolIconFrameSize, alignment: .center)
            .allowsHitTesting(false)
            .animation(toolExpansionAnimation, value: rotationDegrees)
    }

    private var systemName: String {
        switch kind {
        case .disclosure:
            // Rotating one symbol keeps disclosure transitions animated; swapping
            // between chevron SF Symbols snaps before the row animation settles.
            return "chevron.right"
        case .bash:
            return "dollarsign"
        case .symbol(let systemName):
            return systemName
        }
    }

    private var rotationDegrees: Double {
        switch kind {
        case .disclosure(let isExpanded):
            return isExpanded ? 90 : 0
        case .bash, .symbol:
            return 0
        }
    }

    private var iconFont: Font {
        switch kind {
        case .disclosure, .symbol:
            return .system(size: transcriptToolIconFontSize, weight: .regular)
        case .bash:
            return .system(size: transcriptToolIconFontSize, weight: .regular)
        }
    }
}

enum ToolStatusPhase: Equatable {
    case loading
    case success
    case error

    init(isError: Bool, isComplete: Bool) {
        if !isComplete {
            self = .loading
        } else if isError {
            self = .error
        } else {
            self = .success
        }
    }

    var isTerminal: Bool {
        self != .loading
    }

    var branchKey: Int {
        switch self {
        case .error:
            return 0
        case .success:
            return 1
        case .loading:
            return 2
        }
    }
}

@MainActor
final class ToolStatusIndicatorDebouncer: ObservableObject {
    @Published private(set) var displayedPhase: ToolStatusPhase

    private let debounceDelay: Duration
    private var pendingTask: Task<Void, Never>?
    private var pendingPhaseVersion = 0

    init(initialPhase: ToolStatusPhase, debounceDelay: Duration = toolGroupStatusIndicatorDebounce) {
        displayedPhase = initialPhase
        self.debounceDelay = debounceDelay
    }

    deinit {
        pendingTask?.cancel()
    }

    func update(to phase: ToolStatusPhase) {
        pendingTask?.cancel()
        pendingTask = nil
        pendingPhaseVersion &+= 1

        let phaseVersion = pendingPhaseVersion

        guard phase != displayedPhase else {
            return
        }

        guard phase.isTerminal else {
            displayedPhase = .loading
            return
        }

        pendingTask = Task { @MainActor [debounceDelay] in
            do {
                try await Task.sleep(for: debounceDelay)
            } catch {
                return
            }

            guard phaseVersion == pendingPhaseVersion else {
                return
            }

            displayedPhase = phase
            pendingTask = nil
        }
    }

    func cancelPendingUpdate() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}

/// Multi-entry tool groups can briefly look done before another tool call streams in.
/// Delay terminal icons slightly so aggregate headers stay on the spinner until the
/// group has actually settled.
struct DebouncedToolStatusIndicator: View {
    let phase: ToolStatusPhase

    @StateObject private var debouncer: ToolStatusIndicatorDebouncer

    init(phase: ToolStatusPhase) {
        self.phase = phase
        _debouncer = StateObject(wrappedValue: ToolStatusIndicatorDebouncer(initialPhase: phase))
    }

    var body: some View {
        ToolStatusIndicator(phase: debouncer.displayedPhase)
            .onChange(of: phase) { _, newValue in
                debouncer.update(to: newValue)
            }
            .onDisappear {
                debouncer.cancelPendingUpdate()
            }
    }
}

/// Status indicator shared by single-tool rows and aggregate headers. All states keep
/// the same layout box so spinner-to-symbol transitions do not resize rows.
struct ToolStatusIndicator: View {
    let phase: ToolStatusPhase

    init(phase: ToolStatusPhase) {
        self.phase = phase
    }

    init(isError: Bool, isComplete: Bool) {
        phase = ToolStatusPhase(isError: isError, isComplete: isComplete)
    }

    var body: some View {
        Group {
            if phase == .error {
                Image(systemName: "xmark")
                    .font(.system(size: transcriptToolStatusIconFontSize, weight: .regular))
                    .foregroundStyle(.red)
            } else if phase == .success {
                Image(systemName: "checkmark")
                    .font(.system(size: transcriptToolStatusIconFontSize, weight: .regular))
                    .foregroundStyle(.green)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(transcriptToolStatusSpinnerScale)
            }
        }
        .frame(width: transcriptToolStatusFrameSize, height: transcriptToolStatusFrameSize, alignment: .center)
        .transaction(value: branchKey) { $0.animation = nil }
        .allowsHitTesting(false)
    }

    private var branchKey: Int {
        phase.branchKey
    }
}

extension ToolEntry {
    var transcriptStatusPhase: ToolStatusPhase {
        ToolStatusPhase(isError: isError, isComplete: isComplete)
    }

    var transcriptDisplaySummary: String {
        switch name {
        case "Bash":
            return "\(isComplete ? "Ran" : "Running") \(bashSummaryBody)"
        case "Read":
            return isComplete
                ? summary.replacingLeadingWord("Reading", with: "Read")
                : summary.replacingLeadingWord("Read", with: "Reading")
        case "Grep", "Glob":
            return isComplete ? summary.replacingPrefix("Searching ", with: "Searched ") : summary
        case "ToolSearch":
            return isComplete ? summary.replacingPrefix("Searching ", with: "Searched ") : summary
        case "WebSearch":
            return isComplete ? summary.replacingPrefix("Searching ", with: "Searched ") : summary
        case "WebFetch":
            return isComplete ? summary.replacingPrefix("Fetching ", with: "Fetched ") : summary
        case "Edit", "MultiEdit", "NotebookEdit":
            return summary.replacingLeadingWord(name, with: isComplete ? "Edited" : "Editing")
        case "Write":
            return summary.replacingLeadingWord("Write", with: isComplete ? "Wrote" : "Writing")
        default:
            return summary
        }
    }

    private var bashSummaryBody: String {
        summary
            .replacingPrefix("Executing ", with: "")
            .replacingPrefix("Running ", with: "")
            .replacingPrefix("Ran ", with: "")
    }
}

private extension String {
    func replacingLeadingWord(_ word: String, with replacement: String) -> String {
        replacingPrefix("\(word) ", with: "\(replacement) ")
    }

    func replacingPrefix(_ prefix: String, with replacement: String) -> String {
        guard hasPrefix(prefix) else {
            return self
        }
        return replacement + String(dropFirst(prefix.count))
    }
}
