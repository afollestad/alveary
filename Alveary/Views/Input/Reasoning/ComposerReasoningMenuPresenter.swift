@preconcurrency import AppKit

/// Owns the reasoning popover's lifecycle so every surface that offers model/effort controls presents
/// it identically. The composer action row, the `ExitPlanMode` overlay, and `SettingsAgentSelector` each
/// host one of these; the mechanics — transient behavior, suppressed animation, one-time placement,
/// anchor reuse on resize, close bookkeeping — must not drift between them.
@MainActor
final class ComposerReasoningMenuPresenter: NSObject {
    /// Composer hosts open the menu above their anchor, away from the window's bottom edge; a settings
    /// field opens it below, like the menu pickers beside it.
    enum Direction {
        case above
        case below
    }

    /// The upward edge for a non-flipped anchor; `upwardEdge(for:)` is the general form.
    static let preferredEdge: NSRectEdge = .maxY

    /// `NSPopover` edges are anchor-relative, so "up" is `.maxY` for a non-flipped anchor (the action
    /// row) but `.minY` for a flipped one (the overlay panel) — a hardcoded `.maxY` would open the
    /// overlay's menu downward over the footer.
    static func upwardEdge(for anchorView: NSView) -> NSRectEdge {
        anchorView.isFlipped ? .minY : .maxY
    }

    static func downwardEdge(for anchorView: NSView) -> NSRectEdge {
        anchorView.isFlipped ? .maxY : .minY
    }

    static func edge(_ direction: Direction, for anchorView: NSView) -> NSRectEdge {
        switch direction {
        case .above:
            upwardEdge(for: anchorView)
        case .below:
            downwardEdge(for: anchorView)
        }
    }

    /// Where a presentation opens and how tall its content may grow; both are fixed until it closes.
    struct Placement: Equatable {
        let direction: Direction
        let maximumContentHeight: CGFloat?
    }

    /// AppKit moves a shown popover to the anchor's other side whenever a resize outgrows its room, so expanding
    /// Models could flip it mid-interaction. Deciding once avoids that: the popover keeps its preferred side and caps
    /// its height to that side's room, where the model list scrolls, unless a few rows cannot fit there but can on the
    /// other side.
    static func placement(
        preferring direction: Direction,
        anchorOnScreen anchor: NSRect,
        visibleFrame screen: NSRect,
        minimumContentHeight: CGFloat
    ) -> Placement {
        let allowance = ComposerReasoningMenuMetrics.popoverScreenAllowance
        let roomAbove = screen.maxY - anchor.maxY - allowance
        let roomBelow = anchor.minY - screen.minY - allowance
        let (preferredRoom, otherRoom) = direction == .above ? (roomAbove, roomBelow) : (roomBelow, roomAbove)
        guard preferredRoom < minimumContentHeight, otherRoom > preferredRoom else {
            return Placement(direction: direction, maximumContentHeight: preferredRoom)
        }
        return Placement(direction: direction == .above ? .below : .above, maximumContentHeight: otherRoom)
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

    private let direction: Direction
    private let onDisplaySelectionChanged: (ReasoningSelection?) -> Void
    private let onClosed: () -> Void

    init(
        direction: Direction = .above,
        onDisplaySelectionChanged: @escaping (ReasoningSelection?) -> Void,
        onClosed: @escaping () -> Void = {}
    ) {
        self.direction = direction
        self.onDisplaySelectionChanged = onDisplaySelectionChanged
        self.onClosed = onClosed
    }

    var isShown: Bool { popover?.isShown == true }

    /// The preferred edge; `placement(preferring:anchorOnScreen:visibleFrame:minimumContentHeight:)` may take the other.
    func presentationEdge(for anchorView: NSView) -> NSRectEdge {
        Self.edge(direction, for: anchorView)
    }

    func toggle(
        configuration: ReasoningConfiguration,
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
        configuration: ReasoningConfiguration,
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

        let placement = placement(for: configuration, anchorView: anchorView, anchorRect: anchorRect)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration,
            maximumContentHeight: placement.maximumContentHeight,
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
        presentedEdge = Self.edge(placement.direction, for: anchorView)
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

    func update(configuration: ReasoningConfiguration) {
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
            // anchor and original preference so collapse stays on the same side of the anchor.
            popover.show(relativeTo: anchorRect, of: anchorView, preferredEdge: presentedEdge)
        }
        controller.alignContentViewToPopoverHost()
    }
}

private extension ComposerReasoningMenuPresenter {
    func placement(for configuration: ReasoningConfiguration, anchorView: NSView, anchorRect: NSRect) -> Placement {
        guard let window = anchorView.window else {
            return Placement(direction: direction, maximumContentHeight: nil)
        }
        let anchor = window.convertToScreen(anchorView.convert(anchorRect, to: nil))
        let anchorCenter = NSPoint(x: anchor.midX, y: anchor.midY)
        // A window spanning displays reports the one holding most of it, not necessarily the anchor's.
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorCenter) }) ?? window.screen else {
            return Placement(direction: direction, maximumContentHeight: nil)
        }
        return Self.placement(
            preferring: direction,
            anchorOnScreen: anchor,
            visibleFrame: screen.visibleFrame,
            minimumContentHeight: ComposerReasoningMenuMetrics.minimumExpandedContentHeight(for: configuration)
        )
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
