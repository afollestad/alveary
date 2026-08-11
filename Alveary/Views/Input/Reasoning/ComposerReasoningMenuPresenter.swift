@preconcurrency import AppKit

/// Owns the reasoning popover's lifecycle so every surface that offers model/effort controls presents
/// it identically. The composer action row and the `ExitPlanMode` overlay both host one of these; the
/// mechanics — transient behavior, suppressed animation, anchor reuse on resize, close bookkeeping —
/// must not drift between them.
@MainActor
final class ComposerReasoningMenuPresenter: NSObject {
    /// The upward edge for a non-flipped anchor; `upwardEdge(for:)` is the general form.
    static let preferredEdge: NSRectEdge = .maxY

    /// The menu always opens above its anchor. `NSPopover` edges are anchor-relative, so "up" is
    /// `.maxY` for a non-flipped anchor (the action row) but `.minY` for a flipped one (the overlay
    /// panel) — a hardcoded `.maxY` would open the overlay's menu downward over the footer.
    static func upwardEdge(for anchorView: NSView) -> NSRectEdge {
        anchorView.isFlipped ? .minY : .maxY
    }

    /// Testing seams. `AlvearyTests/AGENTS.md` forbids live `NSPopover` host tests on macOS 26, and this
    /// popover resizes itself on disclosure expansion — exactly the pattern that crashes there.
    var isPresentedOverride: (() -> Bool)?
    var presentationOverride: (() -> Void)?
    var effortFocusOverride: (() -> Void)?
    var modelsFocusOverride: (() -> Void)?

    /// Settable so tests can install a recording popover/controller without showing a live one.
    var popover: NSPopover?
    var controller: ComposerReasoningMenuViewController?
    var anchorRect: NSRect?
    weak var anchorView: NSView?
    /// Captured at presentation; the resize re-`show` must reuse the same edge or AppKit could flip
    /// the menu to the opposite side of the anchor mid-interaction.
    private var presentedEdge: NSRectEdge = ComposerReasoningMenuPresenter.preferredEdge

    private let onDisplaySelectionChanged: (ChatComposerActionRowView.ReasoningSelection?) -> Void
    private let onClosed: () -> Void

    init(
        onDisplaySelectionChanged: @escaping (ChatComposerActionRowView.ReasoningSelection?) -> Void,
        onClosed: @escaping () -> Void = {}
    ) {
        self.onDisplaySelectionChanged = onDisplaySelectionChanged
        self.onClosed = onClosed
    }

    var isShown: Bool { popover?.isShown == true }

    func toggle(
        configuration: ChatComposerActionRowView.ReasoningConfiguration,
        anchorView: NSView,
        anchorRect: NSRect
    ) {
        if isShown {
            close()
            return
        }
        present(configuration: configuration, anchorView: anchorView, anchorRect: anchorRect)
    }

    func present(
        configuration: ChatComposerActionRowView.ReasoningConfiguration,
        anchorView: NSView,
        anchorRect: NSRect
    ) {
        if isPresentedOverride?() == true {
            return
        }
        if let popover {
            guard !popover.isShown else {
                return
            }
            finishClose(for: popover)
        }
        if let presentationOverride {
            presentationOverride()
            return
        }

        let controller = ComposerReasoningMenuViewController(
            configuration: configuration,
            onRequestCloseMainMenu: { [weak self] in
                self?.close()
            },
            onDisplaySelectionChanged: { [weak self] selection in
                self?.onDisplaySelectionChanged(selection)
            },
            onContentSizeChanged: { [weak self] size in
                self?.applyContentSize(size)
            }
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = controller
        popover.contentSize = controller.preferredContentSize
        self.controller = controller
        self.popover = popover
        self.anchorRect = anchorRect
        self.anchorView = anchorView
        presentedEdge = Self.upwardEdge(for: anchorView)
        popover.show(relativeTo: anchorRect, of: anchorView, preferredEdge: presentedEdge)
        controller.alignContentViewToPopoverHost()
    }

    func focusEffortControl() {
        if let effortFocusOverride {
            effortFocusOverride()
            return
        }
        controller?.focusEffortControl()
    }

    func focusModelList() {
        if let modelsFocusOverride {
            modelsFocusOverride()
            return
        }
        // Expands the disclosure and moves focus into the list; rows build synchronously on
        // first expansion, so they are focusable as soon as this returns.
        controller?.focusModelList()
    }

    func update(configuration: ChatComposerActionRowView.ReasoningConfiguration) {
        controller?.update(configuration: configuration)
    }

    func close() {
        guard let popover else {
            onDisplaySelectionChanged(nil)
            onClosed()
            return
        }
        popover.animates = false
        popover.performClose(nil)
        finishClose(for: popover)
    }

    @discardableResult
    func finishClose(for popover: NSPopover) -> Bool {
        guard self.popover === popover else {
            return false
        }
        popover.animates = false
        controller?.cancelEffortPreview()
        popover.delegate = nil
        self.popover = nil
        anchorRect = nil
        anchorView = nil
        controller = nil
        // Reconfigure the host back to its persisted selection; a lingering display override would
        // otherwise stay painted until an unrelated configuration change.
        onDisplaySelectionChanged(nil)
        onClosed()
        return true
    }

    func applyContentSize(_ size: NSSize) {
        guard let popover,
              let controller,
              popover.contentViewController === controller else {
            return
        }
        popover.animates = false
        popover.contentSize = size
        if popover.isShown,
           let anchorRect,
           let anchorView {
            // Resizing a shown popover can make AppKit reconsider its edge. Reapply the captured
            // anchor and original preference so collapse stays on the same side of the composer.
            popover.show(relativeTo: anchorRect, of: anchorView, preferredEdge: presentedEdge)
        }
        controller.alignContentViewToPopoverHost()
    }
}

extension ComposerReasoningMenuPresenter: NSPopoverDelegate {
    func popoverWillClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
              popover === self.popover else {
            return
        }
        popover.animates = false
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover else {
            return
        }
        finishClose(for: popover)
    }
}
