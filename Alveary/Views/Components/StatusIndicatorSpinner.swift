import SwiftUI

/// Fixed-frame ring spinner for small status slots: 8pt status-dot slots in the
/// sidebar and tab chips, and the 16pt primary-toolbar progress slot. Rotation is the only
/// thing that changes per frame, so the spinner never relayouts mid-spin and its
/// footprint stays identical to the status dot it replaces.
///
/// **The angle comes from the wall clock, never from `@State` seeded in `onAppear`.**
/// The sidebar ring used to snap back partway instead of completing a revolution while a Task
/// ran. A state-seeded `repeatForever` rotation has two ways to produce that: it restarts at 0
/// whenever SwiftUI remounts this view — a rebuilt host row is enough, which a probe confirmed —
/// and an in-flight rotation can be re-targeted by a transaction from an ancestor. Which of the
/// two the sidebar hit was never pinned down, so do not reintroduce state-seeded rotation on the
/// strength of having ruled one out. A phase derived from `context.date` is immune to both: it
/// depends on neither this view's lifetime nor the transaction that reached it, and it keeps
/// every spinner on screen in phase with the others.
///
/// The per-frame re-evaluation this costs is scoped to the `TimelineView` closure, which reads
/// only this view's stored values — it never invalidates the host row — so do not trade it back
/// for a state-driven `repeatForever` on render-cost grounds.
///
/// Snapshot fixtures rely on the `statusSpinnerAnimationsDisabled` environment key
/// (set by the shared snapshot hosts) for a deterministic arc angle, because
/// `EnvironmentValues.accessibilityReduceMotion` is get-only and cannot be injected
/// in tests. Both that key and reduce-motion bypass `TimelineView` entirely and render the
/// arc at 0 degrees — a paused schedule would still hand the fixture the current clock phase.
struct StatusIndicatorSpinner: View {
    /// Seconds per revolution. Duplicated in `AppKitStatusIndicatorSpinner`'s `CABasicAnimation`
    /// duration rather than shared, so a change here has to be made there too or the two rings
    /// stop matching.
    private static let spinDuration: TimeInterval = 0.9

    var color: Color
    var diameter: CGFloat = 8
    var lineWidth: CGFloat = 1.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.statusSpinnerAnimationsDisabled) private var animationsDisabled

    var body: some View {
        if reduceMotion || animationsDisabled {
            ring
        } else {
            TimelineView(.animation) { context in
                ring.rotationEffect(.degrees(Self.degrees(at: context.date)))
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        // Inset by half the stroke so the ring renders fully inside the fixed frame.
        .padding(lineWidth / 2)
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private static func degrees(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: spinDuration)
        return phase / spinDuration * 360
    }
}

private struct StatusSpinnerAnimationsDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Test hook: disables the spin animation so snapshot renders capture a fixed
    /// arc angle. Production code should never set this.
    var statusSpinnerAnimationsDisabled: Bool {
        get { self[StatusSpinnerAnimationsDisabledKey.self] }
        set { self[StatusSpinnerAnimationsDisabledKey.self] = newValue }
    }
}
