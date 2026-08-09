## Demo Mode

DEBUG-only fake data for marketing screenshots, selected by `ALVEARY_DEMO_MODE=1` (`run.sh --demo`
or the Developer menu's relaunch item).

## Module Contract

- **Wrap every file here whole in `#if DEBUG`**, following `RawTranscriptWindow.swift`. Release
  additionally excludes `Alveary/Demo/*` from the compile via `EXCLUDED_SOURCE_FILE_NAMES`; that is
  belt-and-braces, not the primary guard.
- **Never touch real state.** Storage is the isolated `AppStorageProfile.demo()` tree, wiped on
  entry; no network, no writes outside it, and no path under the user's home other than the demo
  Application Support directory.
- **Keep it deterministic.** Times derive from `DemoData.launchedAt`; nothing here may depend on
  what a previous launch left behind, because the profile is wiped every time.

## Isolation Gaps To Respect

- **`SkillsService` and `MCPService` ignore `AppStorageProfile` entirely.** `DefaultSkillsService`
  hardcodes `~/.agentskills` and `~/.agents/skills`, and both services reach `~/.claude/skills`,
  `~/.codex/skills`, `~/.claude.json`, and `~/.codex/config.toml` through `DefaultAgentRegistry`.
  Demo mode is safe only because both are swapped at DI, so **any future service that hardcodes a
  home-directory path needs the same treatment** — injecting a different base directory would not
  be enough, since the sync targets come from the registry.
- **Leave `AppSettings.autoTrustProjects` false.** Auto-trust writes through `ClaudeConfigStore` to
  the real `~/.claude.json`. Seeded threads set `hasCompletedInitialSetup` instead, which is what
  keeps the trust gate from firing; creating a thread by hand in demo mode would still write there.

## Surfaces That Stay Real

Not everything routes through a swapped service. Know these before capturing:

- **Terminal pane** — a real `forkpty`, so it renders the real username and hostname, and `cd`
  into a fake project path fails. Keep it closed while capturing.
- **Provider and model pickers** — real `claude --version` / `codex --version` probes.
- **`worktreeManager` and `gitHubCLIService`** take `shellRunner` directly rather than `gitService`,
  so the Git decorator does not cover them.
- **App update check and notification authorization** can paint a badge or raise a system alert
  mid-screenshot.

## What Demo Mode Cannot Show

- **Streaming-only transcript UI** — thinking/reasoning lines, streaming bubbles, and the
  "Retry / not sent" footer have no persisted representation, so they cannot be seeded.
- **Proposal cards render read-only.** `ScheduledTaskProposalQueueCoordinator`,
  `PullRequestReviewProposalCoordinator`, avatar loading, and proposal diff fetch are not wired, so
  a card shows its persisted snapshot without confirm buttons.

## Seeding Rules

- **Stamp timestamps explicitly.** Transcript ordering sorts on `(conversationId, timestamp)`, and
  every record defaults to `.now`; `DemoTranscriptBuilder.commit(into:endingAt:)` owns the
  increasing sequence.
- **Interleave a non-tool row wherever a standalone tool row is wanted** — a second grouping pass
  merges consecutive tool groups, standalone tools, sub-agent blocks, and prompt blocks into one
  activity group.
- **Keep `AskUserQuestion` out of any conversation holding a live approval.** An unanswered prompt
  disables approval controls for the whole conversation.
- **A live approval must be the conversation's last event**, or be followed only by a `tokens` row
  whose `stopReason` is `tool_deferred`; any other later token row marks it resolved.
- **Host-tool payloads are parser-shaped.** `propose_pr_review`'s `event` is lowercase snake_case
  (`approve` / `request_changes` / `comment`), and tool names use the qualified
  `mcp__alveary_host__*` form.
- **A pull request's review-thread and staged-comment anchors must name lines its served diff
  draws**, or the Changes tab omits them with no error; give every conversation row a distinct
  timestamp, because the Overview sorts on date and `Array.sorted` is not stable.
  `DemoPullRequestFixturesTests` guards both.
- **Never invent prose for a machine-written field.** `ScheduledTask.pauseReason` / `lastError` are
  written only by the scheduler engine and `pauseForProjectDeletion`; pausing by hand clears both.
  Seed them verbatim from those sources or leave them nil.
- **Seeded `ScheduledTaskRun`s stay inert**: terminal status, `requiresFinalizationRecovery` false,
  and every `preparedWorkspace*` / `pendingWorktreeCleanup*` / provenance field nil, so cleanup and
  marker verification never engage against fake paths.
- **Never seed draft threads.** Launch cleanup treats a failed draft fetch as "delete every draft".

## Demo Assets

`DemoAssets/` sits at the repo root, outside every `project.yml` `sources:` path, so xcodegen
cannot bundle it — `#if DEBUG` cannot strip a resource, and Copy Bundle Resources flattens, so a
leak would land at the top of `Contents/Resources` in the notarized ZIP. A Debug-only post-build
phase copies it in, and `scripts/ci/verify-exported-app.sh` fails the release if one ever reaches
an exported app.
