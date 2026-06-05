import Foundation

/// Pulls single-body tool content out of tools that render as one code or markdown
/// surface, keeping AppKit row views focused on layout and interaction.
enum MinimalToolContent {
    struct Snapshot: Equatable {
        let content: String?
        let language: String
        let baseURL: URL?

        init(content: String?, language: String, baseURL: URL? = nil) {
            self.content = content
            self.language = language
            self.baseURL = baseURL
        }
    }

    static func snapshot(for tool: ToolEntry) -> Snapshot? {
        switch tool.name {
        case "Write":
            guard let preview = WriteToolContent.extract(from: tool) else {
                return Snapshot(content: nil, language: "")
            }
            return Snapshot(content: preview.content, language: preview.language, baseURL: preview.baseURL)
        case "Edit", "MultiEdit":
            guard let preview = FileEditToolContent.extract(from: tool) else {
                return nil
            }
            return Snapshot(content: preview.content, language: preview.language, baseURL: preview.baseURL)
        case "Read":
            return Snapshot(content: tool.output, language: ReadToolContent.language(for: tool), baseURL: ReadToolContent.baseURL(for: tool))
        case "Bash":
            return Snapshot(content: tool.output, language: "bash")
        default:
            return nil
        }
    }
}

extension ToolEntry {
    var autoExpandsMarkdownMutationPreview: Bool {
        guard isComplete,
              name == "Write" || name == "Edit" || name == "MultiEdit",
              let snapshot = MinimalToolContent.snapshot(for: self) else {
            return false
        }
        return snapshot.language == "markdown" && snapshot.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

/// Extracts the target path and bounded content preview from `Write` input JSON.
enum WriteToolContent {
    struct Preview: Equatable {
        let filePath: String
        let language: String
        let content: String

        var baseURL: URL? {
            guard !filePath.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: filePath).deletingLastPathComponent()
        }
    }

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

        return Preview(filePath: filePath, language: language, content: ToolContentPreviewLimiter.bounded(content))
    }
}

/// Extracts markdown replacement previews from file-edit inputs. `Edit` and
/// `MultiEdit` do not carry the full post-edit file, so this intentionally
/// previews only the inserted/replacement markdown the provider supplied.
enum FileEditToolContent {
    struct Preview: Equatable {
        let filePath: String
        let language: String
        let content: String

        var baseURL: URL? {
            guard !filePath.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: filePath).deletingLastPathComponent()
        }
    }

    static func extract(from tool: ToolEntry) -> Preview? {
        guard tool.name == "Edit" || tool.name == "MultiEdit",
              let json = parsedJSON(from: tool.input) else {
            return nil
        }
        let filePath = json["file_path"] as? String ?? json["path"] as? String ?? ""
        let language = FileLanguageHint.language(forPath: filePath)
        guard language == "markdown",
              let content = previewContent(from: json, toolName: tool.name),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return Preview(filePath: filePath, language: language, content: ToolContentPreviewLimiter.bounded(content))
    }

    private static func parsedJSON(from input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func previewContent(from json: [String: Any], toolName: String) -> String? {
        if toolName == "Edit" {
            return json["new_string"] as? String
        }
        guard let edits = json["edits"] as? [[String: Any]] else {
            return nil
        }
        let replacementBlocks: [String] = edits.compactMap { edit -> String? in
            guard let replacement = edit["new_string"] as? String else {
                return nil
            }
            let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedReplacement.isEmpty ? nil : trimmedReplacement
        }
        return replacementBlocks.isEmpty ? nil : replacementBlocks.joined(separator: "\n\n")
    }
}

private enum ToolContentPreviewLimiter {
    private static let maxLines = 300
    private static let maxCharacters = 20_000

    static func bounded(_ content: String) -> String {
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

        return displayContent
    }
}

/// Resolves `Read` output metadata from the tool input JSON and strips Claude-style
/// line-number prefixes when read markdown is rendered as markdown.
enum ReadToolContent {
    static func language(for tool: ToolEntry) -> String {
        guard tool.name == "Read",
              let filePath = filePath(for: tool) else {
            return ""
        }
        return FileLanguageHint.language(forPath: filePath)
    }

    static func baseURL(for tool: ToolEntry) -> URL? {
        guard tool.name == "Read",
              let filePath = filePath(for: tool) else {
            return nil
        }
        return URL(fileURLWithPath: filePath).deletingLastPathComponent()
    }

    static func strippingLineNumberPrefixes(from output: String) -> String {
        output.split(separator: "\n", omittingEmptySubsequences: false)
            .map { stripLineNumberPrefix(from: String($0)) }
            .joined(separator: "\n")
    }

    private static func filePath(for tool: ToolEntry) -> String? {
        guard let data = tool.input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["file_path"] as? String
    }

    private static func stripLineNumberPrefix(from line: String) -> String {
        if let tabIndex = line.firstIndex(of: "\t") {
            let prefix = line[..<tabIndex].trimmingCharacters(in: .whitespaces)
            if !prefix.isEmpty, prefix.allSatisfy(\.isNumber) {
                return String(line[line.index(after: tabIndex)...])
            }
        }
        let trimmedLeadingSpaces = line.drop(while: \.isWhitespace)
        let digits = trimmedLeadingSpaces.prefix(while: \.isNumber)
        let afterDigits = trimmedLeadingSpaces.dropFirst(digits.count)
        if !digits.isEmpty, afterDigits.isEmpty {
            return ""
        }
        if !digits.isEmpty, afterDigits.first == " " {
            return String(afterDigits.drop(while: { $0 == " " }))
        }
        return line
    }
}

enum TranscriptToolOutputPaging {
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

func prettyPrintedJSON(_ content: String) -> String {
    guard let data = content.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let pretty = String(data: prettyData, encoding: .utf8) else {
        return content
    }
    return pretty
}
