import Foundation

extension ChatItemGrouper {
    static func hostToolWidgetItemID(toolId: String) -> String {
        "host-tool-\(toolId)"
    }

    /// Routes a catalog-matched host MCP tool call to a first-class widget block.
    ///
    /// Returns `false` for nested calls, unknown tools, and payloads the feature
    /// cannot render, so those keep the generic tool row.
    func handleHostToolWidgetCallIfNeeded(_ event: ConversationEventRecord) -> Bool {
        guard event.parentToolUseId == nil,
              let toolName = event.toolName,
              let descriptor = HostToolTranscriptCatalog.descriptor(forToolName: toolName) else {
            return false
        }

        let toolId = event.toolId ?? event.id
        // A result can persist ahead of its call; consume the cached one so the widget
        // renders complete immediately, and restore it if this feature declines the call.
        let cachedResult = pendingToolResultEventsByToolId.removeValue(forKey: toolId)
        guard let entry = makeHostToolWidgetEntry(
            toolId: toolId,
            toolName: toolName,
            descriptor: descriptor,
            input: event.toolInput,
            result: cachedResult
        ) else {
            if let cachedResult {
                pendingToolResultEventsByToolId[toolId] = cachedResult
            }
            return false
        }

        flushGroup()
        flushSubAgents()
        hostToolWidgetToolIds.insert(toolId)
        hostToolWidgetInputsByToolId[toolId] = event.toolInput
        replaceOrAppendTranscriptItem(
            .hostToolWidget(id: Self.hostToolWidgetItemID(toolId: toolId), entry: entry)
        )
        return true
    }

    /// Patches a widget in place when its own result arrives. Unlike prompt and
    /// task-list tools, a widget's payload lives in the result, so it is never swallowed.
    func handleHostToolWidgetResult(toolId: String, event: ConversationEventRecord) {
        let itemID = Self.hostToolWidgetItemID(toolId: toolId)
        guard let index = items.lastIndex(where: { $0.id == itemID }),
              let existing = items[index].hostToolWidgetEntry,
              let descriptor = HostToolTranscriptCatalog.descriptor(forToolName: existing.toolName) else {
            return
        }
        guard let entry = makeHostToolWidgetEntry(
            toolId: toolId,
            toolName: existing.toolName,
            descriptor: descriptor,
            input: hostToolWidgetInputsByToolId[toolId] ?? event.toolInput,
            result: event
        ) else {
            return
        }
        // An immediate action's keyless marker can land before this result; the rebuilt
        // entry starts without it, so carry the already-attached outcome forward.
        items[index] = .hostToolWidget(
            id: itemID,
            entry: entry.withOutcome(
                existing.outcome,
                definitionID: existing.outcomeDefinitionID,
                title: existing.outcomeTitle
            )
        )
    }

    /// Applies a durable outcome marker, caching it when its widget has not rendered yet.
    ///
    /// An exact tool retry returns the same proposal, so several widgets can share one
    /// correlation key; every one of them describes that proposal and must resolve.
    func handleHostToolOutcomeMarker(_ event: ConversationEventRecord) {
        guard let key = event.toolId,
              let content = event.content,
              let outcome = HostToolWidgetOutcomeMarker.outcome(fromContent: content) else {
            return
        }
        let pending = PendingHostToolOutcome(
            outcome: outcome,
            definitionID: HostToolWidgetOutcomeMarker.definitionID(fromContent: content),
            title: HostToolWidgetOutcomeMarker.title(fromContent: content)
        )
        // Cache regardless: a later replay of the same call must resolve too.
        pendingHostToolOutcomesByKey[key] = pending
        var didMatchKey = false
        for index in items.indices {
            guard let entry = items[index].hostToolWidgetEntry, entry.outcomeKey == key else {
                continue
            }
            didMatchKey = true
            applyPendingHostToolOutcome(pending, at: index)
        }
        guard !didMatchKey else {
            return
        }
        // Providers that surface only a host tool's text fallback give the widget no
        // correlation key. Immediate actions write their marker between the call and its
        // result, so pair those with marker-awaiting widgets by the definition they name
        // — an immediate marker always names one, and requiring the match keeps a
        // proposal's resolution from adopting an unrelated running action. Otherwise the
        // grouper is per-conversation and a conversation holds one proposal at a time,
        // so the newest unresolved proposal widget is that proposal.
        //
        // Every keyless pairing stays inside the feature that wrote the marker: scheduling and
        // pull-request reviews both open confirmations, and adopting the other's card would
        // report a decision the user never made.
        let index = items.firstIndex { item in
            guard let entry = item.hostToolWidgetEntry,
                  Self.marker(event, belongsTo: entry),
                  entry.isProposalAwaitingOutcomeMarker else {
                return false
            }
            return pending.definitionID != nil && entry.resolvedScheduledTaskID == pending.definitionID
        } ?? items.lastIndex { item in
            guard let entry = item.hostToolWidgetEntry, Self.marker(event, belongsTo: entry) else {
                return false
            }
            return entry.isUnresolvedProposal || entry.isUnresolvedReviewProposal
        }
        guard let index else {
            return
        }
        applyPendingHostToolOutcome(pending, at: index)
    }
}

private extension ChatItemGrouper {
    /// Whether a marker and a widget come from the same host tool. The marker records the
    /// qualified name while a widget carries whatever its provider reported, so both resolve
    /// through the descriptor. A marker without a tool name predates this scoping and matches
    /// anything, as it did before.
    static func marker(_ event: ConversationEventRecord, belongsTo entry: HostToolWidgetEntry) -> Bool {
        guard let markerToolName = event.toolName,
              let descriptor = HostToolTranscriptCatalog.descriptor(forToolName: markerToolName) else {
            return true
        }
        return descriptor.matches(toolName: entry.toolName)
    }

    func applyPendingHostToolOutcome(_ pending: PendingHostToolOutcome, at index: Int) {
        guard let entry = items[index].hostToolWidgetEntry else {
            return
        }
        items[index] = .hostToolWidget(
            id: items[index].id,
            entry: entry.withOutcome(
                pending.outcome,
                definitionID: pending.definitionID,
                title: pending.title
            )
        )
    }

    func makeHostToolWidgetEntry(
        toolId: String,
        toolName: String,
        descriptor: HostToolTranscriptDescriptor,
        input: String?,
        result: ConversationEventRecord?
    ) -> HostToolWidgetEntry? {
        let output = result.flatMap { $0.toolOutput ?? $0.content }
        let isError = result?.isError ?? false
        guard let content = descriptor.makeContent(input, output, isError) else {
            return nil
        }
        let outcomeKey = descriptor.outcomeKey(output)
        let pending = outcomeKey.flatMap { pendingHostToolOutcomesByKey[$0] }
        return HostToolWidgetEntry(
            id: toolId,
            toolName: toolName,
            content: content,
            isComplete: result != nil,
            isInterrupted: result?.toolOutputInterrupted ?? false,
            isError: isError,
            outcomeKey: outcomeKey,
            outcome: pending?.outcome,
            outcomeDefinitionID: pending?.definitionID,
            outcomeTitle: pending?.title
        )
    }
}

/// Cached outcome-marker payload awaiting the widget it resolves.
struct PendingHostToolOutcome: Equatable {
    let outcome: HostToolWidgetOutcome
    let definitionID: String?
    let title: String?
}

/// Encoding for the feature-neutral `host_tool_outcome` marker payload.
enum HostToolWidgetOutcomeMarker {
    static func content(
        for outcome: HostToolWidgetOutcome,
        definitionID: String? = nil,
        title: String? = nil
    ) -> String {
        var payload: [String: String] = ["status": outcome.rawValue]
        if let definitionID {
            payload["definition_id"] = definitionID
        }
        if let title {
            payload["title"] = title
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let encoded = String(data: data, encoding: .utf8) else {
            return "{\"status\":\"\(outcome.rawValue)\"}"
        }
        return encoded
    }

    static func outcome(fromContent content: String) -> HostToolWidgetOutcome? {
        decoded(content)?["status"].flatMap(HostToolWidgetOutcome.init(rawValue:))
    }

    /// Scheduled task the resolution produced or targeted, when the feature recorded one.
    static func definitionID(fromContent content: String) -> String? {
        decoded(content)?["definition_id"]
    }

    /// Target task name, so a widget can name the task when the tool result never
    /// carried one (state-change requests, plain-text fallbacks).
    static func title(fromContent content: String) -> String? {
        decoded(content)?["title"]
    }

    private static func decoded(_ content: String) -> [String: String]? {
        guard let data = content.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }
}
