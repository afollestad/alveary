# Part 2h: Permissions

Permission model, auto-trust, permission modes, plan mode behavior, reconfigure-session flow. Continues from Part 2g.

## Permissions and Auto-Approve

The app has no permission model of its own. It delegates entirely to the agent CLI. The `permissionMode` string (e.g. `"default"`, `"bypassPermissions"`) flows from the UI through the agent spawn pipeline via `AgentSpawnConfig.permissionMode`. The adapter's `buildArgs()` appends `--permission-mode <mode>` when set. The shared UI surfaces are driven by provider metadata (`ProviderDefinition.supportedPermissionModes` and `suggestedWriteEscalationMode`) so a future provider can expose a different mode set or no escalation CTA without rewriting the chat composer:

- **Claude**: use `--permission-mode bypassPermissions` for the v1 Skep contract. Claude also exposes legacy bypass-related flags, but Skep does not depend on them or surface them directly in the shared UI.

### Auto-Trust (Claude Only)

Reference: [Claude Code Settings](https://code.claude.com/docs/en/settings) | [Permissions](https://code.claude.com/docs/en/permissions)

The app can write to `~/.claude.json` (Claude Code's global config) to auto-trust worktree directories. When auto-trust is enabled and the provider is Claude, set `hasTrustDialogAccepted: true` and `hasCompletedProjectOnboarding: true` in the `projects` map for the worktree path. The key is the worktree's **literal absolute path** (not slashes-to-dashes — that encoding is only for session file names):

```json
{
  "projects": {
    "/Users/you/Development/worktrees/fix-auth-a2b": {
      "hasTrustDialogAccepted": true,
      "hasCompletedProjectOnboarding": true
    }
  }
}
```

This happens during `ProviderSetupService.prepareForSpawn()` when auto-trust is enabled in `AppSettings` and the thread is actually using a worktree. Project-root threads intentionally skip this write so the runtime behavior matches the setting name. The write uses read-merge-write with atomic replacement (write to temp file, then `FileManager.replaceItemAt`) to preserve other keys in `~/.claude.json`.

---

## Permission Modes (Including Plan Mode)

Reference: [Permission Modes](https://code.claude.com/docs/en/permission-modes)

Claude supports multiple permission modes activated via the **`--permission-mode <mode>`** CLI flag at spawn time.

Available permission modes for Claude:

| Mode | Behavior | When to use | UI indicator |
|---|---|---|---|
| `default` | Interactive CLI usage asks before destructive actions. In Skep's non-interactive `stream-json` flow, denied actions come back as auto-denied `tool_result` errors plus `result.permission_denials`. | Normal usage -- the safe default. | None (default state) |
| `plan` | Read-only. Agent can read files, search, run simple read-only bash commands, and analyze, but cannot edit files or run destructive commands. | When the user wants the agent to research and propose a plan before executing. | "Plan Mode" badge in chat view |
| `acceptEdits` | Auto-accept file edits but confirm other actions (bash commands, deletions). | When the user trusts the agent to edit code but wants oversight on shell commands. | "Auto-Edit" badge |
| `auto` | Auto-accept most actions. Only prompts for high-risk operations. | When the user wants minimal interruption. | "Auto" badge |
| `bypassPermissions` | Skip all permission checks (verified: works without `--dangerously-skip-permissions`). | Sandboxed environments or full trust. Equivalent to choosing Auto-Approve as the default permission mode for new threads. | "Auto-Approve" badge |

Note: `dontAsk` mode (CI/automation) is intentionally excluded from the UI. All modes are agent-side -- the app just sets the flag and shows the badge. `AppSettings.permissionMode` determines which mode new threads start with; setting it to `bypassPermissions` makes new threads auto-approve by default.

### Permission Behavior in Non-Interactive Mode (Verified)

When Claude is spawned with `-p` (print mode) and `--input-format stream-json`, permissions **cannot be approved interactively via stdin**. The CLI handles permissions internally:

| Mode | Read tools | Write tools | Bash (simple) | Bash (piped/complex) |
|---|---|---|---|---|
| `bypassPermissions` | Allowed | Allowed | Allowed | Allowed |
| `plan` | Allowed | Refused (Claude declines in its response) | Allowed | Auto-denied |
| `default` | Allowed | Auto-denied | Allowed | Some auto-denied |
| `acceptEdits` | Allowed | Allowed | Auto-denied for some | Auto-denied for some |

When a tool is auto-denied, the event stream shows a `user` event with a `tool_result` containing `is_error: true` and a message like "Claude requested permissions to write to /path, but you haven't granted it yet." Claude then sees this denial and responds accordingly.

**App behavior**: permission denials are detected via the structured `permission_denials` array on the `result` event (not by matching error message text, which would be fragile). The adapter preserves each denied tool name (for example `Write`, `Edit`, `Bash`, `AskUserQuestion`) on the normalized `.tokens` event. When that array is non-empty, `ConversationState.showPermissionBanner` is set to `true`, and the chat view renders an inline banner above the input area. The banner only shows a provider's `suggestedWriteEscalationMode` CTA when at least one denied tool intersects that provider's `writeEscalationEligibleTools`; otherwise it stays dismiss-only. This prevents a denied Bash or AskUserQuestion turn from incorrectly offering Auto-Edit, which would not fix the underlying denial. Claude's write-denial banner therefore offers Auto-Edit only for denied file-mutation tools:

This permission surface is chat-specific UI, not the shared `InlineBanner` from Part 4e. It can carry provider CTA buttons and disabled-state rules tied to reconfigure, so it should remain a small chat-local helper instead of turning the shared banner component into a multi-purpose action row.

```
│  ┌─ Working ─────────────────────────────────────┐  │
│  │ ✓  Read `src/auth.swift`                      │  │
│  │ ✕  Edit `src/auth.swift`  — permission denied │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌─ 🔒 Permission needed ────────────────────────┐  │
│  │ Claude needs write access to edit files.       │  │
│  │ [ Switch to Auto-Edit ]  [ Keep Current Mode ] │  │
│  └───────────────────────────────────────────────┘  │
```

When the denial is for a non-write tool, keep the same banner but drop the escalation CTA entirely:

```
│  ┌─ Working ─────────────────────────────────────┐  │
│  │ ✓  Read `README.md`                           │  │
│  │ ✕  Bash `git status | cat` — permission denied│  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌─ 🔒 Permission needed ────────────────────────┐  │
│  │ Claude could not run a restricted command.     │  │
│  │ [ Dismiss ]                                    │  │
│  └───────────────────────────────────────────────┘  │
```

"Switch to Auto-Edit" snapshots the previous mode, updates `thread.permissionMode`, then calls `reconfigureSession()` with the new config. On success it clears the permission banner; on failure it restores the previous mode so the visible dropdown/badge keep matching the still-live session. The banner follows the same busy gating as the dropdowns: disable the reconfigure action while a turn is active, an outbound send is reserved, or another reconfigure is already in flight. While that fork-session reconfigure is in flight, `ConversationState.isReconfiguringSession` disables the composer/dropdowns and shows an inline "Applying session changes..." status so the user cannot queue, steer, or submit against a disappearing process. If Claude had to fall back to a fresh `--session-id <same-uuid>` launch because its resumable artifact was missing, the chat UI must also show a separate dismissible warning that local history is still visible but the live provider context restarted fresh (`sessionContinuityNotice = nil` dismisses that warning; `showPermissionBanner = false` dismisses only the permission banner). Any later `result` event without denials also clears the permission banner, so it only reappears when a new turn is actually blocked. In `plan` mode, Claude refuses write actions in its response text; v1 does **not** synthesize a permission banner from that plain assistant prose, so the plan-mode badge/dropdown remain the cue unless a structured denial is also present. Denied non-write tools (for example Bash or AskUserQuestion) should leave the permission banner dismiss-only rather than advertising Auto-Edit.

### Plan Mode Conversation Flow (Verified)

In `plan` mode, Claude asks clarifying questions and proposes options through standard multi-turn conversation — there is no special "question" or "option selection" event type. Questions and options are plain text in `assistant` messages (same JSON format as any other response — see Part 2e for schemas). `stop_reason: "end_turn"` on the `result` event signals Claude is waiting for input. All user responses use the same stdin JSON format as any other message — no distinction between answering a question, selecting an option, or sending a new instruction.

The app can optionally parse numbered lists from assistant messages and render them as tappable buttons — but this is a UI-level enhancement, not something Claude structures in the JSON.

### How Permission Mode Is Set

Build-order note: the underlying `reconfigureSession()` runtime path is already implemented earlier in Phase 3 (#9 for runtime teardown/respawn and #13 for `ConversationViewModel` integration). This section defines permission-mode behavior and end-to-end usage of that existing path rather than introducing a new runtime owner.

**At thread creation**: the thread creation form includes a permission mode dropdown defaulting to `AppSettings.permissionMode`. The selected mode is stored on the `AgentThread` SwiftData model.

**At spawn time**: `ClaudeAdapter.buildArgs()` reads the thread's `permissionMode` field and adds `--permission-mode <mode>` to the CLI args. Verified by testing: `--permission-mode bypassPermissions` alone is sufficient for full auto-approve.

**On an existing thread**: the user can change the mode via a dropdown in the chat input bar. The selected value is always persisted to `AgentThread.permissionMode` immediately so stopped threads pick it up on their next spawn. If a session is already running, changing the mode uses the normal fork-session reconfigure path when Claude's resume artifact still exists (validated):

1. Snapshot the previous `permissionMode`, then update the thread's `permissionMode` in SwiftData so `ConversationViewModel` can build the new spawn config from the same source of truth.
2. Call `ConversationViewModel.reconfigureSession(config:)`, which delegates to `AgentsManager.reconfigureSession()` for targeted teardown (`process.terminate()`, stream/buffer cleanup). Do **not** close stdin explicitly.
3. Re-spawn with `--resume <original-session-id> --fork-session --permission-mode <new-mode>` in the normal case where the current session's `.jsonl` still exists. That `--fork-session` path is the validated context-preserving flow: Claude creates a new session ID while retaining prior messages and tool results under the new permission mode. If the expected `.jsonl` is missing, `ClaudeAdapter.sessionLaunch()` instead uses the now-validated fallback of `--session-id <same-uuid>` and reports `.restartedFresh` continuity so the UI can show a warning banner. That branch is intentionally fresh-session behavior — the missing provider artifact means prior Claude history is gone even though the app keeps the same binding key, so the VM/UI must surface that continuity break rather than silently preserving only the local transcript.
4. `ConversationViewModel.reconfigureSession()` must reject the request unless the current turn is idle and no outbound send reservation is already in flight, then set `ConversationState.isReconfiguringSession = true` before the fork-session call begins and clear it on both success and failure. The UI disabling is therefore only the UX layer; the VM method itself remains the correctness boundary.
5. Clear `ConversationState.showPermissionBanner` and stale denied-tool names only after successful reconfigure; on failure, restore the previous persisted mode and leave the banner visible so the user can retry or keep the old mode.
6. Update the session map with the new session ID (from the `system/init` event).
7. Update the badge in the chat view.
8. Preserve any queued follow-up messages as queued; v1 does not auto-drain the queue immediately after reconfigure succeeds. The user retries the queued head explicitly under the new session settings.

**Changing effort on an existing thread** follows the same pattern — snapshot the previous `AgentThread.effort`, persist the new value, and if a session is already running, perform the same reconfigure flow because `--effort` is also a spawn-time flag. In the common case that the resume artifact is still present, this is the same validated `--resume ... --fork-session` path; if the artifact is missing, the adapter falls back to a fresh `--session-id` launch as described above. On running-session failure, restore the previous value so the UI does not advertise a setting the live session never adopted. Both permission mode and effort changes use `AgentsManager.reconfigureSession()` from the Phase 3 runtime path ([Part 2d](part2d-spawn-and-buffer.md) plus the [Agent Runtime Teardown supplement](supplement-agent-runtime-teardown.md)) only for the running-session case.

At the UI layer, permission mode, effort, and model changes should all reuse the same small optimistic-with-revert helper described in the [Composer State and Live Progress supplement](supplement-composer-and-live-progress.md) rather than open-coding three variants. The only difference is the storage target (`ConversationState.selectedModel` vs persisted thread fields), not the running-session handoff semantics.

### Reconfigure-Session Sequence Diagram

```
User               ChatInputBar         ConversationVM      AgentsManager       SessionManager
  │                     │                     │                   │                   │
  │  Change dropdown    │                     │                   │                   │
  │  (e.g. Default→Plan)│                     │                   │                   │
  ├────────────────────▶│                     │                   │                   │
  │                     │  update thread.     │                   │                   │
  │                     │  permissionMode     │                   │                   │
  │                     │  in SwiftData       │                   │                   │
  │                     │                     │                   │                   │
  │                     │  reconfigureSession │                   │                   │
  │                     ├────────────────────▶│                   │                   │
  │                     │                     │  reconfigureSession(id, config)       │
  │                     │                     ├──────────────────▶│                   │
  │                     │                     │                   │                   │
  │                     │                     │  ┌─ Targeted teardown (NOT kill()) ─┐ │
  │                     │                     │  │ cancel streamTask                │ │
  │                     │                     │  │ remove eventBuffer               │ │
  │                     │                     │  │ process.terminate() (SIGTERM)    │ │
  │                     │                     │  │ ConversationState PRESERVED      │ │
  │                     │                     │  └─────────────────────────────────┘  │
  │                     │                     │                   │                   │
  │                     │                     │  spawn(id, config) │                   │
  │                     │                     │  ┌─────────────────────────────────┐   │
  │                     │                     │  │ --resume <old-uuid>             │   │
  │                     │                     │  │ --fork-session                  │   │
  │                     │                     │  │ --permission-mode plan          │   │
  │                     │                     │  │ → new Process, new EventBuffer  │   │
  │                     │                     │  └─────────────────────────────────┘   │
  │                     │                     │                   │                   │
  │                     │                     │                   │  system/init event │
  │                     │                     │                   │  → new session ID  │
  │                     │                     │                   │  updateSessionId() │
  │                     │                     │                   ├──────────────────▶│
  │                     │                     │                   │                   │ persist()
  │                     │                     │                   │                   │
  │                     │                     │  subscribe()      │                   │
  │                     │                     ├──────────────────▶│                   │
  │                     │                     │                   │                   │
  │  UI: badge updates  │                     │                   │                   │
  │  "Plan Mode"        │                     │                   │                   │
  │◀─────────────────────────────────────────┤                   │                   │
  │                     │                     │                   │                   │
  │  Agent retains full conversation context  │                   │                   │
  │  (all prior messages, tool results, etc.) │                   │                   │
```

**Key invariants**:
- `ConversationState` (message queue, input draft, selected model, grouper, staged context) is **not** destroyed — the user's in-progress work survives the mode switch.
- The old process's `terminationHandler` fires but is guarded by the stored PID (`processes[id]?.processIdentifier == pid`), so it's a no-op if a replacement process has already been stored under the same conversation ID.
- The sequence diagram shows the normal validated path where Claude can still `--resume` the existing session artifact. If that artifact is missing, the adapter uses the now-validated `--session-id <same-uuid>` fallback instead of `--resume`, and that branch should still be treated as a fresh session because the missing `.jsonl` means Claude no longer has resumable history to load.

---
