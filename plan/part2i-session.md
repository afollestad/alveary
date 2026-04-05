# Part 2i: Session Storage

Session map, SessionManager, persisted session IDs, session lifecycle. Conceptually grouped after Part 2h in the Part 2 narrative, but build this earlier at Phase 3 step #7 before `AgentsManager` so resume state exists before process spawning begins.

### The Session Map

A JSON file in the app's support directory (e.g. `~/Library/Application Support/com.afollestad.skep/session-map.json`). Claude doesn't know it exists.

```json
{
  "claude-main-abc123": {
    "cwd": "/Users/you/project",
    "providerId": "claude",
    "appSessionId": "d4e5f6a7-...",
    "launchSessionId": "d4e5f6a7-..."
  }
}
```

Each entry maps a **conversation ID** to the app-managed session binding plus the `cwd` and provider metadata needed to resume the correct conversation later. Without it, there's no way to tell an agent "resume *this specific* conversation" on the next spawn after the user reopens a thread or relaunches the app.

For Claude, `cwd` is the **canonicalized** working directory used for session identity and orphan lookup, not necessarily the raw path string the UI launched from. Normalize once with `URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path` before storing or comparing it. Runtime validation showed that both live-process cwd inspection and Claude's `system/init.cwd` report the resolved real path, so storing a symlink alias here would break stale-file checks and startup orphan matching.

### Claude Session Storage

**Agent's files**: `~/.claude/projects/<encoded-cwd>/<uuid>.jsonl` where `<encoded-cwd>` is Claude's project-directory encoding of the canonical working directory path (`system/init.cwd`, not a symlinked alias). Validation confirmed slash replacement is part of the transform, but other punctuation is normalized too (for example `/private/.../tmp.GoO5iFLoCO` became `-private-...-tmp-GoO5iFLoCO`). Treat the exact encoding as provider-owned and keep it inside a Claude-specific helper instead of assuming slash-only replacement everywhere.

**One ID per conversation** (verified by testing): the app generates a UUID the first time a conversation is spawned, stores it in the session map, and passes it as `--session-id <uuid>`. Claude uses this exact UUID as its own session ID -- the `system/init` event returns the same UUID. For resume after crash/restart, use `--resume <uuid>` with the stored ID.

This means the session map does **not** need a second opaque provider-owned token, but it does need to distinguish between two Claude-facing IDs:

- `appSessionId` — the session ID the app should use for the **next** resume.
- `launchSessionId` — the session ID currently visible in the live child process argv for orphan ownership lookup.

These are the same for ordinary spawns. After `--resume <old> --fork-session`, Claude reports a **new** `system/init.session_id`, so `appSessionId` advances to that new branch ID while `launchSessionId` intentionally stays on the old resume ID until the next spawn refreshes it. Runtime validation confirmed that this split is temporary: the first later plain `--resume <new>` child again reports `system/init.session_id = <new>` and advertises `--resume <new>` in `ps`, so ordinary resumes collapse the two IDs back together.

**Source of truth**: the session map is authoritative. If its entry is removed (archive/delete) or missing (fresh thread), the next spawn intentionally creates a fresh provider session. This keeps archive/restore semantics correct and avoids accidentally reconnecting to an old Claude session after the app explicitly dropped the binding.

**When Claude's files are read**: only for existence checks -- never reads the `.jsonl` content itself.

- Check session existence via `FileManager.default.fileExists(atPath:)` on the `.jsonl` file.

The app does **not** scan Claude's session directory looking for the "latest" unclaimed session to adopt in v1. The session map remains authoritative: if the app has no binding for a conversation, it creates a fresh provider session instead of attaching to provider-owned history opportunistically.

The `<encoded-cwd>` input for those checks must come from the same canonicalized cwd described above, not from the raw launch path. A symlinked launch directory still lands in Claude's canonical project bucket.

**CLI args:**
- **Normal spawn**: `--session-id <uuid>` (creates the session). Subsequent messages are sent via stdin JSON -- no re-spawn needed.
- **Next spawn after crash/restart/relaunch**: `--resume <uuid>` (reconnects to the existing session using the same UUID).

**Stale detection**: if a known session's `.jsonl` file is missing but the cwd is unchanged, the adapter must fall back to `--session-id <current-uuid>` instead of `--resume`. This is now runtime-validated: deleting the real `.jsonl` makes `--resume <uuid>` fail immediately with `No conversation found with session ID: ...`, while `--session-id <same-uuid>` succeeds, recreates the `.jsonl`, and starts a fresh conversation with no stale history replayed. Do not take this fallback while the old `.jsonl` still exists: Claude errors that the session ID is already in use. If the cwd or provider changed, rotate to a fresh UUID before the next spawn so the session binding matches the new working directory.

**Fresh sessions after entry removal**: if the session map entry is deleted, the next spawn creates a new UUID and a new Claude session. This is intentional for archive/restore and explicit teardown flows.

### Thread Listing

The app does not list Claude's sessions directly. Instead, the app has its own **thread** concept in SwiftData. Each thread maps to one or more conversations, and each conversation owns its own session binding in the session map. That conversation ↔ Claude-session linkage is invisible to the user. The user interacts with app threads; the app handles the translation to Claude sessions behind the scenes.

### Files Read and Written (Mac)

| File | Read | Write | Owner |
|---|---|---|---|
| `~/Library/Application Support/com.afollestad.skep/session-map.json` | Yes | Yes | Skep |
| `~/.claude/projects/<encoded-cwd>/<uuid>.jsonl` | Existence only | Never | Claude |
| `<cwd>/.claude/settings.local.json` | Yes (to merge) | Yes (before spawn) | Shared |
| `~/.claude.json` | Yes (to merge trust) | Yes (atomic rename) | Shared |

**Future providers** may require reading additional provider-owned session stores (for example, repo-local JSON, SQLite, or other agent-specific metadata). `SessionManager` does **not** read those stores directly; it only owns the app-side conversation → session binding. Each provider adapter owns resume-availability checks and session launch args for its own storage format.

For the session map and Claude config files: `FileManager`, `JSONSerialization`, and `Data(contentsOf:)` / `data.write(to:atomically:)`. The atomic write pattern for `~/.claude.json` maps to writing to a temp file and using `FileManager.replaceItemAt(_:withItemAt:)`.

### SessionManager Implementation

`SessionManager` is injectable via Knit. It owns session ID generation, session map persistence, and session lifecycle:

```swift
struct SessionEntry: Codable, Sendable {  // Skep/Services/Session/SessionManager.swift
    var cwd: String
    var providerId: String
    var appSessionId: String         // App-managed persisted UUID the next spawn should resume with
    var launchSessionId: String      // Session ID currently visible in the live child's argv for orphan lookup
}

protocol SessionManager: Actor {  // Skep/Services/Session/SessionManager.swift
    /// Ensures the conversation has a session entry bound to the current canonical
    /// cwd/provider pair.
    /// Returns true only when the existing identity was preserved and the caller may
    /// attempt `--resume`; returns false for a brand-new or rotated identity, which
    /// must spawn with `--session-id` instead.
    func createEntry(conversationId: String, cwd: String, providerId: String) -> Bool
    /// Destructive teardown paths (archive/delete) depend on this being durable, so
    /// persistence failures surface to the caller instead of being silently swallowed.
    func removeEntry(for conversationId: String) throws
    func hasSession(for conversationId: String) -> Bool
    /// Returns the app-managed session UUID for this conversation.
    /// Callers must invoke `createEntry()` first on every spawn path.
    /// In v1 Claude this is also the provider's resumable ID. Future providers that
    /// cannot use an app-supplied resumable ID should keep their provider-owned resume
    /// metadata in adapter-specific storage until that contract is explicitly validated.
    func sessionId(for conversationId: String) -> String
    /// Reverse lookup used by startup orphan cleanup. `cwd` is the canonicalized path
    /// recovered from live process inspection / `system/init.cwd`, not a raw symlink
    /// alias. For Claude, this matches either the current resumable `appSessionId`
    /// or the most recently launched argv `launchSessionId`, because a live
    /// `--fork-session` child still advertises the pre-fork `--resume <old-id>` in
    /// `ps` even after `system/init` rotates to a new session ID. Returns the owning
    /// conversation only when all binding components match, so a reused UUID from
    /// another cwd or provider cannot be mistaken for this app's process.
    func conversationId(forSessionId sessionId: String, cwd: String, providerId: String) -> String?
    /// Updates the app-managed resumable ID after the provider confirms the active
    /// session identity. In v1 Claude the `system/init` ID equals the app-managed ID,
    /// so this overwrites `appSessionId` but intentionally leaves `launchSessionId`
    /// pointing at the old argv-visible `--resume` ID until the next spawn. Future
    /// providers should only reuse this path if they prove the same contract.
    /// Implementations intentionally update the in-memory binding before attempting
    /// the durable write so the current launch does not fall back to the stale
    /// pre-fork session when persistence fails.
    /// Best-effort callers may ignore errors, but the write itself is allowed to fail so
    /// higher-level flows can surface or retry durability problems when they matter.
    func updateSessionId(for conversationId: String, newSessionId: String) throws
    func load()
    func persist() throws
}

actor DefaultSessionManager: SessionManager {  // Skep/Services/Session/DefaultSessionManager.swift
    private var entries: [String: SessionEntry] = [:]
    private let fileURL: URL
    private var hasLoaded = false

    init(supportDirectory: URL) {
        self.fileURL = supportDirectory.appendingPathComponent("session-map.json")
    }

    /// Startup eagerly calls `load()`, but every public read/write path also gates on
    /// this so a fast first spawn cannot race the background warmup and accidentally
    /// create a fresh session when a resume entry already exists.
    private func ensureLoaded() {
        guard !hasLoaded else { return }
        load()
    }

    func createEntry(conversationId: String, cwd: String, providerId: String) -> Bool {
        ensureLoaded()
        if let existing = entries[conversationId] {
            // Session identity is bound to canonical cwd/provider. Preserve the UUID
            // only when the conversation still points at the same normalized working
            // directory and provider. This prevents a thread that moved from project
            // root → worktree (or one that switched providers) from accidentally reusing
            // a mismatched session, and also keeps symlink aliases from forking a second
            // binding for the same underlying directory.
            let shouldPreserveIdentity = existing.cwd == cwd && existing.providerId == providerId
            let sessionId = shouldPreserveIdentity ? existing.appSessionId : UUID().uuidString
            entries[conversationId] = SessionEntry(
                cwd: cwd,
                providerId: providerId,
                appSessionId: sessionId,
                launchSessionId: sessionId
            )
            do {
                try persist()
            } catch {
                print("[SessionManager] Failed to persist reconciled session binding: \(error)")
            }
            return shouldPreserveIdentity
        } else {
            let sessionId = UUID().uuidString
            entries[conversationId] = SessionEntry(
                cwd: cwd,
                providerId: providerId,
                appSessionId: sessionId,
                launchSessionId: sessionId
            )
            do {
                try persist()
            } catch {
                print("[SessionManager] Failed to persist new session binding: \(error)")
            }
            return false
        }
    }

    func hasSession(for conversationId: String) -> Bool {
        ensureLoaded()
        return entries[conversationId] != nil
    }

    func sessionId(for conversationId: String) -> String {
        ensureLoaded()
        guard let entry = entries[conversationId] else {
            preconditionFailure("sessionId(for:) requires an existing entry; call createEntry() first")
        }
        return entry.appSessionId
    }

    func conversationId(forSessionId sessionId: String, cwd: String, providerId: String) -> String? {
        ensureLoaded()
        return entries.first { _, entry in
            return (entry.appSessionId == sessionId || entry.launchSessionId == sessionId)
                && entry.cwd == cwd
                && entry.providerId == providerId
        }?.key
    }

    func removeEntry(for conversationId: String) throws {
        ensureLoaded()
        entries.removeValue(forKey: conversationId)
        try persist()
    }

    func updateSessionId(for conversationId: String, newSessionId: String) throws {
        // Update memory first: after `--fork-session`, Claude keeps both the old and new
        // session IDs resumable as separate branches. If this durable write fails, the
        // current launch must keep following the new branch rather than silently rolling
        // back to the old pre-fork session. Intentionally do NOT overwrite
        // `launchSessionId` here — the live child process argv still exposes the old
        // `--resume` ID until the next spawn refreshes that launch metadata.
        ensureLoaded()
        entries[conversationId]?.appSessionId = newSessionId
        try persist()
    }

    func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            entries = try JSONDecoder().decode([String: SessionEntry].self, from: data)
        } catch {
            // Corrupted JSON — back up the bad file so it can be diagnosed,
            // rather than silently starting with an empty session map. After the
            // backup, this launch continues with no persisted bindings loaded,
            // which degrades resume behavior to fresh sessions until new entries
            // are written successfully.
            // Remove any existing backup first (moveItem fails if dest exists).
            let backupURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("session-map.corrupt.json")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            print("[SessionManager] Corrupted session map backed up to \(backupURL.path): \(error)")
        }
    }

    func persist() throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

`load()` is still called during startup as a warmup step, but correctness does not depend on that task winning the race to first spawn — the actor lazily `ensureLoaded()` on every public method.

Provider-specific resume decisions are intentionally outside `SessionManager`. The spawn path is:

1. `SessionManager.createEntry()` reconciles the conversation's binding to `(cwd, providerId)` and returns whether resuming is still legal for that binding.
2. `SessionManager.sessionId()` returns the persisted session ID.
3. The active `AgentAdapter` decides whether that provider can actually resume right now and builds the correct launch args (`--resume`, `--fork-session`, or a fresh-session path).

For Claude, `ClaudeAdapter.sessionLaunch()` checks whether `~/.claude/projects/<encoded-cwd>/<uuid>.jsonl` exists before emitting `--resume`, and that `<encoded-cwd>` must be derived from the canonicalized cwd stored in `SessionManager`. That existence check is mandatory, not speculative: a missing file makes `--resume <uuid>` fail, while `--session-id <same-uuid>` recreates a fresh session and a new `.jsonl`; conversely, using `--session-id <same-uuid>` while the old file still exists fails because Claude reports that the session ID is already in use. The returned `SessionLaunchDecision.continuity` is therefore what drives the chat's dismissible "provider context restarted fresh" warning. The `system/init` session ID continues to overwrite `appSessionId` because Claude uses the same identifier for both app-supplied and provider-confirmed resume state, but `launchSessionId` intentionally stays on the old fork source until the next spawn because the live child argv still shows `--resume <old-uuid>`. A future provider that returns a different resume token should keep that provider-owned token in adapter-specific storage rather than extending the shared session map preemptively.

### In-Memory Test Implementation

The plan also relies on a lightweight in-memory implementation for unit tests. Because `SessionManager` is an actor protocol and several test suites inject `InMemorySessionManager` directly, define it explicitly instead of treating it as an implied helper:

```swift
actor InMemorySessionManager: SessionManager {  // Skep/Services/Session/InMemorySessionManager.swift
    private var entries: [String: SessionEntry] = [:]

    func createEntry(conversationId: String, cwd: String, providerId: String) -> Bool {
        if let existing = entries[conversationId] {
            let shouldPreserveIdentity = existing.cwd == cwd && existing.providerId == providerId
            let sessionId = shouldPreserveIdentity ? existing.appSessionId : UUID().uuidString
            entries[conversationId] = SessionEntry(
                cwd: cwd,
                providerId: providerId,
                appSessionId: sessionId,
                launchSessionId: sessionId
            )
            return shouldPreserveIdentity
        }
        let sessionId = UUID().uuidString
        entries[conversationId] = SessionEntry(
            cwd: cwd,
            providerId: providerId,
            appSessionId: sessionId,
            launchSessionId: sessionId
        )
        return false
    }

    func removeEntry(for conversationId: String) throws {
        entries.removeValue(forKey: conversationId)
    }

    func hasSession(for conversationId: String) -> Bool {
        entries[conversationId] != nil
    }

    func sessionId(for conversationId: String) -> String {
        guard let entry = entries[conversationId] else {
            preconditionFailure("sessionId(for:) requires an existing entry; call createEntry() first")
        }
        return entry.appSessionId
    }

    func conversationId(forSessionId sessionId: String, cwd: String, providerId: String) -> String? {
        entries.first { _, entry in
            return (entry.appSessionId == sessionId || entry.launchSessionId == sessionId)
                && entry.cwd == cwd
                && entry.providerId == providerId
        }?.key
    }

    func updateSessionId(for conversationId: String, newSessionId: String) throws {
        entries[conversationId]?.appSessionId = newSessionId
    }

    func load() {}
    func persist() throws {}
}
```

Use `InMemorySessionManager` for fast actor-isolated tests of UUID creation, rotation, and removal. Use `DefaultSessionManager` with a temporary directory only when the test specifically needs real file persistence or corrupt-file backup behavior.

### Failure Handling

- **Missing session map**: treated the same as a clean install — no entries loaded, next spawn creates fresh UUID bindings.
- **Corrupt session map**: back up the unreadable file to `session-map.corrupt.json`, continue with an empty in-memory map, and let future successful spawns recreate entries. This is intentionally non-blocking: the app stays usable, but resume history for the corrupted bindings is lost.
- **Persist failure**: keep the in-memory `entries` dictionary for the rest of the current launch and log a developer-facing error. Existing live conversations keep working because the active `Process` and `ConversationState` are already in memory. For ordinary create failures, the risk is loss of resume durability on a later relaunch if no subsequent persist succeeds. For destructive `removeEntry()` failures, the manager-owned teardown path records that durable-write error and `destroyRuntime()` surfaces it back to archive/delete/setup-rollback callers instead of silently leaving a stale binding on disk. For `updateSessionId()` after `--fork-session`, the risk is subtler and now runtime-validated: Claude leaves both the old and new session IDs resumable as separate branches, and the live child argv keeps advertising the **old** `--resume` ID even after `system/init` rotates to the new one. The session map therefore keeps `launchSessionId = old` for orphan lookup while `appSessionId` advances to `new` for the next resume. If that durable write fails, a relaunch before any later successful persist can silently reopen the stale pre-fork branch rather than the fresh post-reconfigure branch. A later successful plain `persist()` is enough to repair the on-disk `appSessionId`; no second reconfigure is required. The shutdown safety-net persist in Part 4e was then stress-validated against deliberately oversized session maps and still stayed within its 500ms bridge budget until roughly 200,000 synthetic entries (~79MB), so the repair path has substantial headroom relative to the expected one-entry-per-conversation v1 footprint.
- **Orderly shutdown during an active turn**: Claude-specific validation showed that a `SIGTERM`-terminated live session still resumes cleanly with the same UUID, and facts introduced by the interrupted user prompt remain in Claude's resumed context. However, the interrupted turn did **not** have a finalized assistant entry in the provider `.jsonl` at exit time. A second stdin message injected while that first turn was still busy could be consumed far enough for Claude to record queue metadata, yet still failed to appear as a persisted `user` entry before shutdown and was absent after `--resume`. Session resume should therefore be treated as preserving provider context and the currently active committed user turn, not as reconstructing partially streamed assistant output or later queued follow-ups that never became the next active turn. Skep must continue to treat its own persisted events / `streamingText` as the source of truth for what the user saw before quit, and any app-owned pending outbound state as the source of truth for follow-ups Claude had not started yet. In v1 that pending outbound state is launch-scoped only: queued messages, staged context, and draft text may be lost on app quit/crash unless they were already durably reflected in SwiftData.
- **Startup orphan cleanup interaction**: the launch-time orphan scan from Part 4e should only terminate a Claude process when a successfully loaded session-map binding proves ownership. The lookup keys are the live argv session flag (`--session-id` / `--resume`) plus the canonical cwd recovered from process inspection, so the session map must store that same canonical cwd rather than the raw launch alias. Because a live `--fork-session` child keeps advertising the pre-fork `--resume <old-id>` in `ps`, `conversationId(forSessionId:cwd:providerId:)` must match both `appSessionId` and `launchSessionId`. If the map was missing or backed up as corrupt, the scan must default to leaving unproven processes alone.

### Session Lifecycle State Diagram

```
                    ┌───────────────────────────────────────────────────────────┐
                    │                                                           │
     New thread     ▼                                                           │
  ──────────► ┌──────────┐  createEntry()  ┌──────────────┐  spawn()   ┌───────────────┐
              │ No entry │───────────────▶│ Entry created │──────────▶│ Session active │
              │          │                │ UUID stored   │ --session-id│ (process alive) │
              └──────────┘                └──────────────┘  <uuid>      └───────┬───────┘
                    ▲                                                       │
                    │                                                       │
                    │  destroyRuntime()                                     │
                    │  (manager-owned      ┌───────────────────────────────┤
                    │   kill → removeEntry)│                               │
                    │                       │                               │
                    │                       ▼                               ▼
              ┌──────────┐         ┌────────────────┐            ┌──────────────────┐
              │ Cleaned  │◀────────│ Process exited │            │ reconfigureSession│
              │ up       │ destroy │ (crash/normal) │            │ (model/mode/effort│
              │          │ runtime │ entry preserved│            │ change)           │
              └──────────┘         │ for resume     │            └────────┬─────────┘
                                   └───────┬────────┘                     │
                                           │                               │
                                           ▼                               ▼
                                   ┌────────────────┐            ┌──────────────────┐
                                   │ Resume          │            │ Fork-session      │
                                   │ --resume <uuid> │            │ --resume <uuid>   │
                                   │ (same session)  │            │ --fork-session     │
                                   └───────┬────────┘            │ --model /          │
                                           │                     │ --permission-mode /│
                                           │                     │ --effort           │
                                           │                     └────────┬─────────┘
                                           │                               │
                                           ▼                               ▼
                                   ┌────────────────┐            ┌──────────────────┐
                                   │ Session active  │            │ system/init       │
                                   │ (same UUID)     │            │ → new session ID  │
                                   └────────────────┘            │ → updateSessionId │
                                                                 └──────────────────┘
```

Key rules:
- **UUID is persisted, not derived** — a new UUID is created when the conversation first gets a session-map entry.
- **Entry survives process exit** — so resume can work on the next spawn after crash/restart/relaunch. Only manager-owned destructive teardown (`destroyRuntime()`, which internally drives `kill()` and then `removeEntry()`) removes it, and that durable removal happens only after the old child exit is confirmed.
- **Fork-session creates a new UUID** — the old `.jsonl` file stays on disk; the new session starts fresh but with full context. `updateSessionId()` persists the new UUID into `appSessionId`. `launchSessionId` intentionally stays on the old `--resume` value until the next spawn because the live process argv still exposes that pre-fork ID. If the durable write fails, the current launch still keeps the new UUID in memory, but a later relaunch can resume the stale pre-fork branch until some later persist repairs the on-disk session map.
- **Entry reconciliation happens on every spawn** — `createEntry()` is not just a first-run helper. It re-checks cwd/provider on every spawn path and returns whether resume is still valid for this identity.
- **Every spawn refreshes `launchSessionId`** — `createEntry()` resets it to whichever session ID the next child will actually launch with, so ordinary resumes collapse back to one ID after a fork.
- **Stale detection** — if the provider-owned session artifact is missing on resume, the adapter falls back to a fresh-session launch using the currently stored UUID; if cwd/provider changed, `createEntry()` rotates to a fresh UUID first.

### Resume and Fork Decision Matrix

| Situation | `createEntry()` result | Session args from adapter session logic | UUID outcome |
|---|---|---|---|
| Brand-new thread or previously removed entry | `false` | `--session-id <uuid>` | Create and persist a brand-new UUID |
| Relaunch/crash recovery with same cwd/provider and session file still on disk | `true` | `--resume <uuid>` | Keep the same UUID/session binding |
| Same cwd/provider but the expected `.jsonl` file is missing | `true` | `--session-id <uuid>` | Keep the stored UUID, let Claude recreate the session file |
| Conversation moved to a different worktree or switched providers | `false` | `--session-id <new-uuid>` | Rotate to a new UUID before spawn |
| Reconfigure model / permission mode / effort on an existing session | `true` | `--resume <old-uuid> --fork-session ...` | Claude returns a new session ID in `system/init`; `appSessionId` updates to that new ID for the next resume while `launchSessionId` stays on `old` until the next spawn refreshes it |

This table is the quickest way to sanity-check session behavior during implementation: only the second row is a plain resume, only the fifth row uses `--fork-session`, and cwd/provider drift always forces the fourth row.

**Unit tests for SessionManager** (use `InMemorySessionManager` or a temp directory): cover session ID persistence, CRUD operations, and persistence round-trips. Non-obvious:
- `createEntry()` returns `true` only when the existing entry's `cwd` and `providerId` still match, so callers know whether `--resume` is legal for this spawn
- `createEntry()` preserves an existing `appSessionId` only when `cwd` and `providerId` are unchanged
- `createEntry()` also resets `launchSessionId` to the session ID the next child will actually launch with, so post-fork orphan-lookup aliases do not linger past the next spawn
- `createEntry()` treats symlinked aliases of the same directory as the same canonical `cwd` when the caller normalizes before storage, so relaunching from `/tmp/link/project` does not rotate the UUID away from the prior `/private/tmp/real/project` binding
- `createEntry()` rotates to a fresh `appSessionId` when `cwd` or `providerId` changes, preventing resume across mismatched session directories
- `sessionId()` returns the established persisted ID and traps in programmer-error cases where `createEntry()` was skipped
- `conversationId(forSessionId:cwd:providerId:)` matches both `appSessionId` and `launchSessionId`, so startup orphan cleanup can still prove ownership of a live post-fork process whose argv advertises the old resume ID
- `load()` is idempotent after the actor is already warm, so the startup warmup task cannot overwrite newer in-memory mutations from an early spawn or reconfigure
- `removeEntry()` surfaces durable-write failures so archive/delete can abort instead of silently leaving a stale resume binding on disk, and `destroyRuntime()` propagates that failure back to higher layers after child exit is confirmed
- `updateSessionId()` for a non-existent conversation is a no-op (does not crash)
- `updateSessionId()` mutates only `appSessionId` before persisting, leaving `launchSessionId` on the old argv-visible fork source until the next spawn refreshes it
- A later successful plain `persist()` after a thrown `updateSessionId()` write repairs the on-disk binding and makes the next fresh `load()` pick up the new forked session ID
- `load()` handles corrupted JSON by backing up the file and starting fresh

Provider-specific resume/fork/stale-launch behavior is covered by adapter tests (Claude in Part 2e), not repeated in `SessionManager` tests.
