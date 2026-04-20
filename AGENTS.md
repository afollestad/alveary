## Keep AGENTS.md Up to Date

**WHEN** making changes, think about whether there are learnings that would be worth documenting for future agents in `AGENTS.md` files (including ones in sub-folders).
**WHEN** making changes to dependencies, project structure, or lint, make sure `README.md` is kept up to date, as well as `AGENTS.md` files (including ones in sub-folders).
**WHEN** adding or updating agent guidance, prefer the narrowest `AGENTS.md` whose scope covers the affected files. Keep instructions in the root `AGENTS.md` only when they are truly repo-wide or protect cross-cutting invariants.
**WHEN** a single guidance bullet covers multiple discrete rules (e.g. "do X", "do not Y", "the reason is Z"), split it into scannable sub-bullets rather than letting it grow into a wall-of-text paragraph. One top-level bullet introduces the topic, each nested sub-bullet captures one rule. Lead the sub-bullet with a short bolded imperative so a reader scanning for a single rule can find it without parsing the whole section.

## Scoped AGENTS Files

Use nested `AGENTS.md` files to keep local guidance close to the code it governs.

- `Alveary/App/AGENTS.md` covers macOS app-lifecycle, shutdown, and the root `ContentView` layout.
- `Alveary/Data/AGENTS.md` covers SwiftData model invariants (`AgentThread`, `Conversation`, `Project`).
- `Alveary/DI/AGENTS.md` covers Knit assemblies, generated DI output, and the SwiftData store location.
- `Alveary/Services/Agent/AGENTS.md` covers the agent runtime and Claude CLI adapter.
- `Alveary/Services/Detection/AGENTS.md` covers `AgentRegistry` and provider detection.
- `Alveary/Services/Git/AGENTS.md` covers worktree lifecycle and the GitHub CLI adapter.
- `Alveary/Services/Notification/AGENTS.md` covers the notification manager, badge-count chaining, and OS notification tap routing.
- `Alveary/Services/Session/AGENTS.md` covers the session manager and session persistence contract.
- `Alveary/Services/Settings/AGENTS.md` covers `.alveary.json` round-tripping and settings persistence.
- `Alveary/Views/AGENTS.md` covers shared SwiftUI view composition rules.
- `Alveary/Views/Components/AGENTS.md` covers shared component and `AppTextEditor` implementation details.
- `Alveary/Views/Chat/AGENTS.md` covers chat-specific view chrome, tab behavior, and conversation interaction contracts.
- `Alveary/Views/Input/AGENTS.md` covers composer autocomplete, slash-command hints, and worktree picker behavior.
- `Alveary/Views/Projects/AGENTS.md` covers the project settings editor and toolbar action surfacing.
- `Alveary/Views/Sidebar/AGENTS.md` covers sidebar-specific interaction patterns.
- `AlvearyTests/AGENTS.md` covers snapshot and test-organization guidance.

**WHEN** creating a new nested `AGENTS.md`, also add a sibling `CLAUDE.md` symlink to it (`ln -s AGENTS.md CLAUDE.md` from inside that directory) so Claude Code picks up the scoped guidance, and add a line for the new file to the list above. The root `project.yml` already excludes `**/CLAUDE.md` from Xcode sources, so no project regeneration is required.

## XCode Project Generation

The XCode project (`Alveary.xcodeproj`) is generated from `project.yml` using XcodeGen (`brew install xcodegen`). **Never edit the `.xcodeproj` directly.**

**WHEN** you create a new `.swift` file, run `xcodegen generate` afterward so the file is included in the Xcode project. The glob-based `sources` in `project.yml` picks up files automatically from the folder structure, but the `.xcodeproj` must be regenerated to reflect the change.

**WHEN** you add a new SPM dependency, add it to the `packages` and `dependencies` sections of `project.yml`, then run `xcodegen generate`.

**DO NOT** commit `Alveary.xcodeproj/` — it is gitignored and regenerated from `project.yml`.

## Building, Testing, and Running

The project currently builds as the `Alveary` scheme in `Alveary.xcodeproj`. The app target's pre-build step requires `knit-cli`; install it with `mint install cashapp/knit knit-cli` if it is missing.

- First-time local setup: `./scripts/setup.sh` installs the required CLI tools, including `xcbeautify` for prettified wrapper-script output, generates `Alveary.xcodeproj`, and configures the repo-local Git hooks.
- Regenerate the Xcode project after project-structure changes with `xcodegen generate`.
- Build from the command line with `./scripts/build.sh`.
- Run the full test suite with `./scripts/test.sh`.
- Run focused tests with `./scripts/test.sh AlvearyTests/AppDelegateTests` or multiple identifiers as separate arguments.
- See `AlvearyTests/AGENTS.md` for snapshot verification details.
- Run the already-built app from the command line with `./scripts/run.sh`.
- The wrapper scripts use the same underlying commands as `xcodebuild -project Alveary.xcodeproj -scheme Alveary -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode build` and `open .build/xcode/Build/Products/Debug/Alveary.app`.
- For interactive development, you can also open `Alveary.xcodeproj` in Xcode and run the `Alveary` scheme directly.
- Ordered validation workflows (build-then-run, build-then-test, record-then-verify) must run strictly serially — never in parallel, and never via `multi_tool_use.parallel`. Wait for `./scripts/build.sh` to exit successfully before starting `./scripts/run.sh` or any dependent command. When the user asks you to build-then-run after each iteration, treat that as a hard sequencing requirement.

- When updating non-UI logic, check if unit tests need to be updated and/or if new cases need to be added.
- When updating UI, check if snapshot tests need to be updated and/or if new cases need to be added.
- Use `./scripts/snapshots.sh` for snapshot workflows, and verify snapshots before committing whenever UI is modified. See `AlvearyTests/AGENTS.md` for the focused snapshot-specific rules.
- If temporary logging is added for debugging, observe logs yourself instead of instructing the user to open the Console app. Also remember to *remove* temporary logs after confirming a fix.

## Linting

The project uses [SwiftLint](https://github.com/realm/SwiftLint) for code style and linting (`brew install swiftlint`).

- The repo ships a pre-commit hook at `.githooks/pre-commit` that runs `swiftlint` for commits touching Swift sources or `.swiftlint.yml`.
- Install the repo-managed hooks once with `./scripts/setup.sh` or `./scripts/install-git-hooks.sh`. This writes a repo-local `core.hooksPath=.githooks` override and does not modify your global Git hooks setup.
- The hook runs `swiftlint` from the project root so nested config discovery still works for `AlvearyTests/.swiftlint.yml`.
- Run `swiftlint` from the project root *without* `--config`; passing an explicit config file bypasses nested config discovery and breaks the `AlvearyTests/.swiftlint.yml` override.
- Run `swiftlint` manually when you want feedback before reaching the commit hook.
- *If a change introduces new lint warnings and/or errors, inform the user before following through with a commit.*

**WHEN** writing new Swift files, follow the rules in `.swiftlint.yml`. Key rules: no force unwraps outside of tests, no force casts, prefer `let` over `var`, max line length 150.

## Code Style And File Organization

These are default structure and readability conventions for new code and routine edits. Follow them unless a nearby type already has an established local pattern.

- Private types should always go *below* public types.
- Add concise code comments where needed for human readers.
- Large types may be split into companion files like `Type+Feature.swift`. When reading current behavior or adding new logic to an existing type, search for same-type extensions and treat those companion files as part of the canonical implementation before editing.
- Prefer categorized companion files once a type starts accumulating distinct concerns, such as `TerminalPane+ResizeHandle.swift` or `TerminalPane+SessionViews.swift`, instead of continuing to grow a single base file. Also lean on companion files earlier to avoid files becoming too large, and use them to resolve lint warnings about file length.

## Self Review and Auditing Changes

**WHEN** I ask for a self review or audit, say "Performing a self review..." first. Then deeply look at uncommitted changes with a pair of fresh eyes, using these questions as a guide:
- Are there any bugs?
- Are there any edge cases?
- Are there any performance issues?
- Will the changes regress any behavior elsewhere?
- Is there any dead code, or stale code?
- Is there any missing test coverage (unit or snapshot)?
- Were snapshots recorded again where needed?
- Are AGENTS.md files up to date and accurate? 
- Can any AGENTS.md files be split up into smaller sections, or into separate files?
- If we fixed a bug, are we sure it won't regress later? What's stopping regression?
- Are there any lint warnings or errors? Do any files need to be split up?

Double-check to make sure nothing is missed or inaccurate.

Automatically resolve anything that's low risk, ask about others before making changes. 

When finished applying fixes, ask the user if they want to do another pass; if so, start at the top with a fresh pair of eyes.
