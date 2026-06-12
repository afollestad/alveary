import Foundation

/// Leading glyph contract for AppKit tool headers. Keep this UI-neutral so the
/// row factory can decide expansion state while header views only render it.
enum TranscriptToolLeadingIconKind: Equatable {
    case terminal
    case search
    case folder
    case read
    case book
    case document
    case edit
    case write
    case skill
    case checklist
    case question
    case subAgent
    case toolGroup
    case genericTool
}

/// Stable status model shared by single tool rows, groups, and sub-agent rows.
/// It intentionally separates loading from terminal states so AppKit views can
/// debounce only terminal transitions without re-parsing tool completion flags.
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
}

extension ToolEntry {
    /// Compact loading/success/error phase derived from the tool's completion
    /// and error flags.
    var transcriptStatusPhase: ToolStatusPhase {
        ToolStatusPhase(isError: isError, isComplete: isComplete)
    }

    var transcriptLeadingIconKind: TranscriptToolLeadingIconKind {
        switch name {
        case let name where CommandToolPresentation.isCommandToolName(name):
            return .terminal
        case "LS":
            return .folder
        case "Read":
            return .read
        case "NotebookRead":
            return .document
        case "Grep", "Glob", "ToolSearch", "WebSearch", "WebFetch":
            return .search
        case "Edit", "MultiEdit", "NotebookEdit":
            return .edit
        case "Write":
            return .write
        case "Skill":
            return .skill
        case "TodoWrite":
            return .checklist
        default:
            return .genericTool
        }
    }

    static func transcriptGroupLeadingIconKind(for tools: [ToolEntry]) -> TranscriptToolLeadingIconKind {
        let icons = tools.map(\.transcriptLeadingIconKind)
        if icons.contains(.terminal) {
            return .terminal
        }
        if icons.contains(.search) {
            return .search
        }
        if icons.contains(.folder) {
            return .folder
        }
        if icons.contains(.read) {
            return .read
        }
        if icons.contains(.document) {
            return .document
        }
        if icons.contains(.edit) {
            return .edit
        }
        if icons.contains(.write) {
            return .write
        }
        if icons.contains(.book) {
            return .book
        }
        return icons.first ?? .toolGroup
    }

    /// User-facing summary text for transcript rows, normalized to present tense
    /// while running and past tense after completion.
    var transcriptDisplaySummary: String {
        if isDeniedWithoutOutput {
            return deniedDisplaySummary
        }

        switch name {
        case let name where CommandToolPresentation.isCommandToolName(name) && hasCommandDisplayBody:
            return "\(isComplete ? "Ran" : "Running") \(commandSummaryBody)"
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

    private var isDeniedWithoutOutput: Bool {
        isComplete && isError && output == nil && stderr == nil && summary.hasPrefix("Denied ")
    }

    private var deniedDisplaySummary: String {
        switch name {
        case let name where CommandToolPresentation.isCommandToolName(name) && hasCommandDisplayBody:
            return "Denied \(commandSummaryBody)"
        default:
            return summary
        }
    }

    private var commandSummaryBody: String {
        if let command = CommandToolPresentation.command(fromInput: input) {
            return CommandToolPresentation.summaryBody(command: command)
        }
        return CommandToolPresentation.summaryBody(from: summary)
    }

    private var hasCommandDisplayBody: Bool {
        CommandToolPresentation.command(fromInput: input) != nil || summary != name
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
