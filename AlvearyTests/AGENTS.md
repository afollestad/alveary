## Test Execution

These instructions apply to files under `AlvearyTests/`. `AlvearyTests/Snapshots/AGENTS.md` owns the snapshot suite — running `./scripts/snapshots.sh`, the `assertMacSnapshot()` helpers, and baseline organization.

- Run the smallest relevant test scope you can, typically with `./scripts/test.sh <focused identifier>`.
- When updating UI, verify whether snapshot tests need to be updated and run the relevant snapshot checks before finishing.
- Do not assert exact SPM dependency revisions in tests; dependency pins are configuration, and regressions should be covered by behavior-focused tests.
- AppKit animation assertions must honor `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`; CI can disable animations even when local runs keep them enabled.
- SwiftUI logs `Accessing Environment<…>'s value outside of being installed on a View` when a test builds a view struct directly and reads an `@Environment` object property. The read yields `nil`, which is what those tests want; do not host the view or convert the property to explicit injection just to quiet the log.
- **Avoid live `NSPopover` host tests on macOS 26.** Resizing a shown popover or opening nested shown popovers can schedule `_NSWindowTransformAnimation`; AppKit over-releases it after the popover window dies and crashes whichever later test pumps the run loop. `xcodebuild` silently relaunches the crashed host and can still report success, so verify suspicious runs by checking for new `Alveary-*.ips` files in `~/Library/Logs/DiagnosticReports`. Prefer not-shown content/frame tests over OS-skipped live-popover coverage.

## Test File Organization

When a test class grows large, split it into companion files named `<BaseTests>+<Topic>.swift` (for example `ConversationViewModelTests+Settings.swift`). The `+` in the filename has a specific contract in this repo:

- **Use an `extension <BaseTests>` in companion files**, not a new `final class`. This matches the convention in the main app (for example `ConversationViewModel+Settings.swift`) and keeps all tests for a single subject under one class so shared fixtures, helpers, and `setUp`/`tearDown` apply uniformly.
  - Why: mixing separate `final class <Base><Topic>Tests: XCTestCase` into `<BaseTests>+<Topic>.swift` files made the `+` convention ambiguous — readers could not tell from the filename whether the file extended the base suite or introduced a parallel one.
  - How to apply: when adding a new `<BaseTests>+<Topic>.swift` companion, declare `extension <BaseTests> { ... }`. Preserve the base class's actor annotation (for example `@MainActor`) on the extension. Only declare a separate `XCTestCase` subclass when the suite is genuinely independent; in that case do *not* use the `+` filename — name the file after the new class (for example `ScheduledTaskRootLockTests.swift`).
- Support files that define fixtures, mocks, or helper types (for example `*+Support.swift`, `*+Fixtures.swift`) are an accepted exception — those declare separate helper types rather than extending the base suite.
