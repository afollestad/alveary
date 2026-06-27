@preconcurrency import AppKit
import BlockInputKit
import QuartzCore

/// Non-view owner for Alveary's BlockInputKit composer bridge.
@MainActor
final class AppKitChatComposerEditorController {
    var bridgeController: BlockInputComposerBridgeController?
    var configuration: AppKitChatComposerBodyConfiguration?
    var measuredEditorHeight: CGFloat = AppKitChatComposerEditorController.editorBaseHeight
    var stopConfirmationResetTask: Task<Void, Never>?
    var onPreferredSizeInvalidated: ((Bool) -> Void)?
    private var lastConsumedFocusRequestToken: UUID?
    private var hasSeededInitialBlockInputHeight = false
    private var preferredHeightAnimationTimer: Timer?
    private var preferredHeightAnimationState: PreferredHeightAnimationState?

    func configure(_ configuration: AppKitChatComposerBodyConfiguration) {
        let previousConfiguration = self.configuration
        previousConfiguration?.onDraftSnapshotProviderChange(nil)
        if let previousConfiguration,
           previousConfiguration.draftIdentity != configuration.draftIdentity {
            bridgeController?.view.removeFromSuperview()
            bridgeController = nil
            lastConsumedFocusRequestToken = nil
            hasSeededInitialBlockInputHeight = false
            cancelPreferredHeightAnimation()
        }
        self.configuration = configuration

        let replacedDocument = configureBlockInput(configuration)
        installDraftSnapshotProvider(configuration)
        consumeFocusRequestIfNeeded(
            configuration.requestFirstResponder,
            focusesDocumentEnd: replacedDocument && !configuration.text.isEmpty
        )
        invalidatePreferredSize(animateSurfaceHeight: true)
    }

    func detach() {
        configuration?.onDraftSnapshotProviderChange(nil)
        cancelAsyncTasks()
    }

    func cancelAsyncTasks() {
        stopConfirmationResetTask?.cancel()
        stopConfirmationResetTask = nil
        cancelPreferredHeightAnimation()
    }
}

extension AppKitChatComposerEditorController {
    nonisolated static let editorHorizontalPadding: CGFloat = 14
    nonisolated static let editorVerticalPadding: CGFloat = 10
    nonisolated static let editorBaseHeight: CGFloat = 68
    nonisolated static let editorCornerRadius: CGFloat = AppCornerRadius.standard
    nonisolated static let borderWidth: CGFloat = 1
    nonisolated static let autocompleteVerticalOffset: CGFloat = 8
    nonisolated static let modalHorizontalOffset: CGFloat = 8
    nonisolated static let modalVerticalSpacing: CGFloat = 20
    nonisolated static let stopConfirmationTimeoutNanoseconds: UInt64 = 1_000_000_000
    nonisolated static let preferredHeightAnimationFrameInterval: TimeInterval = 1 / 60

    var view: BlockInputView? {
        bridgeController?.view
    }

    var topPadding: CGFloat {
        guard let configuration else {
            return 0
        }
        return configuration.hasQueuedMessages || configuration.hasTopContent || !configuration.attachments.isEmpty ?
            0 :
            ChatComposerPanelLayout.nativeInputTopPadding
    }

    var resolvedEditorHeight: CGFloat {
        max(0, measuredEditorHeight)
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        seedInitialBlockInputHeightIfPossible(width: width)
        return topPadding + resolvedEditorHeight
    }

    func editorFrame(origin: NSPoint, width: CGFloat) -> NSRect {
        seedInitialBlockInputHeightIfPossible(width: width)
        return NSRect(
            x: origin.x,
            y: origin.y + topPadding,
            width: width,
            height: resolvedEditorHeight
        )
    }

    func presentation(for configuration: AppKitChatComposerBodyConfiguration) -> ComposerPresentation {
        ComposerPresentation(
            text: configuration.text,
            isTextEffectivelyEmpty: configuration.isTextEffectivelyEmpty,
            mode: configuration.mode,
            defaultEnterBehavior: configuration.defaultEnterBehavior,
            supportsMidTurnSteering: configuration.supportsMidTurnSteering,
            canSteerCurrentTurn: configuration.canSteerCurrentTurn,
            isHandoffSteeringPromptActive: configuration.isHandoffSteeringPromptActive,
            isHandoffOutputPromptActive: configuration.isHandoffOutputPromptActive,
            handoffSteeringCountdown: configuration.handoffSteeringCountdown,
            sendCountdown: configuration.sendCountdown,
            isProjectTrustBlocked: configuration.isProjectTrustBlocked,
            isGoalModeArmed: configuration.isGoalModeArmed
        )
    }
}

extension AppKitChatComposerEditorController {
    func handlePreferredHeightTransition(_ transition: BlockInputEditorHeightTransition) {
        hasSeededInitialBlockInputHeight = true
        let nextHeight = max(0, ceil(transition.targetHeight))
        guard abs(measuredEditorHeight - nextHeight) > 0.5 else {
            cancelPreferredHeightAnimation()
            return
        }
        guard let animation = transition.animation,
              !transition.isInitial else {
            cancelPreferredHeightAnimation()
            applyPreferredEditorHeight(nextHeight)
            return
        }

        animatePreferredEditorHeight(to: nextHeight, animation: animation)
    }

    private func animatePreferredEditorHeight(to nextHeight: CGFloat, animation: BlockInputEditorHeightAnimation) {
        cancelPreferredHeightAnimation()
        let startHeight = measuredEditorHeight
        guard animation.duration > 0, abs(startHeight - nextHeight) > 0.5 else {
            applyPreferredEditorHeight(nextHeight)
            return
        }

        preferredHeightAnimationState = PreferredHeightAnimationState(
            startHeight: startHeight,
            targetHeight: nextHeight,
            startTime: CACurrentMediaTime(),
            duration: animation.duration,
            curve: animation.curve
        )

        let timer = Timer(timeInterval: Self.preferredHeightAnimationFrameInterval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                self.advancePreferredHeightAnimation()
            }
        }
        preferredHeightAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advancePreferredHeightAnimation() {
        guard let state = preferredHeightAnimationState else {
            preferredHeightAnimationTimer?.invalidate()
            return
        }

        let progress = min(1, max(0, (CACurrentMediaTime() - state.startTime) / state.duration))
        guard progress < 1 else {
            cancelPreferredHeightAnimation()
            applyPreferredEditorHeight(state.targetHeight)
            return
        }
        let easedProgress = state.curve.easedProgress(progress)
        let nextHeight = state.startHeight + (state.targetHeight - state.startHeight) * easedProgress
        applyPreferredEditorHeight(nextHeight)
    }

    private func cancelPreferredHeightAnimation() {
        preferredHeightAnimationTimer?.invalidate()
        preferredHeightAnimationTimer = nil
        preferredHeightAnimationState = nil
    }

    private func applyPreferredEditorHeight(_ nextHeight: CGFloat) {
        measuredEditorHeight = nextHeight
        view?.needsDisplay = true
        // BlockInputKit owns editor visible-line animation; the surface must
        // track each editor height frame immediately so controls stay pinned.
        invalidatePreferredSize(animateSurfaceHeight: false)
        layoutPreferredHeightHostIfNeeded(animateSurfaceHeight: false)
    }

    private func seedInitialBlockInputHeightIfPossible(width: CGFloat) {
        guard !hasSeededInitialBlockInputHeight,
              width > 0,
              let editor = view else {
            return
        }
        hasSeededInitialBlockInputHeight = true
        let preferredHeight = max(0, ceil(editor.preferredHeight(forWidth: width)))
        guard abs(measuredEditorHeight - preferredHeight) > 0.5 else {
            return
        }
        measuredEditorHeight = preferredHeight
        view?.needsDisplay = true
        invalidatePreferredSize(animateSurfaceHeight: false)
    }

    private func layoutPreferredHeightHostIfNeeded(animateSurfaceHeight: Bool) {
        if let surface = enclosingChatSurfaceView() {
            surface.layoutPreferredComposerHeightChange(animated: animateSurfaceHeight)
        } else if let parent = view?.superview {
            parent.layoutSubtreeIfNeeded()
        } else {
            view?.layoutSubtreeIfNeeded()
        }
    }

    func invalidatePreferredSize(animateSurfaceHeight: Bool) {
        view?.invalidateIntrinsicContentSize()
        view?.needsLayout = true
        view?.superview?.needsLayout = true
        onPreferredSizeInvalidated?(animateSurfaceHeight)
    }

    func consumeFocusRequest(_ token: UUID?) {
        configuration?.onFocusRequestConsumed(token)
    }

    func consumeFocusRequestIfNeeded(_ token: UUID?, focusesDocumentEnd: Bool = false) {
        guard let token,
              token != lastConsumedFocusRequestToken else {
            return
        }
        lastConsumedFocusRequestToken = token
        focusBlockInputWhenReady(token: token, focusesDocumentEnd: focusesDocumentEnd, attempt: 0)
    }

    private func focusBlockInputWhenReady(token: UUID, focusesDocumentEnd: Bool, attempt: Int) {
        guard configuration?.requestFirstResponder == token,
              view != nil else {
            return
        }
        guard view?.window != nil else {
            guard attempt < 4 else {
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.focusBlockInputWhenReady(
                    token: token,
                    focusesDocumentEnd: focusesDocumentEnd,
                    attempt: attempt + 1
                )
            }
            return
        }

        if focusesDocumentEnd {
            bridgeController?.focusEditorAtDocumentEnd()
        } else {
            view?.focusEditor()
        }
        consumeFocusRequest(token)
    }
}

private struct PreferredHeightAnimationState {
    let startHeight: CGFloat
    let targetHeight: CGFloat
    let startTime: CFTimeInterval
    let duration: TimeInterval
    let curve: BlockInputEditorHeightAnimationCurve
}

private extension BlockInputEditorHeightAnimationCurve {
    func easedProgress(_ progress: TimeInterval) -> CGFloat {
        let progress = CGFloat(min(1, max(0, progress)))
        switch self {
        case .easeInOut:
            return progress * progress * (3 - 2 * progress)
        case .easeIn:
            return progress * progress
        case .easeOut:
            let remaining = 1 - progress
            return 1 - remaining * remaining
        case .linear:
            return progress
        }
    }
}
