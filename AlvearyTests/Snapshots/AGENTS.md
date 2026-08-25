## Snapshot Tests

These instructions cover `AlvearyTests/Snapshots/` — `SnapshotTests` and its `+Topic` companions, the fixtures they build on, the `assertMacSnapshot()` / `assertMacModelSnapshot()` helpers, and the baselines under `__Snapshots__/`. `AlvearyTests/AGENTS.md` owns test execution and the `+Topic` file convention this suite also follows.

**Keep a rule here only when the code that would violate it is not the code that documents it.** The helpers carry their own mechanism: `defaultPixelPrecision` holds the relaxed-precision defaults and why `1.0` is unreachable, `assertMacSnapshot` its window-backed render and off-screen determinism, `assertMacModelSnapshot` its SwiftData teardown, `macSnapshotImage` renderer selection, and `snapshotCornerBackgroundPixel` the three-corner rule. `scripts/snapshots.sh` documents why it patches the `.xctestrun` and why `record` re-verifies.

### Running

- **Use `./scripts/snapshots.sh`, never `RECORD_SNAPSHOTS=1 ./scripts/test.sh`.** Plain `xcodebuild test` does not reliably propagate that variable into the app-hosted macOS tests, so the run silently verifies instead of recording. Its `usage()` covers both forms.
- **Pass at most four focused identifiers per run.** Beyond that the run executes *zero* tests while still printing `status: success` and "Snapshot verification passed", so a batch re-record leaves every baseline stale. A real run prints `passed_tests` — two per test — and, recording, one "Record mode is on" error per baseline. Split longer lists into batches.
- **A newly conditional element needs a fixture audit, not a `verify`.** One that renders only in some state adds too few pixels to breach the 1% budget, so grep the fixtures that seed that state (`setStatus`, say) and re-record their baselines.
- **Audit for stale baselines by recording the full suite and diffing decoded pixels, not `git status`.** Decode drift marks most PNGs byte-changed, burying the few that actually moved.
- **A macOS update can fail text baselines locally while CI stays green.** Local runs compare at 2x/`0.99` and CI's 1x fallback at `0.9`, so glyph-metric drift clears one threshold and not the other. Re-record, then confirm through `ALVEARY_FORCE_FIXED_SCALE_SNAPSHOTS=true ./scripts/snapshots.sh verify …`.

### Calling The Helpers

- **Keep stored baselines at 2x, and never re-record one only because CI captured it at 1x.** The fallback normalizes the 2x reference in memory; re-recording against a 1x runner would bake the lower-resolution capture in for everyone.
- **Reach for `assertMacModelSnapshot()` whenever the view reads `@Query`.** The synchronous helper returns before SwiftUI unregisters SwiftData observations, so a later in-memory context save crashes an unrelated test. A custom persistent host that bypasses both helpers owes the same pairing — `closeSnapshotWindow()` then `awaitSnapshotHostTeardown(retaining:)`.
- **Fill a fixture bitmap through `appearanceStableFixtureFillColor(_:)`.** System colors are dynamic, so a dark-mode host bakes the dark variant into the bytes and a light-mode CI runner disagrees over the whole image area.
- **A passing `verify` is not proof the baseline is current.** `precision: 0.99` budgets 1% of pixels and a changed label occupies far less — a full-screen toggle-title rename measured ~0.2% — so `verify` passes with the old text still in the PNG. For an intentional visible change, `record` the affected baselines and eyeball the new images. Do not chase this with stricter call-site precision; the decode drift `defaultPixelPrecision` describes lives on exactly those large images.

### Organizing Baselines

- Prefer focused companion files such as `SnapshotTests+Terminal.swift` over growing `SnapshotTests.swift`; group coverage by screen or feature area.
- **Moving a snapshot test between files changes its baseline lookup path** under `__Snapshots__/`. Move or re-record the reference images to match the new companion, and run `xcodegen generate` if you added, removed, or renamed a source file.

### Coverage

- **Keep grouped chat-bubble baselines alongside single-bubble ones** when changing transcript bubble spacing or chrome; single-item baselines cannot catch inter-bubble spacing regressions.
- **AppKit owns the live transcript surface.** Native transcript snapshots go in `SnapshotTests+AppKitTranscript.swift`; do not add new SwiftUI transcript-row snapshots.
- Treat native migration snapshots as parity gates: verify the replaced SwiftUI surface before recording, and add focused hover or pressed coverage when a migrated AppKit control has custom interaction styling.
- **A prose-dense baseline reflows on CI.** A newer local macOS fits slightly more text per line than the runner, so a wrapped line sitting at its break point moves and clears the tolerance — and re-recording locally cannot fix it, since it already matches locally. Assert wording textually instead.
