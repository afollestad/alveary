import Foundation

/// Leading glyph contract for AppKit tool headers. Keep this UI-neutral so the
/// row factory can decide expansion state while header views only render it.
enum TranscriptToolLeadingIconKind: Equatable {
    case disclosure(isExpanded: Bool)
    case bash
    case symbol(systemName: String)
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

    /// User-facing summary text for transcript rows, normalized to present tense
    /// while running and past tense after completion.
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
