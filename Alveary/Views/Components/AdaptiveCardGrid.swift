import SwiftUI

/// One owner for the card grids that pair up when wide enough — Skills, MCP, and the
/// Settings Agents tab — so the column minimum, the two-column threshold, and the flip
/// animation cannot drift apart per screen.
enum AdaptiveCardGridLayout {
    /// Two `columnMinimumWidth` columns plus their gap need 496pt; the rest is slack for
    /// the observing container's content insets. Skills and MCP measure their scroll view
    /// while the Agents tab measures the grid itself, so the threshold is deliberately
    /// loose enough to serve both rather than derived per screen.
    static let twoColumnMinimumWidth: CGFloat = 544
    static let columnMinimumWidth: CGFloat = 240
    static let columnSpacing: CGFloat = 16

    static func columns(count: Int, alignment: Alignment? = nil) -> [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: columnMinimumWidth),
                spacing: columnSpacing,
                alignment: alignment
            ),
            count: count
        )
    }
}

extension View {
    /// Crossfades a grid through its column-count flips. Apply to each `LazyVGrid` whose
    /// columns come from `AdaptiveCardGridLayout`, passing the same count the screen's
    /// `adaptiveCardGridColumnCount(...)` drives.
    ///
    /// A crossfade rather than a glide, deliberately: gliding interpolates every card's
    /// frame toward a target the sliding pane re-narrows each frame, which bounced the
    /// cards' trailing icons left and back right, and it slides translucent cards across
    /// each other, which ghosts the covered card's text through the tint — the fills
    /// cannot be made opaque because the window backdrop is a dynamic material (see
    /// `AppSelectableCardBackground`). Rebuilding under `.id` and fading costs neither.
    func adaptiveCardGridReflow(columnCount: Int) -> some View {
        id(columnCount)
            .transition(.opacity)
    }

    /// Tracks this container's width and flips `columnCount` between two columns and one.
    ///
    /// The flip rides `RightPaneWidthPolicy.presentationAnimation` because the right-pane
    /// slide is what usually drives it: the lane narrows the screen continuously, but
    /// `onGeometryChange`'s action runs outside the slide's transaction, so an unanimated
    /// write snapped the grid into its new layout in a single frame mid-slide. The
    /// animated flip plays as a crossfade — see `adaptiveCardGridReflow(columnCount:)`.
    ///
    /// When the lane publishes `rightPaneSettledMainWidth`, that value drives the flip
    /// instead of live geometry, so the reflow starts on the slide's first frame and plays
    /// concurrently with it. Live geometry alone crosses the threshold wherever the slide
    /// happens to pass it — near the end, the reflow trails the slide as a second beat.
    ///
    /// Pass `spansMainPane: false` when the measured container is inset from the lane's
    /// main-content slot (the Settings Agents grid sits behind the settings side list):
    /// the settled slot width then overstates the container's width by that inset, so the
    /// modifier falls back to the live-geometry flip, which stays animated but late.
    func adaptiveCardGridColumnCount(
        _ columnCount: Binding<Int>,
        spansMainPane: Bool = true
    ) -> some View {
        modifier(
            AdaptiveCardGridColumnCountModifier(
                columnCount: columnCount,
                spansMainPane: spansMainPane
            )
        )
    }
}

private struct AdaptiveCardGridColumnCountModifier: ViewModifier {
    @Binding var columnCount: Int
    let spansMainPane: Bool

    @Environment(\.rightPaneSettledMainWidth) private var settledMainWidth

    /// The first applied value seeds without animation: screens remount on every sidebar
    /// or tab switch, and an animated seed would play the whole reflow on entry whenever
    /// the window is already below the threshold.
    @State private var hasSeededColumnCount = false

    /// The settled width the flip follows, or `nil` to follow live geometry.
    private var settledWidth: CGFloat? {
        spansMainPane ? settledMainWidth : nil
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Int.self) { proxy in
                proxy.size.width >= AdaptiveCardGridLayout.twoColumnMinimumWidth ? 2 : 1
            } action: { newValue in
                // The settled width owns the flip while published: live geometry mid-slide
                // would cross the threshold late, or worse, briefly overrule an early flip
                // and bounce the grid back.
                guard settledWidth == nil else {
                    return
                }
                apply(newValue)
            }
            .onChange(of: settledWidth, initial: true) { _, newValue in
                guard let newValue else {
                    return
                }
                apply(newValue >= AdaptiveCardGridLayout.twoColumnMinimumWidth ? 2 : 1)
            }
    }

    private func apply(_ target: Int) {
        guard hasSeededColumnCount else {
            hasSeededColumnCount = true
            columnCount = target
            return
        }
        guard target != columnCount else {
            return
        }
        withAnimation(RightPaneWidthPolicy.presentationAnimation) {
            columnCount = target
        }
    }
}
