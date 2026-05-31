## Test Execution

These instructions apply to files under `AlvearyTests/`.

- Run the smallest relevant test scope you can, typically with `./scripts/test.sh <focused identifier>`.
- When updating UI, verify whether snapshot tests need to be updated and run the relevant snapshot checks before finishing.
- Do not assert exact SPM dependency revisions in tests; dependency pins are configuration, and regressions should be covered by behavior-focused tests.

## Test File Organization

When a test class grows large, split it into companion files named `<BaseTests>+<Topic>.swift` (for example `ConversationViewModelTests+Settings.swift`). The `+` in the filename has a specific contract in this repo:

- **Use an `extension <BaseTests>` in companion files**, not a new `final class`. This matches the convention in the main app (for example `ConversationViewModel+Settings.swift`) and keeps all tests for a single subject under one class so shared fixtures, helpers, and `setUp`/`tearDown` apply uniformly.
  - Why: mixing separate `final class <Base><Topic>Tests: XCTestCase` into `<BaseTests>+<Topic>.swift` files made the `+` convention ambiguous — readers could not tell from the filename whether the file extended the base suite or introduced a parallel one.
  - How to apply: when adding a new `<BaseTests>+<Topic>.swift` companion, declare `extension <BaseTests> { ... }`. Preserve the base class's actor annotation (for example `@MainActor`) on the extension. Only declare a separate `XCTestCase` subclass when the suite is genuinely independent; in that case do *not* use the `+` filename — name the file after the new class (for example `SidebarViewModelCloneTests.swift`).
- Support files that define fixtures, mocks, or helper types (for example `*+Support.swift`, `*+Fixtures.swift`) are an accepted exception — those declare separate helper types rather than extending the base suite.

## Snapshot Testing

### Running Snapshots

- Use `./scripts/snapshots.sh` for snapshot workflows instead of prefixing `./scripts/test.sh` with `RECORD_SNAPSHOTS=1`; plain `xcodebuild test` does not reliably propagate that environment variable into the app-hosted macOS snapshot tests.
- Verify snapshot tests with `./scripts/snapshots.sh verify` and record them with `./scripts/snapshots.sh record`.
- `./scripts/snapshots.sh record` tolerates SnapshotTesting's expected non-zero record exit and then verifies the same identifiers before reporting success.
- `./scripts/snapshots.sh` defaults to `AlvearyTests/SnapshotTests`, and also accepts focused identifiers like `AlvearyTests/SnapshotTests/testSidebarViewPopulated`.
- Snapshot failure artifacts default to `.build/snapshot-failures` through `SNAPSHOT_ARTIFACTS`; set that environment variable only when a caller needs a different artifact directory.

Examples:
```sh
./scripts/snapshots.sh verify AlvearyTests/SnapshotTests/testSidebarViewPopulated
./scripts/snapshots.sh record AlvearyTests/SnapshotTests/testSidebarViewPopulated
```

### Organizing Baselines

- Prefer focused companion snapshot files such as `SnapshotTests+Terminal.swift` instead of continuing to grow `SnapshotTests.swift`; keep snapshot coverage grouped by screen or feature area.
- Moving a snapshot test into a different file changes the baseline lookup path under `AlvearyTests/Snapshots/__Snapshots__/`; move or re-record the reference images to match the new companion file, and run `xcodegen generate` afterward if you added, removed, or renamed snapshot test source files.

### Coverage Guidance

- When changing transcript bubble spacing or bubble chrome, keep grouped chat-bubble snapshots (for example stacked outbound and stacked assistant bubbles) alongside single-bubble cases; single-item baselines do not catch inter-bubble spacing regressions.
- AppKit owns the live transcript surface. Keep native transcript snapshots in `SnapshotTests+AppKitTranscript.swift`; do not add new SwiftUI transcript-row snapshots.
- Native migration snapshots are parity gates. Verify the replaced SwiftUI surface before recording baselines, and add focused coverage for hover or pressed states when a migrated AppKit control has custom interaction styling.

### `assertMacSnapshot()` Internals

- Keep `assertMacSnapshot()` window-backed. macOS SwiftUI snapshots that render sidebar `List` content with custom section headers can capture as a blank background if they are hosted in a bare `NSHostingController` without an `NSWindow` display pass.
- `assertMacSnapshot()` supports dark-mode coverage via its `colorScheme:` argument; when adding dark-mode snapshots, keep the SwiftUI `colorScheme` and the hosting `NSAppearance` in sync or AppKit-backed colors such as `separatorColor` will render incorrectly.
- `assertMacSnapshot()` positions its `NSWindow` *far* off-screen and flushes first responder before rendering. Don't revert those: a window positioned at on-screen coordinates sits inside the primary-display space and picks up the real cursor's position, which AppKit consults mid-render and applies as a hover highlight on whichever control happens to be under that point (e.g. a `Picker` rendering a gray rounded rect behind its selected label on only some runs). `window.makeFirstResponder(nil)` before `displayIfNeeded()` produces a deterministic, focus-free baseline — `NSHostingController` can settle on an initial first responder during its first layout pass.
- `assertMacSnapshot()` uses SnapshotTesting's native AppKit renderer on Retina displays and falls back to a fixed 2x bitmap renderer when headless CI exposes only a 1x screen. Use `ALVEARY_FORCE_FIXED_SCALE_SNAPSHOTS=true ./scripts/snapshots.sh verify ...` to verify the fallback locally. Do not re-record baselines only because CI is 1x; the fallback exists so Retina baselines remain comparable.
- `assertMacSnapshot()` runs its pixel comparison at a relaxed precision, not the SnapshotTesting library's strict default. Both knobs are parameters on the function and fall back to shared default constants at the top of `SnapshotTestSupport.swift`.
    - **Default values: `precision: 0.99, perceptualPrecision: 0.99`.** Both have to move together — `perceptualPrecision` sets the per-pixel Delta-E tolerance, but with `precision` still at `1.0` the test fails if even one pixel crosses it. `0.99` on both maps to the Delta-E band the library documents as "mimics the precision of the human eye".
    - **Why not `1.0`/`1.0`:** Core Graphics' color-managed PNG decode path is not reliably bit-stable across runs. The embedded iCCP profile is resolved through `CGContext`, and tiny per-channel rounding differences survive the encoder round trip on larger, color-rich baselines (diff viewer with syntax highlighting, settings screens, composer autocomplete at scroll offset). Those baselines had been re-recorded more than once with no accompanying code change before this loosening landed.
    - **Overriding at a call site:** if a specific test wants stricter or looser matching, pass an explicit `precision:` and/or `perceptualPrecision:` argument to `assertMacSnapshot(...)`. Do *not* tighten the shared defaults — the drift class returns for every baseline at the same time.
