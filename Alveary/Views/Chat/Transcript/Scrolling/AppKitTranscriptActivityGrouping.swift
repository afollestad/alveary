import Foundation

enum AppKitTranscriptActivityChild: Equatable {
    case tool(rowID: String, expansionID: String?, tool: ToolEntry)
    case subAgent(rowID: String, expansionID: String?, agent: SubAgentEntry)

    var id: String {
        switch self {
        case .tool(_, _, let tool):
            "tool-\(tool.id)"
        case .subAgent(_, _, let agent):
            "subagent-\(agent.id)"
        }
    }

    var rowID: String {
        switch self {
        case .tool(let rowID, _, _), .subAgent(let rowID, _, _):
            rowID
        }
    }

    var expansionID: String? {
        switch self {
        case .tool(_, let expansionID, _), .subAgent(_, let expansionID, _):
            expansionID
        }
    }

    var isComplete: Bool {
        switch self {
        case .tool(_, _, let tool):
            tool.isComplete
        case .subAgent(_, _, let agent):
            agent.isComplete
        }
    }

    var isError: Bool {
        switch self {
        case .tool(_, _, let tool):
            tool.isError
        case .subAgent(_, _, let agent):
            agent.appKitHasFailedTool
        }
    }

    var canExpand: Bool {
        switch self {
        case .tool(_, _, let tool):
            tool.appKitRendersDetails
        case .subAgent(_, _, let agent):
            agent.appKitRendersDetails
        }
    }
}

enum AppKitTranscriptVisualRow: Equatable {
    case item(ChatItem)
    case activityGroup(id: String, children: [AppKitTranscriptActivityChild])

    var id: String {
        switch self {
        case .item(let item):
            item.id
        case .activityGroup(let id, _):
            id
        }
    }
}

enum AppKitTranscriptActivityGrouping {
    static func activityGroupID(firstRawItemID: String) -> String {
        "activity-\(firstRawItemID)"
    }

    static func visualRows(for items: [ChatItem]) -> [AppKitTranscriptVisualRow] {
        var visualRows: [AppKitTranscriptVisualRow] = []
        var pendingRun: [ChatItem] = []
        let rawItemIDs = Set(items.map(\.id))
        var usedVisualIDs: Set<String> = []

        func flushRun() {
            guard !pendingRun.isEmpty else {
                return
            }
            let children = pendingRun.flatMap(activityChildren(for:))
            if children.count > 1, let firstID = pendingRun.first?.id {
                let id = uniqueActivityGroupID(firstRawItemID: firstID, occupiedIDs: rawItemIDs.union(usedVisualIDs))
                visualRows.append(.activityGroup(id: id, children: children))
                usedVisualIDs.insert(id)
            } else {
                for item in pendingRun {
                    visualRows.append(.item(item))
                    usedVisualIDs.insert(item.id)
                }
            }
            pendingRun = []
        }

        for item in items {
            if isActivityItem(item) {
                pendingRun.append(item)
            } else {
                flushRun()
                visualRows.append(.item(item))
            }
        }
        flushRun()
        return visualRows
    }

    private static func uniqueActivityGroupID(firstRawItemID: String, occupiedIDs: Set<String>) -> String {
        let baseID = activityGroupID(firstRawItemID: firstRawItemID)
        guard occupiedIDs.contains(baseID) else {
            return baseID
        }

        var suffix = 2
        var id = "activity-\(suffix)-\(firstRawItemID)"
        while occupiedIDs.contains(id) {
            suffix += 1
            id = "activity-\(suffix)-\(firstRawItemID)"
        }
        return id
    }

    static func expandableRowIDs(for items: [ChatItem]) -> Set<String> {
        Set(visualRows(for: items).flatMap { row in
            switch row {
            case .item(let item):
                return item.appKitExpandableRowId.map { [$0] } ?? []
            case .activityGroup(let id, let children):
                return [id] + children.filter(\.canExpand).compactMap(\.expansionID)
            }
        })
    }

    static func migratedExpandedRowIDs(_ expandedRowIDs: Set<String>, for items: [ChatItem]) -> Set<String> {
        var migrated: Set<String> = []
        for row in visualRows(for: items) {
            switch row {
            case .item(let item):
                if let expansionID = item.appKitExpandableRowId, expandedRowIDs.contains(expansionID) {
                    migrated.insert(expansionID)
                }
            case .activityGroup(let id, let children):
                let childExpansionIDs = Set(children.compactMap(\.expansionID))
                let childRowIDs = Set(children.map(\.rowID))
                if expandedRowIDs.contains(id) ||
                    !expandedRowIDs.isDisjoint(with: childExpansionIDs) ||
                    !expandedRowIDs.isDisjoint(with: childRowIDs) {
                    migrated.insert(id)
                }
                migrated.formUnion(expandedRowIDs.intersection(childExpansionIDs))
            }
        }
        return migrated
    }

    static func rowIDAliases(for items: [ChatItem]) -> [String: String] {
        var aliases: [String: String] = [:]
        for row in visualRows(for: items) {
            guard case .activityGroup(let id, let children) = row else {
                continue
            }
            for child in children {
                aliases[child.rowID] = id
            }
        }
        return aliases
    }

    private static func isActivityItem(_ item: ChatItem) -> Bool {
        switch item {
        case .toolGroup(_, let tools):
            return !tools.isEmpty
        case .standaloneTool(_, let tool):
            return !tool.appKitRendersExitPlanModeFollowUpPreview
        case .subAgentBlock(_, let agents):
            return !agents.isEmpty
        case .userMessage,
             .assistantMessage,
             .taskListBlock,
             .promptBlock,
             .toolApproval,
             .toolApprovalBatch,
             .centeredNote,
             .error:
            return false
        }
    }

    private static func activityChildren(for item: ChatItem) -> [AppKitTranscriptActivityChild] {
        switch item {
        case .toolGroup(let id, let tools):
            let expansionID = tools.count == 1 ? id : nil
            return tools.map { .tool(rowID: id, expansionID: expansionID, tool: $0) }
        case .standaloneTool(let id, let tool):
            return [.tool(rowID: id, expansionID: id, tool: tool)]
        case .subAgentBlock(let id, let agents):
            let expansionID = agents.count == 1 ? id : nil
            return agents.map { .subAgent(rowID: id, expansionID: expansionID, agent: $0) }
        case .userMessage,
             .assistantMessage,
             .taskListBlock,
             .promptBlock,
             .toolApproval,
             .toolApprovalBatch,
             .centeredNote,
             .error:
            return []
        }
    }
}
