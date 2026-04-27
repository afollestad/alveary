## Keep Guidance Current

- Keep `AGENTS.md` information concise to minimize token usage.
- Keep `AGENTS.md` accurate when changes create useful future-agent context.
- Put new rules in the narrowest `AGENTS.md` that covers the affected files.
- Split dense rules into short sub-bullets with bold imperative leads.
- Call out oversized guidance files or sections that should be split.
- When adding a nested `AGENTS.md`, also add sibling `CLAUDE.md` as `ln -s AGENTS.md CLAUDE.md`, then list the new scope below. `project.yml` already excludes `**/CLAUDE.md`.
- Update `README.md` plus scoped guidance when dependencies, project structure, or lint rules change.

## Scoped Guidance

Read the nearest `AGENTS.md` before editing. Current scopes:

- `AGENTS.md`: repo-wide workflow.
- `Alveary/App/AGENTS.md`: lifecycle, commands, root layout.
- `Alveary/Data/AGENTS.md`: SwiftData model invariants.
- `Alveary/DI/AGENTS.md`: Knit and generated DI.
- `Alveary/Services/Agent/AGENTS.md`: provider-neutral agent services.
- `Alveary/Services/Agent/Runtime/AGENTS.md`: runtime, event buffers, deferred tools.
- `Alveary/Services/Agent/Claude/AGENTS.md`: Claude adapter and stream decoding.
- `Alveary/Services/Agent/Claude/Hooks/AGENTS.md`: hook listener and approval policy.
- `Alveary/Services/Agent/Transcript/AGENTS.md`: `ChatItemGrouper`.
- `Alveary/Services/Detection/AGENTS.md`: provider detection.
- `Alveary/Services/Git/AGENTS.md`: worktrees and GitHub CLI.
- `Alveary/Services/Notification/AGENTS.md`: notifications and badge routing.
- `Alveary/Services/Session/AGENTS.md`: session persistence.
- `Alveary/Services/Settings/AGENTS.md`: `.alveary.json`.
- `Alveary/Services/Terminal/AGENTS.md`: terminal session state and pruning.
- `Alveary/Views/AGENTS.md`: shared SwiftUI, status colors, focus.
- `Alveary/Views/Components/AGENTS.md`: general shared controls.
- `Alveary/Views/Components/Accent/AGENTS.md`: accent tokens and dynamic colors.
- `Alveary/Views/Components/Markdown/AGENTS.md`: markdown rendering and palettes.
- `Alveary/Views/Components/Markdown/Rendering/AGENTS.md`: SwiftUI-only markdown renderer internals.
- `Alveary/Views/Components/TabChips/AGENTS.md`: shared tab-chip shell.
- `Alveary/Views/Components/TextInput/AGENTS.md`: `AppTextEditor` and AppKit bridge.
- `Alveary/Views/Chat/AGENTS.md`: chat view and conversation contracts.
- `Alveary/Views/Chat/Blocks/AGENTS.md`: shared block primitives.
- `Alveary/Views/Chat/Blocks/Approvals/AGENTS.md`: tool approval blocks.
- `Alveary/Views/Chat/Blocks/Prompts/AGENTS.md`: `AskUserQuestion` prompt blocks.
- `Alveary/Views/Chat/Blocks/Tasks/AGENTS.md`: task-list blocks.
- `Alveary/Views/Chat/Blocks/Tools/AGENTS.md`: tool rows, groups, and details.
- `Alveary/Views/Chat/ConversationTabs/AGENTS.md`: conversation tab row.
- `Alveary/Views/Chat/Transcript/AGENTS.md`: transcript shell and approval plumbing.
- `Alveary/Views/Chat/Transcript/Links/AGENTS.md`: markdown link resolution.
- `Alveary/Views/Chat/Transcript/Scrolling/AGENTS.md`: follow-mode and scroll mechanics.
- `Alveary/Views/DiffViewer/AGENTS.md`: diff routing and loading overlays.
- `Alveary/Views/Input/AGENTS.md`: composer, autocomplete, worktree picker.
- `Alveary/Views/Projects/AGENTS.md`: project settings editor.
- `Alveary/Views/Sidebar/AGENTS.md`: sidebar interactions.
- `Alveary/Views/Terminal/AGENTS.md`: terminal pane.
- `AlvearyTests/AGENTS.md`: tests and snapshots.
- `scripts/ci/AGENTS.md`: release CI helper scripts.
- `skills/AGENTS.md`: repo-local agent skills.

## Xcode Project

- `Alveary.xcodeproj` is generated from `project.yml`; never edit it directly.
- After creating, moving, removing, or renaming Swift files, run `xcodegen generate`.
- After adding an SPM dependency, update `project.yml`, then run `xcodegen generate`.
- Do not commit `Alveary.xcodeproj/`; it is gitignored and regenerated.

## Build And Test

- First-time setup: `./scripts/setup.sh`.
- The app pre-build needs `knit-cli`; setup installs it, or use `mint install cashapp/knit knit-cli`.
- Build: `./scripts/build.sh`.
- Run the built app: `./scripts/run.sh`.
- Interactive development can also use the `Alveary` scheme in Xcode.
- Test: `./scripts/test.sh`, or pass focused identifiers as arguments.
- Release CI uses Developer ID signing and notarization secrets in GitHub Actions; do not commit certificate or API-key material.
- Snapshot workflows use `./scripts/snapshots.sh`; verify snapshots before committing UI changes.
- Ordered workflows must stay serial, never via `multi_tool_use.parallel`: build-then-run, build-then-test, record-then-verify.
- Add temporary logs early when useful; observe them yourself with `/usr/bin/log`, then remove them after confirming the fix.

## Lint

- Use SwiftLint from the repo root without `--config` so nested configs apply.
- The repo hook runs SwiftLint for Swift or `.swiftlint.yml` commits.
- Install repo hooks with `./scripts/setup.sh` or `./scripts/install-git-hooks.sh`; this sets repo-local `core.hooksPath=.githooks`.
- New Swift should follow `.swiftlint.yml`: no force unwraps outside tests, no force casts, prefer `let`, max line length 150.
- If a change introduces lint warnings or errors, tell the user before committing.

## Code Style

- Put private types below public types.
- Add concise comments only where they help future readers.
- Search for same-type companion files before editing behavior.
- Split large types into focused companions like `Type+Feature.swift`.

## Self Review

When asked for a self review or audit, first say `Performing a self review...`.

Review uncommitted changes for: bugs, edge cases, regressions, performance, dead code, stale code, missing unit/snapshot coverage, missing docs/comments, stale guidance, lint, file-size pressure, and accessibility. Confirm snapshot recording where needed. Fix low-risk issues yourself; ask before risky changes. When done, ask whether the user wants another pass.
