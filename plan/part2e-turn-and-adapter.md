# Part 2e: Turn Lifecycle and ClaudeAdapter

Turn state lifecycle, event JSON schemas, sub-agent event flow, ClaudeAdapter implementation. Continues from Parts 2c/2d.

## Turn State and Event Lifecycle

Claude emits both session-scoped metadata and per-turn events. `system/init` belongs to the session lifecycle, not to an individual turn, so turn handling must not depend on seeing a fresh init event before every result.

Typical session + turn flow (verified by testing Claude's `--output-format stream-json`):

```
session: system/init → session metadata (emitted on startup, and may recur later)
turn 1: assistant    → content: [tool_use] or [text]
turn 1: user         → content: [tool_result]             (if tool was used)
turn 1: assistant    → content: [tool_use] or [text]     (repeats for multi-tool turns)
turn 1: result       → turn completion signal
turn 2+: assistant / user(tool_result) / result repeat without requiring a new init
```

### Event JSON Schemas (Verified by Testing)

**`system/init`** -- emitted when the interactive session initializes (and may recur later when Claude re-announces session metadata):
```json
{
  "type": "system",
  "subtype": "init",
  "session_id": "b9de25c6-3f0f-4bc5-860f-4e8666a9c5da",
  "model": "claude-opus-4-6[1m]",
  "permissionMode": "default",
  "tools": ["Bash", "Edit", "Read", "Write", "Glob", "Grep", ...],
  "mcp_servers": [{"name": "...", "status": "connected"}],
  "cwd": "/path/to/project",
  "slash_commands": ["commit", "review", ...],
  "apiKeySource": "/login managed key",
  "claude_code_version": "2.1.92",
  "output_style": "default",
  "agents": ["general-purpose", "Explore", "Plan", ...],
  "skills": ["commit", "review", ...],
  "plugins": [{"name": "...", "path": "...", "source": "..."}],
  "uuid": "f954d5a6-...",
  "fast_mode_state": "off"
}
```

**`assistant`** -- agent response with content blocks (text or tool_use):
```json
{
  "type": "assistant",
  "message": {
    "id": "msg_01...",
    "role": "assistant",
    "model": "claude-opus-4-6",
    "content": [
      {"type": "thinking", "thinking": "Let me analyze...", "signature": "EoMD..."},
      {"type": "text", "text": "Here's what I found..."}
    ],
    "stop_reason": null,
    "usage": {"input_tokens": 3, "output_tokens": 15, "cache_read_input_tokens": 11271}
  },
  "parent_tool_use_id": null,
  "session_id": "b9de25c6-...",
  "uuid": "c74a2b5f-..."
}
```

**`assistant` with tool_use** -- agent requesting to use a tool:
```json
{
  "type": "assistant",
  "message": {
    "role": "assistant",
    "content": [
      {
        "type": "tool_use",
        "id": "toolu_01ESJ...",
        "name": "Read",
        "input": {"file_path": "/path/to/file.swift", "limit": 50},
        "caller": {"type": "direct"}
      }
    ],
    "stop_reason": null
  },
  "parent_tool_use_id": null,
  "session_id": "b9de25c6-...",
  "uuid": "41652bf6-..."
}
```

**`user` (tool_result)** -- tool execution result (emitted by Claude after it runs the tool):
```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_01ESJ...",
        "content": "1\t# Skep App Research\n2\t\n3\tReference architecture...",
        "is_error": false
      }
    ]
  },
  "parent_tool_use_id": null,
  "session_id": "b9de25c6-...",
  "uuid": "d4e5074e-...",
  "timestamp": "2026-04-05T04:37:09.288Z",
  "tool_use_result": {
    "stdout": "1\t# Skep App Research\n...",
    "stderr": "",
    "interrupted": false,
    "isImage": false,
    "noOutputExpected": false
  }
}
```

The `tool_use_result` object provides structured metadata about the tool execution beyond the `content` string. The `stdout`/`stderr` split and `interrupted` flag are useful for rendering tool results in the UI (e.g. showing stderr in a different style, indicating if the user interrupted the tool).

**`user` (tool_result with error)** -- when a tool fails, `is_error` is true and `content` contains the error message:
```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_01ESJ...",
        "is_error": true,
        "content": "File does not exist. Note: your current working directory is /Users/you/project."
      }
    ]
  }
}
```

Note: a tool error does NOT make the turn's `result.is_error` true -- Claude handles tool errors gracefully and continues the conversation. `result.is_error` only indicates a fatal turn-level failure.

**`result`** -- **turn completion signal** (the process remains alive for the next turn):
```json
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "stop_reason": "end_turn",
  "num_turns": 2,
  "result": "The text of the final assistant message",
  "duration_ms": 6773,
  "duration_api_ms": 5263,
  "total_cost_usd": 0.0697,
  "session_id": "b9de25c6-...",
  "usage": {
    "input_tokens": 3,
    "output_tokens": 5,
    "cache_read_input_tokens": 11271,
    "cache_creation_input_tokens": 10229,
    "server_tool_use": {"web_search_requests": 0, "web_fetch_requests": 0},
    "service_tier": "standard"
  },
  "modelUsage": {
    "claude-opus-4-6[1m]": {
      "inputTokens": 3,
      "outputTokens": 5,
      "cacheReadInputTokens": 11271,
      "cacheCreationInputTokens": 10229,
      "costUSD": 0.0697,
      "contextWindow": 1000000,
      "maxOutputTokens": 64000
    }
  },
  "permission_denials": [],
  "terminal_reason": "completed",
  "fast_mode_state": "off",
  "uuid": "31542f13-..."
}
```

Key fields on the result event:
- `stop_reason: "end_turn"` -- normal completion. The process is now waiting for the next stdin message.
- `result` -- the text content of the final assistant message
- `num_turns` -- how many tool-use cycles happened in this turn
- `total_cost_usd` -- cost for this turn
- `duration_ms` -- wall clock time; `duration_api_ms` -- API time only
- `is_error` -- whether the turn failed
- `modelUsage` -- per-model token breakdown with cost, context window, and max output tokens
- `permission_denials` -- list of permissions that were denied during the turn
- `terminal_reason` -- why the turn ended (e.g. `"completed"`)
- `fast_mode_state` -- current fast mode state (`"off"`, `"on"`, etc.)
- `uuid` -- unique identifier for this event

**`stream_event`** -- partial message chunks (only with `--include-partial-messages`):

These wrap the Messages API streaming protocol. The sequence for a text response is:

```
stream_event (message_start)       → message metadata (id, model, role)
stream_event (content_block_start) → new content block (index 0, type "text")
stream_event (content_block_delta) → text chunk: "Opt"
stream_event (content_block_delta) → text chunk: "ionals unwrap,\n..."
stream_event (content_block_delta) → text chunk: "the compiler knows."
stream_event (content_block_stop)  → block complete
stream_event (message_delta)       → stop_reason, final usage
stream_event (message_stop)        → message complete
assistant                          → full message (same data, already aggregated)
```

Example `content_block_delta` event:
```json
{
  "type": "stream_event",
  "event": {
    "type": "content_block_delta",
    "index": 0,
    "delta": {"type": "text_delta", "text": "ionals unwrap,\nprotocols shape the design"}
  },
  "session_id": "67aa1eff-...",
  "parent_tool_use_id": null,
  "uuid": "dbef69e7-..."
}
```

**How the app uses `stream_event`**: the adapter turns `content_block_delta` text chunks into transient `.messageChunk` events so the chat UI can render text as it arrives (typewriter effect). When the full `assistant` event arrives, it replaces the accumulated text (source of truth). If the app doesn't need token-by-token streaming, it can ignore `stream_event` lines entirely and rely on the complete `assistant` events.

**`caller` field on `tool_use` content blocks**: indicates how the tool was invoked. `{"type": "direct"}` means the agent called the tool directly. Other values (e.g. `{"type": "agent", "agent": "Explore"}`) indicate the tool was called by a sub-agent. The grouping key for sub-agent event routing is still `parent_tool_use_id`; `caller` is preserved as extra metadata for labeling/debugging, not as the primary grouping key.

### Sub-Agent Event Flow

When Claude Code spawns a sub-agent (e.g. "Explore", "Plan"), the stream produces a nested sequence identified by `parent_tool_use_id`. Every JSON line in the stream includes this field -- `null` for top-level events, or set to the `id` of the `Agent` tool_use that spawned the sub-agent.

**Event sequence (verified by testing):**

```
main  assistant  { tool_use: name="Agent", id="toolu_ABC" }     parent_tool_use_id: null
ctrl  system     { subtype: "task_started", task_id, tool_use_id="toolu_ABC" }
sub   user       { prompt text forwarded to sub-agent }          parent_tool_use_id: "toolu_ABC"
ctrl  system     { subtype: "task_progress", description, last_tool_name, usage }   ← periodic
sub     assistant  { thinking / text / tool_use }                parent_tool_use_id: "toolu_ABC"
sub     user       { tool_result for sub-agent's inner tool }    parent_tool_use_id: "toolu_ABC"
sub     assistant  { text (sub-agent's final response) }         parent_tool_use_id: "toolu_ABC"
ctrl  system     { subtype: "task_notification", status: "completed", usage }
main  user       { tool_result: tool_use_id="toolu_ABC" }        parent_tool_use_id: null
main  assistant  { text (main agent continues) }                 parent_tool_use_id: null
```

Three `system` event subtypes are emitted for sub-agent lifecycle (verified CLI v2.1.92):

**`system/task_started`** — emitted when a sub-agent begins:
```json
{
  "type": "system",
  "subtype": "task_started",
  "task_id": "ac263469150f5236d",
  "tool_use_id": "toolu_01Dink275Kr988Uk3z5gy8ZW",
  "description": "Find DiffParser references",
  "task_type": "local_agent",
  "prompt": "Search the repository..."
}
```

**`system/task_progress`** — emitted periodically during sub-agent execution:
```json
{
  "type": "system",
  "subtype": "task_progress",
  "task_id": "ac263469150f5236d",
  "tool_use_id": "toolu_01Dink275Kr988Uk3z5gy8ZW",
  "description": "Searching for DiffParser",
  "usage": {"total_tokens": 14238, "tool_uses": 1, "duration_ms": 1165},
  "last_tool_name": "Grep"
}
```

**`system/task_notification`** — emitted when the sub-agent completes:
```json
{
  "type": "system",
  "subtype": "task_notification",
  "task_id": "ac263469150f5236d",
  "tool_use_id": "toolu_01Dink275Kr988Uk3z5gy8ZW",
  "status": "completed",
  "summary": "Find DiffParser references",
  "usage": {"total_tokens": 17830, "tool_uses": 1, "duration_ms": 8157}
}
```

The `task_progress` event is especially useful for the live sub-agent UI — it provides a dynamic `description` (live status text like "Searching for DiffParser"), `last_tool_name`, and a running `tool_uses` count without requiring the app to track each inner `tool_call` event individually. The app uses both: `task_progress` for the summary line (status · tool name · tool count · elapsed time), and individual inner events for the expandable tool list.

Sub-agents are **not** opaque -- their full inner loop is streamed as individual events, each tagged with `parent_tool_use_id`. The app sees the sub-agent's thinking, tool calls, tool results, and text responses in real-time.

**`assistant` with Agent tool_use** -- main agent spawning a sub-agent:
```json
{
  "type": "assistant",
  "message": {
    "role": "assistant",
    "content": [
      {
        "type": "tool_use",
        "id": "toolu_01ABC...",
        "name": "Agent",
        "input": {
          "prompt": "Search for all usages of the AuthManager class",
          "description": "Find AuthManager usages",
          "subagent_type": "Explore"
        },
        "caller": {"type": "direct"}
      }
    ]
  },
  "parent_tool_use_id": null,
  "session_id": "b9de25c6-..."
}
```

**Sub-agent inner events** -- all carry `parent_tool_use_id` pointing to the Agent tool:
```json
{
  "type": "assistant",
  "message": {
    "role": "assistant",
    "content": [
      {
        "type": "tool_use",
        "id": "toolu_01DEF...",
        "name": "Grep",
        "input": {"pattern": "AuthManager", "type": "swift"},
        "caller": {"type": "agent", "agent": "Explore"}
      }
    ]
  },
  "parent_tool_use_id": "toolu_01ABC...",
  "session_id": "b9de25c6-..."
}
```

**Agent tool_result** -- sub-agent finished, result returned to main agent:
```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_01ABC...",
        "content": "Found 12 usages of AuthManager across 5 files...",
        "is_error": false
      }
    ]
  },
  "parent_tool_use_id": null,
  "session_id": "b9de25c6-..."
}
```

Multiple sub-agents can run in parallel (e.g. "4 agents finished" in the CLI). Each has a distinct `parent_tool_use_id` pointing to its own `Agent` tool_use. The app groups events by this ID to show parallel sub-agent blocks.

**Note**: The tool was renamed from `"Task"` to `"Agent"` in Claude Code v2.1.63. The adapter only needs to recognize `"Agent"` — no backward compatibility with `"Task"` is needed.

**`tool_use_result` on `user` (tool_result) events**: provides structured metadata beyond the `content` string:
- `stdout` / `stderr` -- separated output streams. The app can render stderr in a muted or warning style to distinguish it from normal output.
- `interrupted` -- whether the user (or the agent) interrupted the tool mid-execution. The app can show an "interrupted" badge on the tool result.
- `isImage` -- whether the tool result is an image (e.g. a screenshot). The app can render it inline as an image rather than text.
- `noOutputExpected` -- whether an empty result is expected. The UI can suppress noisy "No output" placeholders for tools whose success case is silent.

The adapter preserves this metadata on `.toolResult` events and SwiftData records so the expanded tool UI can distinguish stdout from stderr, show interrupted badges, and render image results after navigation/rebuild.

### ClaudeAdapter Implementation

The `ClaudeAdapter` conforms to `AgentAdapter` and lives in its own module. In v1 it has no extra dependencies, so `DefaultAgentsManager.resolveAdapter()` can instantiate it directly; a future multi-provider build can swap this for an injected adapter factory if an adapter needs collaborators. `AgentsManager` holds a reference to it and delegates decoding and message sending:

```swift
final class ClaudeAdapter: AgentAdapter, Sendable {  // Skep/Services/Agent/ClaudeAdapter.swift
    let supportsBidirectionalStreaming = true
    let supportsMidTurnSteering = true

    func sessionFilePath(sessionId: String, cwd: String) -> String? {
        let canonicalCwd = URL(fileURLWithPath: cwd)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        // Do NOT implement this as simple slash replacement. Validation showed Claude's
        // project-directory encoding normalizes additional punctuation too, so keep the
        // transform behind a Claude-specific helper.
        let encoded = ClaudePathEncoding.projectDirectoryName(forCanonicalCwd: canonicalCwd)
        return NSHomeDirectory() + "/.claude/projects/\(encoded)/\(sessionId).jsonl"
    }

    func canResumeSession(sessionId: String, cwd: String) -> Bool {
        guard let path = sessionFilePath(sessionId: sessionId, cwd: cwd) else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
    }

    func sessionLaunch(sessionId: String, cwd: String, isResuming: Bool, forkSession: Bool) -> SessionLaunchDecision {
        if isResuming && canResumeSession(sessionId: sessionId, cwd: cwd) {
            var args = ["--resume", sessionId]
            if forkSession {
                args.append("--fork-session")
            }
            return SessionLaunchDecision(args: args, continuity: .preserved)
        }
        return SessionLaunchDecision(
            args: ["--session-id", sessionId],
            continuity: isResuming ? .restartedFresh : .preserved
        )
    }

    func buildArgs(config: AgentConfig) -> [String] {
        var args = ["-p", "--output-format", "stream-json", "--input-format", "stream-json",
                    "--verbose", "--include-partial-messages"]
        // Note: session isolation args are appended by `ClaudeAdapter.sessionLaunch()`
        // after `AgentsManager` fetches the persisted session ID from SessionManager.
        // Note: config.initialPrompt is NOT appended as a CLI arg. For bidirectional
        // providers (like Claude), the initial prompt is sent via stdin JSON after spawn
        // using sendMessage(). The CLI arg approach (bare trailing arg via
        // ProviderDefinition.initialPromptFlag) is reserved for future single-turn
        // providers that need the prompt on the command line.
        if let permissionMode = config.permissionMode {
            args += ["--permission-mode", permissionMode]
        }
        if let model = config.model {
            args += ["--model", model]
        }
        if let effort = config.effort {
            args += ["--effort", effort]
        }
        return args
    }

    func envOverrides(config: AgentConfig) -> [String: String] { [:] }

    func sendMessage(_ message: String, to process: Process) throws {
        guard let stdin = process.standardInput as? Pipe else {
            throw AgentError.stdinClosed
        }
        let event: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [["type": "text", "text": message]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: event)
        guard let json = String(data: data, encoding: .utf8) else {
            throw AgentError.spawnFailed("Failed to encode message as UTF-8")
        }
        // IMPORTANT: Use the throwing write(contentsOf:) — NOT the void write(_:).
        // The void variant raises an uncatchable NSFileHandleOperationException
        // ("Broken pipe") if the process has exited. The throwing variant converts
        // it to a Swift Error (NSCocoaErrorDomain Code 512, EPIPE). Validated.
        try stdin.fileHandleForWriting.write(contentsOf: Data((json + "\n").utf8))
    }

    func decode(_ json: [String: Any]) -> [ConversationEvent] {
        guard let type = json["type"] as? String else { return [] }
        let parentToolUseId = json["parent_tool_use_id"] as? String  // nil for top-level, set for sub-agent events
        func malformed(_ detail: String) -> [ConversationEvent] {
            [.error(message: "Malformed Claude event: \(detail)")]
        }
        func requiredString(_ value: Any?) -> String? {
            guard let string = value as? String, !string.isEmpty else { return nil }
            return string
        }

        switch type {
        case "system":
            let subtype = json["subtype"] as? String
            switch subtype {
            case "init":
                let sessionId = json["session_id"] as? String
                return [.sessionInit(sessionId: sessionId)]
            case "task_started":
                // Sub-agent started — toolUseId links to the Agent tool_call
                guard let toolUseId = requiredString(json["tool_use_id"]) else {
                    return malformed("missing tool_use_id in system/task_started")
                }
                let description = json["description"] as? String ?? ""
                let taskType = json["task_type"] as? String
                return [.subAgentStarted(toolUseId: toolUseId, description: description, taskType: taskType)]
            case "task_progress":
                // Sub-agent periodic progress — update live tool count/token count/status
                guard let toolUseId = requiredString(json["tool_use_id"]) else {
                    return malformed("missing tool_use_id in system/task_progress")
                }
                let description = json["description"] as? String
                let lastToolName = json["last_tool_name"] as? String
                let usage = json["usage"] as? [String: Any]
                let toolUses = usage?["tool_uses"] as? Int ?? 0
                let totalTokens = usage?["total_tokens"] as? Int ?? 0
                let durationMs = usage?["duration_ms"] as? Int ?? 0
                return [.subAgentProgress(toolUseId: toolUseId, description: description, lastToolName: lastToolName, toolUses: toolUses, totalTokens: totalTokens, durationMs: durationMs)]
            case "task_notification":
                // Sub-agent completed
                guard let toolUseId = requiredString(json["tool_use_id"]) else {
                    return malformed("missing tool_use_id in system/task_notification")
                }
                let status = json["status"] as? String ?? "completed"
                let usage = json["usage"] as? [String: Any]
                let toolUses = usage?["tool_uses"] as? Int ?? 0
                let totalTokens = usage?["total_tokens"] as? Int ?? 0
                let durationMs = usage?["duration_ms"] as? Int ?? 0
                return [.subAgentCompleted(toolUseId: toolUseId, status: status, toolUses: toolUses, totalTokens: totalTokens, durationMs: durationMs)]
            default:
                return []
            }

        case "assistant":
            guard let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { return [] }
            return content.compactMap { block in
                switch block["type"] as? String {
                case "thinking":
                    return .thinking(content: block["thinking"] as? String ?? "", parentToolUseId: parentToolUseId)
                case "text":
                    return .message(role: "assistant", content: block["text"] as? String ?? "", parentToolUseId: parentToolUseId)
                case "tool_use":
                    guard let toolId = requiredString(block["id"]) else {
                        return .error(message: "Malformed Claude event: missing tool_use id in assistant block")
                    }
                    guard let toolName = requiredString(block["name"]) else {
                        return .error(message: "Malformed Claude event: missing tool_use name in assistant block")
                    }
                    let input = (block["input"] as? [String: Any])
                        .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    // Extract caller agent name (e.g. {"type": "agent", "agent": "Explore"})
                    let caller = block["caller"] as? [String: Any]
                    let callerAgent: String? = (caller?["type"] as? String == "agent")
                        ? (caller?["agent"] as? String) : nil
                    return .toolCall(
                        id: toolId,
                        name: toolName,
                        input: input,
                        parentToolUseId: parentToolUseId,
                        callerAgent: callerAgent
                    )
                default:
                    return nil
                }
            }

        case "user":
            guard let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { return [] }
            return content.compactMap { block in
                guard block["type"] as? String == "tool_result" else { return nil }
                guard let toolUseId = requiredString(block["tool_use_id"]) else {
                    return .error(message: "Malformed Claude event: missing tool_use_id in tool_result")
                }
                let toolUseResult = json["tool_use_result"] as? [String: Any]
                let output = (block["content"] as? String)
                    ?? (toolUseResult?["stdout"] as? String)
                    ?? ""
                return .toolResult(
                    id: toolUseId,
                    output: output,
                    isError: block["is_error"] as? Bool ?? false,
                    parentToolUseId: parentToolUseId,
                    metadata: toolUseResult.map {
                        ToolResultMetadata(
                            stderr: $0["stderr"] as? String,
                            interrupted: $0["interrupted"] as? Bool ?? false,
                            isImage: $0["isImage"] as? Bool ?? false,
                            noOutputExpected: $0["noOutputExpected"] as? Bool ?? false
                        )
                    }
                )
            }

        case "stream_event":
            // Partial message streaming -- extract text deltas for live UI updates.
            // The full assistant event arrives later and is the source of truth.
            guard let event = json["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String
            else { return [] }
            return [.messageChunk(text: text, parentToolUseId: parentToolUseId)]

        case "result":
            let usage = json["usage"] as? [String: Any]
            let isError = json["is_error"] as? Bool ?? false
            let stopReason = json["stop_reason"] as? String
            let durationMs = json["duration_ms"] as? Int ?? 0
            let costUsd = json["total_cost_usd"] as? Double ?? 0
            let permissionDenials = (json["permission_denials"] as? [[String: Any]])?.compactMap { entry in
                guard let toolName = entry["tool_name"] as? String else { return nil }
                return PermissionDenialSummary(
                    toolName: toolName,
                    toolUseId: entry["tool_use_id"] as? String
                )
            } ?? []
            return [.tokens(
                input: usage?["input_tokens"] as? Int ?? 0,
                output: usage?["output_tokens"] as? Int ?? 0,
                cacheRead: usage?["cache_read_input_tokens"] as? Int ?? 0,
                isError: isError,
                stopReason: stopReason,
                durationMs: durationMs,
                costUsd: costUsd,
                permissionDenials: permissionDenials
            )]

        default:
            return []
        }
    }

    func finalize() -> [ConversationEvent] { [] }
}
```

**Unit tests for ClaudeAdapter**: cover all public methods (`decode()`, `sendMessage()`, `buildArgs()`, `sessionFilePath()`, `canResumeSession()`, `sessionLaunch()`) with standard happy-path and error tests. Non-obvious:
- `decode()` must not require a fresh `system/init` before each turn; ordinary post-startup turns still decode and complete correctly
- `decode()` must propagate `parent_tool_use_id` through every variant that carries stream ancestry, including `messageChunk` from `stream_event` lines
- `decode()` must extract `caller.agent` from the nested `caller` dict on `tool_use` blocks only when `caller.type == "agent"` (not `"direct"`)
- `decode()` must surface malformed required IDs (`tool_use.id`, `tool_result.tool_use_id`, `system/task_* .tool_use_id`) as `.error` events instead of normalizing them to empty strings that would corrupt grouping
- `decode()` must preserve `tool_use_result` metadata (`stderr`, `interrupted`, `isImage`, `noOutputExpected`) on `.toolResult` so the UI does not lose rendering hints after persistence
- `sessionLaunch()` falls back to `["--session-id", sessionId]` when the expected `.jsonl` file is missing even if `isResuming == true`, so stale Claude session bindings degrade safely to a fresh launch and surface `.restartedFresh` for the chat warning state
- `sessionLaunch()` with `forkSession: true` only appends `--fork-session` on a real resume path; new/stale launches stay `["--session-id", sessionId]`
- `sendMessage()` must use `write(contentsOf:)` -- the void `write(_:)` raises an uncatchable `NSFileHandleOperationException` on broken pipe instead of a Swift `Error` (validated gotcha)
- `sendMessage()` on a process that has already exited must throw a catchable error, not crash via `NSException`

`TurnState` and `MessageQueue` are defined in Part 2 > Turn State and Message Queue (before Agent Process Spawning).

---
