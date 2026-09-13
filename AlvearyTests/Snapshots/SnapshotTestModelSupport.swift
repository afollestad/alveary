import AppKit
import SwiftData
import SwiftUI
import XCTest

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

/// Traverse virtual accessibility children too: SwiftUI image slots need not be NSView children.
@MainActor
func requireSnapshotAccessibilityLabel(
    _ label: String,
    in view: NSView,
    pump: () -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    // SwiftUI creates its virtual nodes only while an accessibility client requests them.
    let application = NSApplication.shared
    let enhancedInterface = "AXEnhancedUserInterface" as NSString
    let previousInterface = try XCTUnwrap(application.perform(
        NSSelectorFromString("accessibilityAttributeValue:"), with: enhancedInterface
    )?.takeUnretainedValue(), file: file, line: line)
    _ = application.perform(
        NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true as NSNumber, with: enhancedInterface
    )
    defer {
        _ = application.perform(
            NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: previousInterface, with: enhancedInterface
        )
    }
    view.layoutSubtreeIfNeeded()
    let deadline = Date().addingTimeInterval(2)
    while !snapshotAccessibilityLabels(in: view).contains(label), Date() < deadline { pump() }
    let labels = snapshotAccessibilityLabels(in: view)
    let observed = Array(Set(labels)).sorted().prefix(30).map { String($0.prefix(160)) }
    _ = try XCTUnwrap(
        labels.first { $0 == label },
        "Expected accessibility text '\(label)'; observed \(observed)",
        file: file, line: line
    )
}

@MainActor
private func snapshotAccessibilityLabels(in element: Any, depth: Int = 0) -> [String] {
    guard depth < 30, let node = element as? NSObject else { return [] }
    // SwiftUI exposes these selectors without NSAccessibilityProtocol conformance.
    // AppKit buttons expose titles and static text exposes values; explicit SwiftUI labels use AXLabel.
    let labels = ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].compactMap { name -> String? in
        let selector = NSSelectorFromString(name)
        return node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? String : nil
    }
    let childrenSelector = NSSelectorFromString("accessibilityChildren")
    let children = node.responds(to: childrenSelector) ? node.perform(childrenSelector)?.takeUnretainedValue() as? [Any] : nil
    return labels + (children ?? []).flatMap {
        snapshotAccessibilityLabels(in: $0, depth: depth + 1)
    }
}
