import SwiftData
import SwiftUI

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
