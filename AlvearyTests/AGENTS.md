## Test Execution

These instructions apply to files under `AlvearyTests/`.

- Run the smallest relevant test scope you can, typically with `./scripts/test.sh <focused identifier>`.
- When updating UI, verify whether snapshot tests need to be updated and run the relevant snapshot checks before finishing.

## Snapshot Testing

- Use `./scripts/snapshots.sh` for snapshot workflows instead of prefixing `./scripts/test.sh` with `RECORD_SNAPSHOTS=1`; plain `xcodebuild test` does not reliably propagate that environment variable into the app-hosted macOS snapshot tests.
- Verify snapshot tests with `./scripts/snapshots.sh verify` and record them with `./scripts/snapshots.sh record`.
- `./scripts/snapshots.sh record` is expected to exit non-zero after writing updated baselines because SnapshotTesting reports recorded snapshots as test failures in record mode; treat a follow-up `./scripts/snapshots.sh verify ...` pass as the confirmation step.
- `./scripts/snapshots.sh` defaults to `AlvearyTests/SnapshotTests`, and also accepts focused identifiers like `AlvearyTests/SnapshotTests/testSidebarViewPopulated`.
- Prefer focused companion snapshot files such as `SnapshotTests+Terminal.swift` instead of continuing to grow `SnapshotTests.swift`; keep snapshot coverage grouped by screen or feature area.
- When changing transcript bubble spacing or bubble chrome, keep grouped chat-bubble snapshots (for example stacked outbound and stacked assistant bubbles) alongside single-bubble cases; single-item baselines do not catch inter-bubble spacing regressions.
- Keep `assertMacSnapshot()` window-backed. macOS SwiftUI snapshots that render sidebar `List` content with custom section headers can capture as a blank background if they are hosted in a bare `NSHostingController` without an `NSWindow` display pass.
- `assertMacSnapshot()` supports dark-mode coverage via its `colorScheme:` argument; when adding dark-mode snapshots, keep the SwiftUI `colorScheme` and the hosting `NSAppearance` in sync or AppKit-backed colors such as `separatorColor` will render incorrectly.
- Moving a snapshot test into a different file changes the baseline lookup path under `AlvearyTests/Snapshots/__Snapshots__/`; move or re-record the reference images to match the new companion file, and run `xcodegen generate` afterward if you added, removed, or renamed snapshot test source files.
- `assertMacSnapshot()` positions its `NSWindow` *far* off-screen and flushes first responder before rendering. Don't revert those: a window positioned at on-screen coordinates sits inside the primary-display space and picks up the real cursor's position, which AppKit consults mid-render and applies as a hover highlight on whichever control happens to be under that point (e.g. a `Picker` rendering a gray rounded rect behind its selected label on only some runs). `window.makeFirstResponder(nil)` before `displayIfNeeded()` produces a deterministic, focus-free baseline — `NSHostingController` can settle on an initial first responder during its first layout pass.

Examples:
```sh
./scripts/snapshots.sh verify AlvearyTests/SnapshotTests/testSidebarViewPopulated
./scripts/snapshots.sh record AlvearyTests/SnapshotTests/testSidebarViewPopulated
```
