import SwiftData
import SwiftUI

/// Snapshots a SwiftData-backed view, then waits for its observations to unregister.
///
/// `assertMacSnapshot` builds and releases the query-bearing view inside its own autorelease
/// pool, but SwiftUI queues the `@Query` teardown as main-actor work that a synchronous return
/// never lets run. The next test's in-memory context save then reaches a stale observation and
/// crashes. Suspending here — while retaining the *container*, not the constructed view — lets
/// that queued work drain first. The synchronous helper stays correct for views without
/// SwiftData observations.
@MainActor
func assertMacModelSnapshot<V: View>(
    modelContainer: ModelContainer,
    size: CGSize,
    named: String? = nil,
    colorScheme: ColorScheme = .light,
    precision: Float = defaultPixelPrecision,
    perceptualPrecision: Float = defaultPerceptualPrecision,
    forceFixedScale: Bool = false,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    @ViewBuilder content: @escaping () -> V
) async {
    assertMacSnapshot(
        content().modelContainer(modelContainer),
        size: size,
        named: named,
        colorScheme: colorScheme,
        precision: precision,
        perceptualPrecision: perceptualPrecision,
        forceFixedScale: forceFixedScale,
        file: file,
        testName: testName,
        line: line
    )
    await awaitSnapshotHostTeardown(retaining: modelContainer)
    withExtendedLifetime(content) {}
}

@MainActor
func awaitSnapshotHostTeardown<Retained>(retaining retained: Retained) async {
    // A nested run-loop pump cannot execute queued main-actor teardown work. Suspend
    // cooperatively so SwiftUI can unregister SwiftData observations while their
    // container is still alive.
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(20))
    withExtendedLifetime(retained) {}
}
