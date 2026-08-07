import SwiftUI

/// Hosts a tabbed pane's content so a visited tab survives being deselected, which is
/// what preserves its scroll offsets, prepared row models, and per-card expansion across
/// a tab switch. A `switch` over the selection compiles to `_ConditionalContent`, which
/// tears the outgoing tab down and rebuilds the incoming one from scratch.
///
/// Tabs mount lazily — an unvisited tab costs nothing — and hidden ones are removed from
/// every input surface. Hiding is a rendering concern, so content that reaches input
/// through AppKit (an `NSEvent` monitor, first-responder claims) must gate itself on
/// ``EnvironmentValues/keepAliveTabIsActive`` instead.
///
/// Deliberately not `Equatable`, unlike the pane children around it: re-running this
/// body is how a session write reaches the mounted tabs, so freezing it would strand the
/// pane on stale content. Keep the memoization boundary on the tab views themselves,
/// applying `.equatable()` inside `content` so the hide below stays outside it — tabs
/// routinely compare equal across a switch, which is exactly when their rendered output
/// gets reused.
struct KeepAliveTabContainer<Tab: Hashable, Content: View>: View {
    let tabs: [Tab]
    let selection: Tab
    @ViewBuilder let content: (Tab) -> Content

    @State private var mountedTabs: Set<Tab>

    /// - Parameter initiallyMounted: Tabs to mount before they are first selected. Only
    ///   snapshot hosts need this; production callers let visits do the mounting.
    init(
        tabs: [Tab],
        selection: Tab,
        initiallyMounted: Set<Tab> = [],
        @ViewBuilder content: @escaping (Tab) -> Content
    ) {
        self.tabs = tabs
        self.selection = selection
        self.content = content
        _mountedTabs = State(initialValue: initiallyMounted.union([selection]))
    }

    var body: some View {
        ZStack {
            ForEach(tabs, id: \.self) { tab in
                // The selection check also covers the pass that selects a tab for the
                // first time, which lands before `onChange` records it as mounted.
                if tab == selection || mountedTabs.contains(tab) {
                    content(tab)
                        .environment(\.keepAliveTabIsActive, tab == selection)
                        .modifier(KeepAliveInactiveTabModifier(isHidden: tab != selection))
                        // Without this the stack order is the tab order, so a later
                        // tab's fully transparent layer composites over the visible
                        // one. Keep the selected tab on top.
                        .zIndex(tab == selection ? 1 : 0)
                }
            }
        }
        .onChange(of: selection) { _, newSelection in
            mountedTabs.insert(newSelection)
        }
    }
}

private struct KeepAliveInactiveTabModifier: ViewModifier {
    let isHidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isHidden ? 0 : 1)
            .allowsHitTesting(!isHidden)
            .disabled(isHidden)
            .accessibilityHidden(isHidden)
    }
}

private struct KeepAliveTabIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the enclosing ``KeepAliveTabContainer`` tab is the selected one. Defaults
    /// to `true` so content hosted outside a container — snapshot fixtures, previews, the
    /// panes that never adopted one — behaves as active.
    var keepAliveTabIsActive: Bool {
        get { self[KeepAliveTabIsActiveKey.self] }
        set { self[KeepAliveTabIsActiveKey.self] = newValue }
    }
}
