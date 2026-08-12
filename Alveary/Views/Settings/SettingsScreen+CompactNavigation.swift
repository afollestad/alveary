import SwiftUI

/// Width of the trailing sentinel closing the scrollable chip content. Matches the leading
/// inset so scrolling to the end leaves the last chip the same breathing room the first one
/// gets at rest, and is subtracted from the divider's overflow math because that last stretch
/// of scroll is the sentinel rather than a chip.
private let compactNavigationSentinelWidth = SettingsScreenLayout.settingsContentInset

/// One page in the compact navigation strip, carrying an already-resolved title because
/// `AppSettings.SettingsPage.title` is file-private to `SettingsScreen.swift`.
struct SettingsScreenCompactNavigationItem: Identifiable, Equatable {
    let page: AppSettings.SettingsPage
    let title: String

    var id: AppSettings.SettingsPage { page }
}

/// The settings navigation for panes too narrow to hold the side list.
///
/// It scrolls rather than clips. This replaced a segmented `Picker`, and an `NSSegmentedControl`
/// neither scrolls nor wraps, so a narrow pane cut the later pages off entirely — including the
/// selected page's own chip, leaving it unreachable in its own navigation. Layout follows the
/// conversation-tab and terminal-session strips (`Alveary/Views/Chat/ConversationTabs/AGENTS.md`
/// owns the shared scroll-hook rules).
///
/// Deliberately unkeyed by selection, unlike the pull-request and diff-viewer chip rows: those
/// sit above a `KeepAliveTabContainer`, where a switch changes nothing structural and
/// `TabChipButtonStyle`'s rendered output survives. `SettingsScreen` switches its detail on a
/// plain `switch`, and `.id(selection)` here would discard the scroll offset and geometry state
/// on every chip click.
struct SettingsScreenCompactNavigation: View, Equatable {
    let items: [SettingsScreenCompactNavigationItem]
    let selection: AppSettings.SettingsPage
    let onSelect: (AppSettings.SettingsPage) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var scrollGeometry = SettingsCompactNavigationScrollGeometry()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // The outer HStack hosts the sentinel as its own view so it is part of the
                // scrollable content: a `.padding(.trailing)` on the chip row instead would
                // sit past every scroll target, leaving the last chip butted against the edge.
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        ForEach(items) { item in
                            PaneFilterChip(
                                title: item.title,
                                isSelected: item.page == selection,
                                onSelect: { onSelect(item.page) }
                            )
                            .id(item.page)
                        }
                    }
                    // Inside the scrollable content, so chips scroll past the pane's visible
                    // leading edge while the first one still lines up with the detail header
                    // below it at rest.
                    .padding(.leading, SettingsScreenLayout.settingsContentInset)

                    Color.clear
                        .frame(width: compactNavigationSentinelWidth, height: 1)
                        .id(ScrollTarget.trailingSentinel)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .onScrollGeometryChange(for: SettingsCompactNavigationScrollGeometry.self) { geometry in
                SettingsCompactNavigationScrollGeometry(
                    contentWidth: geometry.contentSize.width,
                    containerWidth: geometry.containerSize.width,
                    contentOffset: geometry.contentOffset.x
                )
            } action: { _, newValue in
                scrollGeometry = newValue
            }
            .overlay(alignment: .trailing) {
                if scrollGeometry.hasChipsBehindTrailingEdge {
                    Rectangle()
                        .fill(dividerColor)
                        .frame(width: 1, height: 18)
                        .accessibilityHidden(true)
                }
            }
            // `initial: true` is what makes settings opened straight onto a late page — a
            // `targetPage` route, or a restored `lastSettingsPage` — mount with that chip
            // visible. A `nil` anchor is minimum-scroll-to-visible, so clicking an already
            // visible chip does not jog the row; only the last page needs the sentinel, whose
            // trailing edge is the content's, to keep its end gap on screen.
            .onChange(of: selection, initial: true) { _, newSelection in
                if items.last?.page == newSelection {
                    proxy.scrollTo(ScrollTarget.trailingSentinel, anchor: .trailing)
                } else {
                    proxy.scrollTo(newSelection)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings section")
        .accessibilityValue(selectedTitle)
    }

    /// Excludes `onSelect`. It captures only `SettingsScreen`'s own `selectPage(_:)` — whose
    /// captures are the screen's `@State` storage and its view model, both stable for the
    /// screen's lifetime — so `items` and `selection` cover everything this renders. The
    /// conformance earns its keep because the strip is built inside `SettingsScreen`'s
    /// `GeometryReader`, which re-runs every frame of a resize or right-pane slide.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.items == rhs.items && lhs.selection == rhs.selection
    }
}

private extension SettingsScreenCompactNavigation {
    var selectedTitle: String {
        items.first { $0.page == selection }?.title ?? ""
    }

    /// Matched to the conversation-tab and terminal-pane dividers so the three strips read the
    /// same way.
    var dividerColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.35 : 0.3)
    }
}

/// Snapshot of the strip's scroll state, published by `onScrollGeometryChange` so the trailing
/// divider can gate on whether chips remain off-screen to the right.
///
/// Internal rather than private so `SettingsScreenCompactNavigationTests` can cover the gating
/// math directly. No snapshot can reach it — scroll geometry publishes after a baseline displays
/// — and the one defect this surface needed a running app to catch lived exactly here.
struct SettingsCompactNavigationScrollGeometry: Equatable {
    var contentWidth: CGFloat = 0
    var containerWidth: CGFloat = 0
    var contentOffset: CGFloat = 0

    /// `true` while a chip is clipped by the trailing edge. Subtracting the sentinel from the
    /// scrollable distance hides the divider as soon as the last *chip* is fully visible,
    /// rather than holding it while the sentinel alone scrolls in, and avoids a false positive
    /// when the chips fit and only the sentinel overflows.
    ///
    /// **Compare the distance scrolled, not the raw offset.** This strip's `contentOffset.x`
    /// runs 0 at rest to *minus* the scrollable distance at the end, so the raw value sits below
    /// any positive threshold at every position and pinned the divider on permanently. Taking
    /// the magnitude reads the same at either sign convention and absorbs rubber-band overscroll
    /// past both ends. The conversation-tab and terminal-session strips compare the raw offset;
    /// do not "restore" that here without re-checking the sign in the running app.
    var hasChipsBehindTrailingEdge: Bool {
        let maxScroll = max(0, contentWidth - containerWidth)
        let effectiveMaxScroll = maxScroll - compactNavigationSentinelWidth
        return effectiveMaxScroll > 0.5
            && abs(contentOffset) < effectiveMaxScroll - 0.5
    }
}

/// `ScrollViewProxy` targets that are not a page. Chips use their own `SettingsPage`.
private enum ScrollTarget: Hashable {
    case trailingSentinel
}
