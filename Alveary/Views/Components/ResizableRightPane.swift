import AppKit
import SwiftUI

struct ResizableRightPane<Destination: Hashable, MainContent: View, PaneContent: View>: View {
    let destination: Destination?
    @Binding var width: CGFloat
    let onWidthCommit: (CGFloat) -> Void
    let presentationGeneration: (Destination) -> UUID?
    let dismissalRequests: Set<RightPanePresentationIdentity<Destination>>
    let onDeactivate: (Destination, UUID) -> Void
    let onDismiss: (Destination, UUID) -> Void
    @ViewBuilder let mainContent: () -> MainContent
    @ViewBuilder let paneContent: (Destination, @escaping () -> Void) -> PaneContent

    @State private var displayedPresentation: RightPanePresentationIdentity<Destination>?
    @State private var displayedWidth: CGFloat?
    @State private var liveResizeWidth: CGFloat?
    @State private var presentationProgress: CGFloat
    @State private var pendingDismissal: RightPanePresentationIdentity<Destination>?
    @State private var hiddenPaneCleanup: UUID?
    @State private var resizeHandleActivation: UUID?
    @State private var isResizeHandleInteractive: Bool
    @State private var didInitializePresentation = false

    init(
        destination: Destination?,
        width: Binding<CGFloat>,
        onWidthCommit: @escaping (CGFloat) -> Void,
        presentationGeneration: @escaping (Destination) -> UUID?,
        dismissalRequests: Set<RightPanePresentationIdentity<Destination>> = [],
        onDeactivate: @escaping (Destination, UUID) -> Void = { _, _ in },
        onDismiss: @escaping (Destination, UUID) -> Void,
        @ViewBuilder mainContent: @escaping () -> MainContent,
        @ViewBuilder paneContent: @escaping (Destination, @escaping () -> Void) -> PaneContent
    ) {
        self.destination = destination
        _width = width
        self.onWidthCommit = onWidthCommit
        self.presentationGeneration = presentationGeneration
        self.dismissalRequests = dismissalRequests
        self.onDeactivate = onDeactivate
        self.onDismiss = onDismiss
        self.mainContent = mainContent
        self.paneContent = paneContent
        _displayedPresentation = State(initialValue: nil)
        _presentationProgress = State(initialValue: 0)
        _isResizeHandleInteractive = State(initialValue: false)
    }

    var body: some View {
        GeometryReader { proxy in
            let activePresentation = resolvedPresentation
            // A new non-nil route renders under its own identity immediately. The
            // stored presentation remains only long enough to animate an outgoing pane.
            let renderedPresentation = activePresentation ?? displayedPresentation
            let isRenderedPresentationSettled = activePresentation == renderedPresentation
                && displayedPresentation == renderedPresentation
            let bounds = RightPaneWidthPolicy.bounds(availableWidth: proxy.size.width)
            let activeEffectiveWidth = RightPaneWidthPolicy.effectiveWidth(
                storedWidth: width,
                availableWidth: proxy.size.width
            )
            let routedPaneWidth = activePresentation == nil
                ? displayedWidth ?? activeEffectiveWidth
                : activeEffectiveWidth
            let paneWidth = RightPaneWidthPolicy.effectiveWidth(
                storedWidth: liveResizeWidth ?? routedPaneWidth,
                availableWidth: proxy.size.width
            )
            RightPanePresentationLayout(
                paneWidth: paneWidth,
                presentationProgress: presentationProgress
            ) {
                mainContent()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .clipped()

                if let renderedPresentation {
                    HStack(spacing: 0) {
                        RightPaneResizeHandle(
                            width: resizeWidthBinding(
                                paneWidth: paneWidth,
                                presentation: renderedPresentation
                            ),
                            bounds: bounds,
                            isInteractionEnabled: isResizeHandleInteractive && isRenderedPresentationSettled,
                            onCommit: { committedWidth in
                                commitLiveResize(committedWidth, presentation: renderedPresentation)
                            }
                        )
                        .id(renderedPresentation)

                        paneContent(renderedPresentation.destination) {
                            dismiss(renderedPresentation)
                        }
                        .id(renderedPresentation)
                        .frame(width: paneWidth)
                    }
                    .frame(width: paneWidth + RightPaneWidthPolicy.resizeHandleThickness)
                    .allowsHitTesting(isRenderedPresentationSettled && pendingDismissal != renderedPresentation)
                    .accessibilityHidden(!isRenderedPresentationSettled || pendingDismissal == renderedPresentation)
                } else {
                    Color.clear
                }
            }
            .clipped()
            .onChange(of: activeEffectiveWidth, initial: true) { _, newWidth in
                guard activePresentation != nil, liveResizeWidth == nil else {
                    return
                }
                guard displayedWidth != newWidth else {
                    return
                }
                displayedWidth = newWidth
            }
            .onChange(of: activePresentation, initial: true) { _, newPresentation in
                if didInitializePresentation {
                    updatePresentation(presentation: newPresentation, width: activeEffectiveWidth)
                } else {
                    initializePresentation(presentation: newPresentation, width: activeEffectiveWidth)
                }
            }
            .onChange(of: dismissalRequests, initial: true) { _, requests in
                handleDismissalRequests(requests)
            }
            .task(id: pendingDismissal) {
                await completePendingDismissal()
            }
            .task(id: hiddenPaneCleanup) {
                await completeHiddenPaneCleanup()
            }
            .task(id: resizeHandleActivation) {
                await activateResizeHandleAfterPresentation()
            }
        }
    }

    private var resolvedPresentation: RightPanePresentationIdentity<Destination>? {
        guard let destination,
              let generation = presentationGeneration(destination) else {
            return nil
        }
        return RightPanePresentationIdentity(destination: destination, generation: generation)
    }

    private func dismiss(_ presentation: RightPanePresentationIdentity<Destination>) {
        guard resolvedPresentation == presentation,
              displayedPresentation == presentation,
              pendingDismissal != presentation else {
            return
        }

        beginDismissal(presentation)
    }

    private func beginDismissal(_ presentation: RightPanePresentationIdentity<Destination>) {
        guard displayedPresentation == presentation,
              pendingDismissal != presentation else {
            return
        }

        if let pendingDismissal {
            onDismiss(pendingDismissal.destination, pendingDismissal.generation)
        }
        deactivateResizeHandle()
        hiddenPaneCleanup = nil
        pendingDismissal = presentation
        onDeactivate(presentation.destination, presentation.generation)
        withAnimation(RightPaneWidthPolicy.presentationAnimation) {
            presentationProgress = 0
        }
    }

    private func handleDismissalRequests(
        _ requests: Set<RightPanePresentationIdentity<Destination>>
    ) {
        for request in requests {
            if displayedPresentation == request {
                beginDismissal(request)
            } else if resolvedPresentation != request {
                onDismiss(request.destination, request.generation)
            }
        }
    }

    private func resizeWidthBinding(
        paneWidth: CGFloat,
        presentation: RightPanePresentationIdentity<Destination>
    ) -> Binding<CGFloat> {
        Binding(
            get: { paneWidth },
            set: { newWidth in
                guard isResizeHandleInteractive,
                      RightPanePresentationPolicy.canResize(
                          active: resolvedPresentation,
                          displayed: displayedPresentation,
                          captured: presentation
                      ),
                      liveResizeWidth != newWidth else {
                    return
                }
                liveResizeWidth = newWidth
            }
        )
    }

    private func commitLiveResize(
        _ committedWidth: CGFloat,
        presentation: RightPanePresentationIdentity<Destination>
    ) {
        guard isResizeHandleInteractive,
              RightPanePresentationPolicy.canResize(
                  active: resolvedPresentation,
                  displayed: displayedPresentation,
                  captured: presentation
              ) else {
            liveResizeWidth = nil
            return
        }

        // Keep high-frequency drag updates local to this layout. Publishing through
        // ContentView on every mouse event rebuilds the full root view hierarchy.
        width = committedWidth
        displayedWidth = committedWidth
        liveResizeWidth = nil
        onWidthCommit(committedWidth)
    }

    private func updatePresentation(
        presentation: RightPanePresentationIdentity<Destination>?,
        width: CGFloat
    ) {
        liveResizeWidth = nil
        guard let presentation else {
            deactivateResizeHandle()
            guard displayedPresentation != nil else {
                hiddenPaneCleanup = nil
                presentationProgress = 0
                return
            }
            if pendingDismissal == displayedPresentation {
                hiddenPaneCleanup = nil
                return
            }
            hiddenPaneCleanup = UUID()
            withAnimation(RightPaneWidthPolicy.presentationAnimation) {
                presentationProgress = 0
            }
            return
        }

        let wasDismissing = hiddenPaneCleanup != nil
            || pendingDismissal != nil
            || presentationProgress < 1
        hiddenPaneCleanup = nil
        if RightPanePresentationPolicy.shouldCancelDismissal(
            active: presentation,
            pending: pendingDismissal
        ) {
            pendingDismissal = nil
        }
        let wasHidden = displayedPresentation == nil || presentationProgress == 0
        let wasPresenting = resizeHandleActivation != nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedPresentation = presentation
            displayedWidth = width
        }

        if dismissalRequests.contains(presentation) {
            beginDismissal(presentation)
            return
        }

        if wasHidden || wasPresenting || wasDismissing {
            scheduleResizeHandleActivation()
            withAnimation(RightPaneWidthPolicy.presentationAnimation) {
                presentationProgress = 1
            }
        } else {
            resizeHandleActivation = nil
            isResizeHandleInteractive = true
            presentationProgress = 1
        }
    }

    private func initializePresentation(
        presentation: RightPanePresentationIdentity<Destination>?,
        width: CGFloat
    ) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedPresentation = presentation
            displayedWidth = presentation == nil ? nil : width
            presentationProgress = presentation == nil ? 0 : 1
            isResizeHandleInteractive = presentation != nil
            didInitializePresentation = true
        }

        if let presentation, dismissalRequests.contains(presentation) {
            beginDismissal(presentation)
        }
    }

    private func scheduleResizeHandleActivation() {
        isResizeHandleInteractive = false
        resizeHandleActivation = UUID()
    }

    private func deactivateResizeHandle() {
        isResizeHandleInteractive = false
        resizeHandleActivation = nil
    }

    private func activateResizeHandleAfterPresentation() async {
        guard let activation = resizeHandleActivation else {
            return
        }

        do {
            try await Task.sleep(for: .seconds(RightPaneWidthPolicy.presentationDuration))
        } catch {
            return
        }
        guard !Task.isCancelled,
              resizeHandleActivation == activation,
              resolvedPresentation == displayedPresentation,
              pendingDismissal != displayedPresentation,
              displayedPresentation != nil else {
            return
        }

        isResizeHandleInteractive = true
        resizeHandleActivation = nil
    }

    private func completeHiddenPaneCleanup() async {
        // External routing hides without discarding the feature session, but the
        // rendered pane only needs to remain mounted until its slide-out completes.
        guard let cleanup = hiddenPaneCleanup else {
            return
        }

        do {
            try await Task.sleep(for: .seconds(RightPaneWidthPolicy.presentationDuration))
        } catch {
            return
        }
        guard !Task.isCancelled,
              hiddenPaneCleanup == cleanup,
              resolvedPresentation == nil,
              pendingDismissal != displayedPresentation else {
            return
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedPresentation = nil
            displayedWidth = nil
            liveResizeWidth = nil
            hiddenPaneCleanup = nil
        }
    }

    private func completePendingDismissal() async {
        guard let pendingDismissal else {
            return
        }

        do {
            try await Task.sleep(for: .seconds(RightPaneWidthPolicy.presentationDuration))
        } catch {
            return
        }
        guard !Task.isCancelled,
              self.pendingDismissal == pendingDismissal else {
            return
        }

        onDismiss(pendingDismissal.destination, pendingDismissal.generation)
        guard RightPanePresentationPolicy.shouldTearDown(
            displayed: displayedPresentation,
            completedDismissal: pendingDismissal
        ) else {
            self.pendingDismissal = nil
            return
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedPresentation = nil
            displayedWidth = nil
            liveResizeWidth = nil
            hiddenPaneCleanup = nil
            isResizeHandleInteractive = false
            resizeHandleActivation = nil
            self.pendingDismissal = nil
        }
    }
}
