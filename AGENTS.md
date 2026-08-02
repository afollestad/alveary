## Keep Guidance Current

- Keep `AGENTS.md` accurate when changes create useful future-agent context; put new rules in the narrowest `AGENTS.md` that covers the affected files.
- A bullet states one rule, imperatively. Cap rationale at one clause naming the failure mode; drop discovery narratives, rejected alternatives, and measurements unless the number itself is the constraint.
- Do not add bullets that restate what the named code already says — prefer improving that code's doc comment. Keep rules the code cannot show: cross-file couplings, deliberate absences, and prohibitions against reintroducing removed behavior.
- One owner per rule. Cross-reference a rule that lives in another `AGENTS.md` instead of restating it, and when adding guidance, check whether existing guidance now duplicates or supersedes it.
- Soft budget: ~40 words per bullet, ~1500 words per file. On breach, trim or split into sections rather than letting the file grow. Avoid file-listing maps in small folders; they rot silently.
- Categorize bullets with `##` sections when there are enough points; split dense rules into short sub-bullets with bold imperative leads.
- When adding a nested `AGENTS.md`, create its sibling symlink with `ln -s AGENTS.md CLAUDE.md`; that symlink is what loads the file into context. `project.yml` already excludes `**/CLAUDE.md`.
- Update `README.md` plus scoped guidance when dependencies, project structure, or lint rules change.

## Scoped Guidance

Read the nearest `AGENTS.md` before editing; every scoped folder pairs it with a `CLAUDE.md` symlink that auto-loads it, and `find . -name AGENTS.md -not -path './.build/*'` lists them all.

## Xcode Project

- `Alveary.xcodeproj` is generated from `project.yml`; never edit it directly.
- After creating, moving, removing, or renaming Swift files, run `xcodegen generate`.
- After adding an SPM dependency, update `project.yml`, then run `xcodegen generate`.
- Do not commit `Alveary.xcodeproj/`; it is gitignored and regenerated.
- Debug app signing uses `Config/CodeSigning/AlvearyDebugTCC.requirements` so app-shot TCC grants survive rebuilds. If `PRODUCT_BUNDLE_IDENTIFIER` changes, update that requirement too. When a privacy row is enabled but raw probes are false, reset Alveary's TCC grants or remove the stale row before re-dragging the rebuilt app.

## Build And Test

- First-time setup: `./scripts/setup.sh`.
- The app pre-build needs `needle 0.25.1`; setup installs `needle` and fails clearly if the installed version does not match.
- Build: `./scripts/build.sh`.
- `TYPECHECK_BUDGET_MS=<ms>` fails the build when any function body or expression in this repo's own sources exceeds that type-check time, and prints the offenders. CI sets `3000`, plus `TYPECHECK_TEST_BUDGET_MS=7000` for test sources; every entry point reads `scripts/lib/typecheck-budget.sh`, whose comments cover the mechanism, exclusions, and CI noise. See the type-check budget bullet in `Alveary/Views/AGENTS.md`.
    - `snapshots.sh` matches the settings but does not enforce. Budgeting changes build settings, forcing a full recompile; `build.sh` additionally forces `--no-xcsift`.
    - A local budget run only reports files the build actually recompiled, so an incremental run can pass while an untouched file is over budget; change the budget value (or clean) for the full picture. CI always builds clean.
    - A CI-only over-budget report on a trivial test statement is attribution noise: recalibrate `TYPECHECK_TEST_BUDGET_MS` with real headroom over the observed number instead of restructuring — each pass costs a red build to discover. App sources have never shown the noise, so `build.sh` keeps the base budget.
    - Genuine cost is still worth removing: prefer explicitly typed helpers over repeating a nested initializer at many call sites (`AppDelegateTests+NotificationSupport.swift`), and hoist large typed literals out of generic assertion calls.
    - The guard costs one extra full CI compile per run (~150s; the snapshot step's `build-for-testing` recompiles). Treat that as the price of the guard, not a misconfiguration to chase.

### Running And Testing

- Run the built app: `./scripts/run.sh`.
- Interactive development can also use the `Alveary` scheme in Xcode.
- Test: `./scripts/test.sh`, or pass focused identifiers as arguments.
- Lint: `./scripts/lint.sh`.
- Release CI uses Developer ID signing and notarization secrets in GitHub Actions; do not commit certificate or API-key material.
- Snapshot workflows use `./scripts/snapshots.sh`; verify snapshots before committing UI changes.
- Ordered workflows must stay serial, never parallelized: build-then-run, build-then-test, record-then-verify.
- Add temporary logs early when useful; observe them yourself with `/usr/bin/log`, then remove them after confirming the fix.

### `xcsift` Output

- Build/test/snapshot wrappers pipe `xcodebuild` through `xcsift -f toon -w` when installed; treat TOON `status` (`success` or `failed`) and the `summary` counts as the concise result.
- Inspect TOON sections such as `errors[n]{file,line,message}`, `warnings[n]{file,line,message,type}`, `failed_tests`, `linker_errors`, `slow_tests`, `flaky_tests`, `build_info`, and `executables` when present; row headers name their own field order.

## Lint

- Use `./scripts/lint.sh` for full repo linting.
- Use SwiftLint from the repo root without `--config` so nested configs apply.
- Install repo hooks with `./scripts/setup.sh` or `./scripts/install-git-hooks.sh`; this sets repo-local `core.hooksPath=.githooks`.
- New Swift follows `.swiftlint.yml` (no force casts, max line length 150) plus conventions the config does not encode: no force unwraps outside tests, prefer `let`.
- If a change introduces lint warnings or errors, tell the user before committing.

## Code Style

- Put private types below public types.
- Add concise comments only where they help future readers.
- Search for same-type companion files before editing behavior.
- Split large types into focused companions like `Type+Feature.swift`.
