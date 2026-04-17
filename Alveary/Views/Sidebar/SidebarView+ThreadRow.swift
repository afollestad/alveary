import AppKit
import SwiftData
import SwiftUI

struct SidebarThreadRow: View {
    let thread: AgentThread
    let status: ThreadStatus
    @Binding var editingThreadID: PersistentIdentifier?
    let onCommitRename: (String) -> Void

    @State private var editText = ""
    @FocusState private var isFieldFocused: Bool

    private var isEditing: Bool {
        editingThreadID == thread.persistentModelID
    }

    private var displayName: String {
        thread.displayName()
    }

    private var containsMarkdownCode: Bool {
        AppMarkdownCodeBlockParser.containsCode(in: displayName)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .offset(x: -3)

            if isEditing {
                TextField("Thread name", text: $editText)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    .lineLimit(1)
            } else if containsMarkdownCode {
                SidebarThreadTitleChips(text: displayName)
                    .allowsHitTesting(false)
            } else {
                Text(displayName)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .onChange(of: isEditing) { _, editing in
            if editing {
                editText = displayName
                isFieldFocused = true
            }
        }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused && isEditing {
                commitRename()
            }
        }
        .accessibilityAction(named: Text("Rename")) {
            editingThreadID = thread.persistentModelID
        }
    }

    private var statusColor: Color {
        switch status {
        case .busy:
            return .green
        case .idle:
            return .blue
        case .error:
            return .red
        case .archived:
            return .secondary
        case .stopped:
            return .secondary
        }
    }

    private func commitRename() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onCommitRename(trimmed)
        }
        editingThreadID = nil
    }

    private func cancelRename() {
        editingThreadID = nil
    }
}

/// Renders a thread title that contains inline code as an `HStack` of plain text and chip
/// views. Each chip is clamped to the body text's line height in layout so the chip's
/// rounded background visually overflows into the row's vertical padding without inflating
/// the sidebar row height.
private struct SidebarThreadTitleChips: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let value):
                    Text(value)
                case .code(let value):
                    AppMarkdownInlineCodeChip(text: value, style: .standard, fontSize: chipFontSize)
                        .fixedSize()
                        .frame(height: bodyLineHeight, alignment: .center)
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var segments: [SidebarTitleSegment] {
        SidebarTitleSegment.segments(for: text)
    }

    private var chipFontSize: CGFloat {
        NSFont.preferredFont(forTextStyle: .body).pointSize * markdownInlineCodeFontScale
    }

    private var bodyLineHeight: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        return ceil(font.ascender + abs(font.descender) + font.leading)
    }
}

private enum SidebarTitleSegment {
    case text(String)
    case code(String)

    static func segments(for markdown: String) -> [SidebarTitleSegment] {
        let ranges = AppMarkdownCodeBlockParser.codeRanges(in: markdown)
        let pairs = zip(ranges.inlineFullRanges, ranges.inlineContentRanges)
            .sorted { $0.0.location < $1.0.location }
        guard !pairs.isEmpty else {
            return [.text(markdown)]
        }

        let source = markdown as NSString
        var result: [SidebarTitleSegment] = []
        var cursor = 0
        for (fullRange, contentRange) in pairs {
            if fullRange.location > cursor {
                let prefix = source.substring(with: NSRange(location: cursor, length: fullRange.location - cursor))
                if !prefix.isEmpty {
                    result.append(.text(prefix))
                }
            }
            result.append(.code(source.substring(with: contentRange)))
            cursor = NSMaxRange(fullRange)
        }
        if cursor < source.length {
            let suffix = source.substring(with: NSRange(location: cursor, length: source.length - cursor))
            if !suffix.isEmpty {
                result.append(.text(suffix))
            }
        }
        return result
    }
}
