import Foundation

extension DefaultAgentsManager {
    func handleDeferredToolRequestFromHookServer(_ deferredToolRequest: ClaudeDeferredToolRequest) async {
        let conversationId = deferredToolRequest.conversationId
        guard let managedBuffer = eventBuffers[conversationId] else {
            return
        }
        guard managedBuffer.allowsReplay else {
            return
        }
        guard !closingConversationIds.contains(conversationId) else {
            return
        }
        guard usesAgentCLIKitRuntime || processes[conversationId]?.processIdentifier != nil else {
            return
        }
        let key = ClaudeToolApprovalKey(
            sessionId: deferredToolRequest.request.sessionId,
            toolUseId: deferredToolRequest.request.toolUseId
        )
        // Hook notifications are delayed so preceding tool_use rows can render
        // first. A batch decision may already have answered this sibling hook
        // before its delayed notification arrives.
        guard !managedBuffer.resolvedLiveToolApprovals.contains(key) else {
            return
        }
        guard deferredToolRequest.launchToken == nil || hookTokens[conversationId] == deferredToolRequest.launchToken else {
            return
        }
        let generation = managedBuffer.generation
        guard managedBuffer.acceptsLiveEvents || managedBuffer.hasDeferredToolStop else {
            return
        }
        if managedBuffer.hasDeferredToolStop {
            await handleStreamEvent(
                .toolApprovalRequested(deferredToolRequest.request),
                conversationId: conversationId,
                generation: generation,
                providerId: "claude",
                allowAfterDeferredStop: true
            )
            return
        }

        eventBuffers[conversationId]?.pendingLiveToolApprovals += 1

        await handleStreamEvent(
            .toolApprovalRequested(deferredToolRequest.request),
            conversationId: conversationId,
            generation: generation,
            providerId: "claude",
            allowAfterDeferredStop: true
        )
    }

    func stopDeferredRuntimeIfCurrent(
        conversationId: String,
        generation: UUID,
        pid: Int32,
        sessionId: String? = nil,
        toolUseId: String? = nil
    ) async {
        guard let managedBuffer = eventBuffers[conversationId] else {
            return
        }
        guard managedBuffer.generation == generation else {
            return
        }
        guard processes[conversationId]?.processIdentifier == pid else {
            return
        }

        suppressExitStatus(for: conversationId, pid: pid)
        if sessionId != nil || toolUseId != nil {
            eventBuffers[conversationId]?.deferredToolStopSessionId = sessionId
            eventBuffers[conversationId]?.deferredToolStopToolUseId = toolUseId
        }
        try? await Task.sleep(for: .milliseconds(150))
        let latestDeferredStop = eventBuffers[conversationId]
        if let sessionId = latestDeferredStop?.deferredToolStopSessionId,
           let toolUseId = latestDeferredStop?.deferredToolStopToolUseId,
           let cwd = processes[conversationId]?.currentDirectoryURL?.path {
            await waitForDeferredToolPersistence(
                sessionId: sessionId,
                toolUseId: toolUseId,
                cwd: cwd
            )
        }
        await teardownProcess(
            for: conversationId,
            awaitExit: true,
            preserveBufferForDurabilityGrace: true,
            graceSeconds: 1.0
        )
        eventBuffers[conversationId]?.allowsReplay = true
        if status(for: conversationId) != .waitingForUser {
            updateStatus(.stopped, for: conversationId)
        }
    }

    private func waitForDeferredToolPersistence(sessionId: String, toolUseId: String, cwd: String) async {
        let path = deferredSessionFilePath(sessionId: sessionId, cwd: cwd)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if deferredSessionFile(path: path, containsToolUseId: toolUseId) {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func deferredSessionFilePath(sessionId: String, cwd: String) -> String {
        let canonicalCwd = CanonicalPath.normalize(cwd)
        let encodedDirectory = ClaudePathEncoding.projectDirectoryName(forCanonicalCwd: canonicalCwd)
        return NSHomeDirectory() + "/.claude/projects/\(encodedDirectory)/\(sessionId).jsonl"
    }

    private func deferredSessionFile(path: String, containsToolUseId toolUseId: String) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return false
        }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let readSize: UInt64 = 128 * 1024
        try? handle.seek(toOffset: size > readSize ? size - readSize : 0)
        guard let data = try? handle.readToEnd(),
              let tail = String(data: data, encoding: .utf8) else {
            return false
        }
        return tail.contains(toolUseId)
    }
}
