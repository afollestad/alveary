import Foundation
import SwiftUI

struct ToolDetails: View {
    let tool: ToolEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            primaryContent

            if let stderr = tool.stderr,
               !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DetailCodeBlock(title: "stderr", content: stderr, tint: .orange)
            }
        }
    }

    @ViewBuilder
    private var primaryContent: some View {
        if let snapshot = MinimalToolContent.snapshot(for: tool) {
            MinimalToolContentView(tool: tool, snapshot: snapshot)
        } else {
            defaultInputOutput
        }
    }

    @ViewBuilder
    private var defaultInputOutput: some View {
        DetailCodeBlock(title: "Input", content: prettyPrintedJSON(tool.input))

        if let output = tool.output {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if tool.isImage {
                Label("Image output isn't previewed yet.", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if trimmed.isEmpty {
                if !tool.noOutputExpected {
                    Text("No output")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ToolOutputView(tool: tool, content: output)
            }
        }
    }
}

/// Shared expanded-content renderer for tools that display a single body of code/text:
/// `Write` (the file content it's writing), `Read` (the file body it read), `Bash` (the
/// command's stdout). Handles the failure fallback (red error block), the image-output
/// case, the noOutputExpected case, and otherwise routes to `HighlightedCodeBlock`.
struct MinimalToolContentView: View {
    let tool: ToolEntry
    let snapshot: MinimalToolContent.Snapshot

    var body: some View {
        if tool.isError, let error = nonEmptyOutput {
            ErrorContentBlock(content: error)
        } else if tool.isImage {
            Label("Image output isn't previewed yet.", systemImage: "photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let content = snapshot.content,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HighlightedCodeBlock(content: content, language: snapshot.language)
        } else if !tool.noOutputExpected {
            Text("No output")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nonEmptyOutput: String? {
        guard let output = tool.output,
              !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return output
    }
}

/// Pulls the single-body content out of the three tools that should render as one code
/// block (Write/Read/Bash), plus the language hint used for syntax highlighting.
enum MinimalToolContent {
    struct Snapshot {
        let content: String?
        let language: String
    }

    static func snapshot(for tool: ToolEntry) -> Snapshot? {
        switch tool.name {
        case "Write":
            guard let preview = WriteToolContent.extract(from: tool) else {
                return Snapshot(content: nil, language: "")
            }
            return Snapshot(content: preview.content, language: preview.language)
        case "Read":
            return Snapshot(content: tool.output, language: ReadToolContent.language(for: tool))
        case "Bash":
            return Snapshot(content: tool.output, language: "bash")
        default:
            return nil
        }
    }
}

private struct ErrorContentBlock: View {
    let content: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(content)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppMarkdownCodeBlockPalette.fillColor(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppMarkdownCodeBlockPalette.borderColor(for: colorScheme), lineWidth: 1)
            )
    }
}

/// Write tool input parsing — extracts the target file path + the content Claude is
/// writing and caps it so a huge file doesn't balloon the transcript.
enum WriteToolContent {
    struct Preview {
        let filePath: String
        let language: String
        let content: String
    }

    private static let maxLines = 300
    private static let maxCharacters = 20_000

    static func extract(from tool: ToolEntry) -> Preview? {
        guard tool.name == "Write" else {
            return nil
        }
        guard let data = tool.input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? String else {
            return nil
        }
        let filePath = json["file_path"] as? String ?? ""
        let language = FileLanguageHint.language(forPath: filePath)

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var displayContent = lines.count > maxLines
            ? lines.prefix(maxLines).joined(separator: "\n")
            : content

        if displayContent.count > maxCharacters {
            displayContent = String(displayContent.prefix(maxCharacters))
            if let lastNewline = displayContent.lastIndex(of: "\n") {
                displayContent = String(displayContent[..<lastNewline])
            }
        }

        return Preview(filePath: filePath, language: language, content: displayContent)
    }
}

/// Resolve a syntax-highlighting language hint for the `Read` tool's output by parsing
/// the `file_path` argument out of the tool's JSON input.
enum ReadToolContent {
    static func language(for tool: ToolEntry) -> String {
        guard tool.name == "Read",
              let data = tool.input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let filePath = json["file_path"] as? String else {
            return ""
        }
        return FileLanguageHint.language(forPath: filePath)
    }
}

/// Renders a tool's output, tailed when the tool's output tends to be long (Bash, Read).
/// A paging button reveals additional lines from the top of the buffer (extending backward
/// in time for Bash, earlier in the file for Read) until the full content is shown.
struct ToolOutputView: View {
    let tool: ToolEntry
    let content: String

    @State private var visibleTailLines: Int

    init(tool: ToolEntry, content: String) {
        self.tool = tool
        self.content = content
        _visibleTailLines = State(initialValue: Self.initialTailLineCount(for: tool.name))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isPaged {
                DetailCodeBlock(title: outputTitle, content: visibleContent)

                HStack(spacing: 10) {
                    Button(showMoreLabel) {
                        visibleTailLines = min(visibleTailLines + pageStep, totalLineCount)
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)

                    Text("\(visibleTailLines) / \(totalLineCount) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }
            } else {
                DetailCodeBlock(title: "Output", content: content)
            }
        }
    }

    private var totalLineCount: Int {
        content.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private var isPaged: Bool {
        supportsPaging && totalLineCount > visibleTailLines
    }

    private var supportsPaging: Bool {
        Self.pageStep(for: tool.name) != nil
    }

    private var pageStep: Int {
        Self.pageStep(for: tool.name) ?? 10
    }

    private var visibleContent: String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = lines.suffix(visibleTailLines)
        return tail.joined(separator: "\n")
    }

    private var outputTitle: String {
        "Output (showing last \(visibleTailLines) of \(totalLineCount) lines)"
    }

    private var showMoreLabel: String {
        let remaining = totalLineCount - visibleTailLines
        let step = min(pageStep, remaining)
        return "Show \(step) more"
    }

    static func initialTailLineCount(for toolName: String) -> Int {
        switch toolName {
        case "Bash":
            return 10
        case "Read":
            return 20
        default:
            return Int.max
        }
    }

    static func pageStep(for toolName: String) -> Int? {
        switch toolName {
        case "Bash":
            return 10
        case "Read":
            return 20
        default:
            return nil
        }
    }
}
