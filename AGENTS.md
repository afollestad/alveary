## Keep Guidance Current

- Keep `AGENTS.md` information concise to minimize token usage.
- Keep `AGENTS.md` accurate when changes create useful future-agent context.
- Put new rules in the narrowest `AGENTS.md` that covers the affected files.
- Categorize bullets inside of `AGENTS.md` files with their own sections, if there are enough points; split dense rules into short sub-bullets with bold imperative leads.
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
- `Alveary/Services/Power/AGENTS.md`: keep-awake power assertions.
- `Alveary/Services/Session/AGENTS.md`: session persistence.
- `Alveary/Services/Settings/AGENTS.md`: `.alveary.json`.
- `Alveary/Services/Shell/AGENTS.md`: process execution and output draining.
- `Alveary/Services/Terminal/AGENTS.md`: terminal session state and pruning.
- `Alveary/ViewModels/AGENTS.md`: view-model coordination.
- `Alveary/ViewModels/DiffViewer/AGENTS.md`: diff viewer coordination and workspace state.
- `Alveary/Views/AGENTS.md`: shared SwiftUI, status colors, focus.
- `Alveary/Views/Components/AGENTS.md`: general shared controls.
- `Alveary/Views/Components/Accent/AGENTS.md`: accent tokens and dynamic colors.
- `Alveary/Views/Components/Markdown/AGENTS.md`: markdown rendering and palettes.
- `Alveary/Views/Components/Markdown/Core/AGENTS.md`: shared markdown parser and model.
- `Alveary/Views/Components/Markdown/SwiftUI/AGENTS.md`: SwiftUI markdown entry points.
- `Alveary/Views/Components/Markdown/SwiftUI/Rendering/AGENTS.md`: SwiftUI-only markdown renderer internals.
- `Alveary/Views/Components/Markdown/AppKit/AGENTS.md`: AppKit markdown renderer internals.
- `Alveary/Views/Components/TabChips/AGENTS.md`: shared tab-chip shell.
- `Alveary/Views/Components/TextInput/AGENTS.md`: `AppTextEditor` and AppKit bridge.
- `Alveary/Views/Chat/AGENTS.md`: chat view and conversation contracts.
- `Alveary/Views/Chat/Blocks/AGENTS.md`: shared block primitives.
- `Alveary/Views/Chat/Blocks/AppKit/AGENTS.md`: AppKit transcript row primitives.
- `Alveary/Views/Chat/Blocks/Prompts/AGENTS.md`: `AskUserQuestion` prompt blocks.
- `Alveary/Views/Chat/Blocks/Tasks/AGENTS.md`: task-list blocks.
- `Alveary/Views/Chat/Blocks/Tools/AGENTS.md`: tool rows, groups, and details.
- `Alveary/Views/Chat/ConversationTabs/AGENTS.md`: conversation tab row.
- `Alveary/Views/Chat/Transcript/AGENTS.md`: transcript shell and approval plumbing.
- `Alveary/Views/Chat/Transcript/Links/AGENTS.md`: markdown link resolution.
- `Alveary/Views/Chat/Transcript/Scrolling/AGENTS.md`: follow-mode and scroll mechanics.
- `Alveary/Views/DiffViewer/AGENTS.md`: diff viewer pane UI and loading overlays.
- `Alveary/Views/Input/AGENTS.md`: composer, BlockInputKit bridge, worktree picker.
- `Alveary/Views/Projects/AGENTS.md`: project settings editor.
- `Alveary/Views/Sidebar/AGENTS.md`: sidebar interactions.
- `Alveary/Views/Terminal/AGENTS.md`: terminal pane.
- `AlvearyTests/AGENTS.md`: tests and snapshots.
- `AlvearyTests/ViewModels/DiffViewer/AGENTS.md`: diff viewer view-model tests.
- `scripts/ci/AGENTS.md`: release CI helper scripts.
- `.agents/AGENTS.md`: repo-local agent workflows.
- `.agents/checks/AGENTS.md`: repo-local review, audit, and check workflows.

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

### `xcsift` Output

- Build/test/snapshot wrappers pipe `xcodebuild` through `xcsift -f toon -w` when installed; treat TOON `status` and `summary` as the concise result. `status` is generally `success` or `failed`.
- `summary:` contains indented count fields such as `errors`, `warnings`, `failed_tests`, and `linker_errors`; it can also include `passed_tests`, `build_time`, `test_time`, and `coverage_percent`.
- Inspect TOON sections such as `errors[n]{file,line,message}`, `warnings[n]{file,line,message,type}`, `failed_tests`, `linker_errors`, `slow_tests`, `flaky_tests`, `build_info`, and `executables` when present.
- In `errors[n]{file,line,message}` rows, values are ordered as file path, line number, and quoted message.
- In `warnings[n]{file,line,message,type}` rows, values are ordered as file path, line number, quoted message, and warning type such as `compile` or `swiftui`.
- `linker_errors` entries include `symbol`, `architecture`, `referenced_from`, `message`, and `conflicting_files`; duplicate symbol failures list object paths in `conflicting_files`.
- `failed_tests` entries include `test`, `message`, `file`, `line`, and `duration`; `slow_tests` entries include `test` and `duration`; `flaky_tests` is a list of test names.
- `build_info` can include `targets[n]{name,duration,phases,depends_on}` rows with per-target timing, phases, and dependencies.
- `executables[n]{path,name,target}` lists built artifacts with their path, name, and target.

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
