import SwiftUI

struct ToolGroupBlock: View {
    let tools: [ToolEntry]
    private let externalIsExpanded: Binding<Bool>?
    @State private var isExpanded: Bool

    init(tools: [ToolEntry], initiallyExpanded: Bool = false, isExpanded: Binding<Bool>? = nil) {
        self.tools = tools
        self.externalIsExpanded = isExpanded
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        let expansion = expansionBinding
        if tools.count <= 1, let only = tools.first {
            InlineToolRow(tool: only, isExpanded: expansion)
        } else {
            let toggleExpansion = {
                withAnimation(toolExpansionAnimation) {
                    expansion.wrappedValue.toggle()
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                TranscriptHeaderToggle(action: toggleExpansion) {
                    TranscriptDisclosureHeaderRow(
                        summary: summary,
                        isExpanded: expansion.wrappedValue,
                        phase: aggregateStatusPhase,
                        debounceStatus: true,
                        bottomPadding: expansion.wrappedValue ? 0 : transcriptToolRowVerticalPadding
                    )
                }

                if expansion.wrappedValue {
                    TranscriptNestedToolRows(tools: tools)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .toolAnimationOverride(value: tools)
            .toolAnimationOverride(value: expansion.wrappedValue)
        }
    }

    private var expansionBinding: Binding<Bool> {
        externalIsExpanded ?? $isExpanded
    }

    private var summary: String {
        let summaries = categorySummaries
        guard let first = summaries.first else {
            return ""
        }
        let tail = summaries.dropFirst().map(Self.lowercasedFirstLetter)
        return ([first] + tail).joined(separator: ", ")
    }

    static func lowercasedFirstLetter(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }
        return first.lowercased() + text.dropFirst()
    }

    private var aggregateIsError: Bool {
        tools.contains(where: \.isError)
    }

    private var aggregateIsComplete: Bool {
        !tools.isEmpty && tools.allSatisfy(\.isComplete)
    }

    private var aggregateStatusPhase: ToolStatusPhase {
        ToolStatusPhase(isError: aggregateIsError, isComplete: aggregateIsComplete)
    }

    private var categorySummaries: [String] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for tool in tools {
            let key = Self.toolCategoryKey(for: tool.name)
            if counts[key] == nil {
                order.append(key)
            }
            counts[key, default: 0] += 1
        }
        return order.map { key in
            Self.toolCategorySummary(
                for: key,
                count: counts[key] ?? 0,
                isComplete: aggregateIsComplete
            )
        }
    }

    static func toolCategoryKey(for toolName: String) -> String {
        switch toolName {
        case "Read":
            return "Read"
        case "Grep", "Glob":
            return "Search"
        case "WebFetch":
            return "WebFetch"
        case "WebSearch":
            return "WebSearch"
        case "ToolSearch":
            return "ToolSearch"
        default:
            return toolName.hasPrefix("mcp__") ? "MCP" : toolName
        }
    }

    static func toolCategorySummary(for categoryKey: String, count: Int, isComplete: Bool = false) -> String {
        switch categoryKey {
        case "Read":
            return count == 1
                ? (isComplete ? "Read 1 file" : "Reading 1 file")
                : (isComplete ? "Read \(count) files" : "Reading \(count) files")
        case "Search":
            return count == 1
                ? (isComplete ? "Searched for 1 pattern" : "Searching for 1 pattern")
                : (isComplete ? "Searched for \(count) patterns" : "Searching for \(count) patterns")
        case "ToolSearch":
            return count == 1
                ? (isComplete ? "Searched for 1 tool" : "Searching for 1 tool")
                : (isComplete ? "Searched for \(count) tools" : "Searching for \(count) tools")
        case "WebFetch":
            return isComplete ? "Fetched from the web" : "Fetching from the web"
        case "WebSearch":
            return isComplete ? "Searched the web" : "Searching the web"
        case "MCP":
            return count == 1
                ? (isComplete ? "Ran 1 MCP call" : "Running 1 MCP call")
                : (isComplete ? "Ran \(count) MCP calls" : "Running \(count) MCP calls")
        default:
            return count == 1 ? categoryKey : "\(categoryKey) x\(count)"
        }
    }
}
