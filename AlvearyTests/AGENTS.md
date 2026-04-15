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
- Keep `assertMacSnapshot()` window-backed. macOS SwiftUI snapshots that render sidebar `List` content with custom section headers can capture as a blank background if they are hosted in a bare `NSHostingController` without an `NSWindow` display pass.
- `assertMacSnapshot()` supports dark-mode coverage via its `colorScheme:` argument; when adding dark-mode snapshots, keep the SwiftUI `colorScheme` and the hosting `NSAppearance` in sync or AppKit-backed colors such as `separatorColor` will render incorrectly.
- Moving a snapshot test into a different file changes the baseline lookup path under `AlvearyTests/Snapshots/__Snapshots__/`; move or re-record the reference images to match the new companion file, and run `xcodegen generate` afterward if you added, removed, or renamed snapshot test source files.

Examples:
```sh
./scripts/snapshots.sh verify AlvearyTests/SnapshotTests/testSidebarViewPopulated
./scripts/snapshots.sh record AlvearyTests/SnapshotTests/testSidebarViewPopulated
```
