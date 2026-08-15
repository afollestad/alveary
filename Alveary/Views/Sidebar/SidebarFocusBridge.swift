import SwiftUI

/// Mounts `SidebarView` beneath the window's one sidebar-side focused-value reader.
///
/// Focused-value re-resolution re-runs every view that *declares* a `@FocusedValue` — and macOS
/// re-resolves once per frame of any presentation or removal animation (a confirmation dialog
/// dismissing, a `List` row animating out), because the value's closures can never prove
/// themselves unchanged. When `SidebarView` declared this wrapper itself, each of those frames
/// rebuilt the whole sidebar — snapshot, rows, drag order — which is exactly the delete-lag
/// stutter. Declaring it here instead makes the per-frame body this one-line view; `SidebarView`'s
/// stored value stays equal, so SwiftUI skips its subtree entirely.
///
/// The handle lands in a `SidebarComposerFocusRelay` the sidebar reads at event time. See
/// **Focus And Keyboard Coordination** in `Alveary/Views/AGENTS.md` for the claim/release
/// contract this carries.
struct SidebarFocusBridge: View {
    let viewModel: SidebarViewModel
    let appState: AppState
    let voiceInputLifecycleController: VoiceInputLifecycleController?

    @FocusedValue(\.chatComposerFocus) private var chatComposerFocus
    @State private var composerFocusRelay = SidebarComposerFocusRelay()

    var body: some View {
        // A plain box write, deliberately not `.onChange`: nothing observes the relay, so
        // refreshing it per body run costs nothing, and the sidebar always reads the newest
        // handle without this view needing to know when presence changed.
        composerFocusRelay.handle = chatComposerFocus
        // `.equatable()` is what makes the skip real — without it SwiftUI cannot prove the
        // non-POD `SidebarView` value unchanged and re-runs it anyway, per the same root
        // memoization pattern `MiddlePane` documents.
        return SidebarView(
            viewModel: viewModel,
            appState: appState,
            voiceInputLifecycleController: voiceInputLifecycleController,
            composerFocusRelay: composerFocusRelay
        )
        .equatable()
    }
}

/// The composer-focus handle, held behind a stable reference so `SidebarView` can call
/// `release()` from event handlers without being a focused-value reader itself. `@MainActor`
/// keeps it `Sendable` for `SidebarView`'s nonisolated `==`.
@MainActor
final class SidebarComposerFocusRelay {
    var handle: ChatComposerFocusHandle?
}
