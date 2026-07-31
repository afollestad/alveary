import AppKit
import SwiftUI

/// An `NSPopover` anchored to the view it is applied behind, for popovers whose
/// content must take keyboard focus.
///
/// SwiftUI's own `.popover` cannot: AppKit attaches a popover's window as a
/// *child* of the presenting window and keeps `NSApp.keyWindow` on the parent.
/// The child's `isKeyWindow` only mirrors the parent, so every focus and
/// `makeKey()` attempt reports success while key events keep routing to the
/// parent's first responder — a text field inside renders a caret and a
/// selection but never receives ⌘V or typing. Detaching the child relationship
/// before claiming key is what actually moves `NSApp.keyWindow`, and that is
/// only reachable with an `NSPopover` we own.
///
/// Apply through `appKitPopover(isPresented:preferredEdge:content:)` so the
/// anchor view inherits the presenting control's bounds.
struct AppKitAnchoredPopover<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let preferredEdge: NSRectEdge
    let content: () -> Content

    func makeNSView(context: Context) -> NSView {
        let view = PopoverAnchorView()
        context.coordinator.anchor = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isPresentedBinding = $isPresented
        context.coordinator.preferredEdge = preferredEdge
        context.coordinator.contentProvider = { AnyView(content()) }
        context.coordinator.synchronize(isPresented: isPresented)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismantle()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        var isPresentedBinding: Binding<Bool>?
        var preferredEdge: NSRectEdge = .maxY
        var contentProvider: (() -> AnyView)?
        weak var anchor: NSView?

        private var popover: NSPopover?
        private var hostingController: NSHostingController<AnyView>?
        private var resignKeyObserver: NSObjectProtocol?

        func synchronize(isPresented: Bool) {
            if isPresented {
                show()
            } else {
                close()
            }
        }

        func dismantle() {
            popover?.delegate = nil
            popover?.performClose(nil)
            clearPresentationState()
        }

        private func clearPresentationState() {
            if let resignKeyObserver {
                NotificationCenter.default.removeObserver(resignKeyObserver)
            }
            resignKeyObserver = nil
            popover = nil
            hostingController = nil
        }

        private func show() {
            guard let anchor, anchor.window != nil, let contentProvider else {
                return
            }
            // Already showing: refresh content so view-model updates (link
            // results, errors) reach the hosted tree.
            if let popover, popover.isShown {
                hostingController?.rootView = contentProvider()
                return
            }

            let hosting = NSHostingController(rootView: contentProvider())
            // The content sizes itself; let AppKit measure it rather than
            // pinning a size that would clip the error and link rows.
            hosting.sizingOptions = [.preferredContentSize]
            let popover = NSPopover()
            popover.contentViewController = hosting
            popover.behavior = .transient
            popover.delegate = self
            self.popover = popover
            hostingController = hosting

            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: preferredEdge)

            // The popover's window exists only after `show`, and AppKit has not
            // finished attaching it on this turn — the detach has to wait for
            // the next one or the parent link is re-established under it.
            DispatchQueue.main.async { [weak self, weak hosting] in
                guard let self, let window = hosting?.view.window else {
                    return
                }
                window.parent?.removeChildWindow(window)
                window.makeKeyAndOrderFront(nil)
                observeDismissal(of: window)
            }
        }

        /// Detaching the popover from its parent is what lets it take key, but it
        /// also takes it out of the parent's dismissal machinery: AppKit stops
        /// delivering `popoverDidClose` reliably, so the binding would stay
        /// `true` after the popover vanished and the next `true` write would be a
        /// no-op — the popover could then never reopen. Losing key is the
        /// dismissal signal for a transient popover, so drive teardown from that.
        private func observeDismissal(of window: NSWindow) {
            if let resignKeyObserver {
                NotificationCenter.default.removeObserver(resignKeyObserver)
            }
            resignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleDismissal()
                }
            }
        }

        private func handleDismissal() {
            popover?.delegate = nil
            popover?.performClose(nil)
            clearPresentationState()
            guard isPresentedBinding?.wrappedValue == true else {
                return
            }
            isPresentedBinding?.wrappedValue = false
        }

        private func close() {
            guard let popover, popover.isShown else {
                return
            }
            popover.performClose(nil)
        }

        func popoverDidClose(_ notification: Notification) {
            // Still wired for the cases AppKit does report; `observeDismissal`
            // covers the rest. Both funnel through one idempotent teardown.
            handleDismissal()
        }
    }

    /// Zero-cost anchor: it only supplies bounds, and must never intercept the
    /// clicks meant for the control it sits behind.
    ///
    /// Flipped so `preferredEdge` reads in screen terms — `.maxY` places the
    /// popover *below* the control. `NSPopover` resolves the edge in this view's
    /// coordinate space, so an unflipped anchor sends `.maxY` upward.
    private final class PopoverAnchorView: NSView {
        override var isFlipped: Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

extension View {
    /// Presents `content` in an `NSPopover` anchored to this view. Use instead of
    /// `.popover` when the content needs keyboard focus — see
    /// `AppKitAnchoredPopover`.
    ///
    /// `preferredEdge` is read in flipped coordinates, so the `.maxY` default puts
    /// the popover below the control.
    func appKitPopover<Content: View>(
        isPresented: Binding<Bool>,
        preferredEdge: NSRectEdge = .maxY,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        background {
            AppKitAnchoredPopover(
                isPresented: isPresented,
                preferredEdge: preferredEdge,
                content: content
            )
        }
    }
}
