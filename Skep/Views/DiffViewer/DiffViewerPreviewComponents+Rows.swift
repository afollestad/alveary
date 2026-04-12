import AppKit
import SwiftUI

struct CollapsedContextSummary {
    let lineCount: Int
    let oldStart: Int?
    let oldEnd: Int?
    let newStart: Int?
    let newEnd: Int?
}

struct DiffCollapsedContextRow: View {
    let summary: CollapsedContextSummary
    let lineNumberWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                omissionColumn
                omissionColumn
                omissionMarker
            }
            .background(Color.primary.opacity(0.04))

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)

            Text(omissionText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .background(Color.primary.opacity(0.03))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var omissionColumn: some View {
        Text("…")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: lineNumberWidth, alignment: .center)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }

    private var omissionMarker: some View {
        Text("…")
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 18)
            .accessibilityHidden(true)
    }

    private var omissionText: String {
        "\(summary.lineCount) unchanged lines hidden"
    }

    private var accessibilityText: Text {
        let oldRange = rangeDescription(prefix: "old", start: summary.oldStart, end: summary.oldEnd)
        let newRange = rangeDescription(prefix: "new", start: summary.newStart, end: summary.newEnd)
        return Text([omissionText, oldRange, newRange].compactMap { $0 }.joined(separator: ", "))
    }

    private func rangeDescription(prefix: String, start: Int?, end: Int?) -> String? {
        guard let start,
              let end else {
            return nil
        }

        if start == end {
            return "\(prefix) line \(start)"
        }

        return "\(prefix) lines \(start) through \(end)"
    }
}

struct DiffLineRow: View {
    let line: DiffLine
    let lineNumberWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                lineNumber(line.oldLineNumber)
                lineNumber(line.newLineNumber)

                Text(verbatim: marker)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(markerColor)
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }
            .background(gutterBackgroundColor)

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)

            Text(verbatim: line.content.isEmpty ? " " : line.content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .fixedSize(horizontal: true, vertical: false)
        }
        .background(rowBackgroundColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private func lineNumber(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? " ")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: lineNumberWidth, alignment: .trailing)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }

    private var marker: String {
        switch line.type {
        case .context:
            return " "
        case .added:
            return "+"
        case .deleted:
            return "-"
        }
    }

    private var markerColor: Color {
        switch line.type {
        case .context:
            return .secondary
        case .added:
            return .green
        case .deleted:
            return .red
        }
    }

    private var rowBackgroundColor: Color {
        switch line.type {
        case .context:
            return .clear
        case .added:
            return .green.opacity(0.12)
        case .deleted:
            return .red.opacity(0.12)
        }
    }

    private var gutterBackgroundColor: Color {
        switch line.type {
        case .context:
            return Color.primary.opacity(0.04)
        case .added:
            return .green.opacity(0.18)
        case .deleted:
            return .red.opacity(0.18)
        }
    }

    private var accessibilityDescription: String {
        let changeLabel: String
        switch line.type {
        case .context:
            changeLabel = "Context"
        case .added:
            changeLabel = "Added"
        case .deleted:
            changeLabel = "Deleted"
        }

        let oldNumberLabel = line.oldLineNumber.map { "Old line \($0)" }
        let newNumberLabel = line.newLineNumber.map { "New line \($0)" }
        let contentLabel = line.content.isEmpty ? "blank line" : line.content

        return [changeLabel, oldNumberLabel, newNumberLabel, contentLabel]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

struct RawDiffFallbackView: View {
    let rawDiffContent: String
    let note: String?

    var body: some View {
        DiffPreviewScrollContainer {
            VStack(alignment: .leading, spacing: 10) {
                if let note,
                   !note.isEmpty {
                    DiffCalloutCard(icon: "text.alignleft", title: "Raw patch", message: note)
                }

                Text(verbatim: rawDiffContent.isEmpty ? "No diff preview available." : rawDiffContent)
                    .font(.system(.caption, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .textSelection(.enabled)
        }
    }
}

struct DiffPreviewScrollContainer<Content: View>: View {
    private let contentPadding: CGFloat = 14

    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(proxy.size.width - (contentPadding * 2), 0)
            let availableHeight = max(proxy.size.height - (contentPadding * 2), 0)

            ScrollView([.horizontal, .vertical]) {
                content()
                    .frame(
                        minWidth: availableWidth,
                        minHeight: availableHeight,
                        alignment: .topLeading
                    )
                    .padding(contentPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct DiffCalloutCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
    }
}

struct DiffPreviewBadge: View {
    enum Tone {
        case neutral
        case accent
        case added
        case deleted
    }

    let title: String
    let tone: Tone

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            )
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .added:
            return .green
        case .deleted:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral:
            return Color.primary.opacity(0.08)
        case .accent:
            return Color.accentColor.opacity(0.14)
        case .added:
            return Color.green.opacity(0.14)
        case .deleted:
            return Color.red.opacity(0.14)
        }
    }
}
