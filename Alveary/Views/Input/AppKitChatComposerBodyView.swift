@preconcurrency import AppKit
import BlockInputKit
import QuartzCore
import SwiftUI

/// Native production composer body that mounts the BlockInputKit editor inside
/// Alveary's composer shell.
///
/// Active chat surfaces configure this view through
/// `AppKitChatComposerPanelView` so editor measurement stays on the native
/// AppKit path.
@MainActor
final class AppKitChatComposerBodyView: NSView {
    let editorClipView = AppKitComposerEditorClipView()
    var bridgeController: BlockInputComposerBridgeController?

    var configuration: AppKitChatComposerBodyConfiguration?
    var measuredEditorHeight: CGFloat = AppKitChatComposerBodyView.editorBaseHeight
    var stopConfirmationResetTask: Task<Void, Never>?
    var onPreferredSizeInvalidated: (() -> Void)?
    private var lastConsumedFocusRequestToken: UUID?

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(width: bounds.width))
    }

    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(width: bounds.width))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        stopConfirmationResetTask?.cancel()
    }

    func configure(_ configuration: AppKitChatComposerBodyConfiguration) {
        let previousConfiguration = self.configuration
        previousConfiguration?.onDraftSnapshotProviderChange(nil)
        if let previousConfiguration,
           previousConfiguration.draftIdentity != configuration.draftIdentity {
            bridgeController?.view.removeFromSuperview()
            bridgeController = nil
            lastConsumedFocusRequestToken = nil
        }
        self.configuration = configuration

        configureBlockInput(configuration)
        installDraftSnapshotProvider(configuration)
        consumeFocusRequestIfNeeded(configuration.requestFirstResponder)
        needsLayout = true
        needsDisplay = true
        invalidatePreferredSize()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil else {
            return
        }
        configuration?.onDraftSnapshotProviderChange(nil)
        cancelAsyncTasks()
    }

    func cancelAsyncTasks() {
        stopConfirmationResetTask?.cancel()
        stopConfirmationResetTask = nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let editorHeight = resolvedEditorHeight
        editorClipView.frame = NSRect(x: 0, y: topPadding, width: bounds.width, height: editorHeight)
        editorClipView.configure(
            radius: Self.editorCornerRadius,
            squaresTopCorners: configuration?.hasQueuedMessages == true
        )
        bridgeController?.view.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: editorHeight
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }
        return super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let editorRect = NSRect(x: 0, y: topPadding, width: bounds.width, height: resolvedEditorHeight)
        let path = NSBezierPath.appKitComposerEditorPath(
            in: editorRect.insetBy(dx: Self.borderWidth / 2, dy: Self.borderWidth / 2),
            radius: Self.editorCornerRadius,
            squaresTopCorners: configuration?.hasQueuedMessages == true
        )

        appKitComposerSecondaryColor(in: self, opacity: 0.08).setFill()
        path.fill()

        appKitComposerSecondaryColor(in: self, opacity: 0.18).setStroke()
        path.lineWidth = Self.borderWidth
        path.stroke()
    }

    private func setup() {
        wantsLayer = true
        addSubview(editorClipView)
    }

}

final class AppKitComposerEditorClipView: NSView {
    private let maskLayer = CAShapeLayer()
    private var radius: CGFloat = 0
    private var squaresTopCorners = false

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(radius: CGFloat, squaresTopCorners: Bool) {
        guard self.radius != radius || self.squaresTopCorners != squaresTopCorners else {
            updateMask()
            return
        }
        self.radius = radius
        self.squaresTopCorners = squaresTopCorners
        updateMask()
    }

    override func layout() {
        super.layout()
        updateMask()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.mask = maskLayer
    }

    private func updateMask() {
        guard bounds.width > 0, bounds.height > 0 else {
            maskLayer.path = nil
            return
        }
        maskLayer.frame = bounds
        maskLayer.path = NSBezierPath.appKitComposerEditorPath(
            in: bounds,
            radius: radius,
            squaresTopCorners: squaresTopCorners
        ).cgPath
    }
}

extension AppKitChatComposerBodyView {
    nonisolated static let editorHorizontalPadding: CGFloat = 10
    nonisolated static let editorVerticalPadding: CGFloat = 10
    nonisolated static let editorBaseHeight: CGFloat = 68
    nonisolated static let editorCornerRadius: CGFloat = 18
    nonisolated static let borderWidth: CGFloat = 1
    nonisolated static let stopConfirmationTimeoutNanoseconds: UInt64 = 1_000_000_000

    var topPadding: CGFloat {
        guard let configuration else {
            return 0
        }
        return configuration.hasQueuedMessages || configuration.hasTopContent ? 0 : ChatComposerPanelLayout.nativeInputTopPadding
    }

    var resolvedEditorHeight: CGFloat {
        max(0, measuredEditorHeight)
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        topPadding + resolvedEditorHeight
    }

    func presentation(for configuration: AppKitChatComposerBodyConfiguration) -> ComposerPresentation {
        ComposerPresentation(
            text: configuration.text,
            isTextEffectivelyEmpty: configuration.isTextEffectivelyEmpty,
            mode: configuration.mode,
            defaultEnterBehavior: configuration.defaultEnterBehavior,
            supportsMidTurnSteering: configuration.supportsMidTurnSteering,
            isHandoffSteeringPromptActive: configuration.isHandoffSteeringPromptActive,
            isHandoffOutputPromptActive: configuration.isHandoffOutputPromptActive,
            handoffSteeringCountdown: configuration.handoffSteeringCountdown,
            sendCountdown: configuration.sendCountdown,
            isProjectTrustBlocked: configuration.isProjectTrustBlocked
        )
    }

    func handlePreferredHeightChange(_ height: CGFloat) {
        let nextHeight = max(0, ceil(height))
        guard abs(measuredEditorHeight - nextHeight) > 0.5 else {
            return
        }
        measuredEditorHeight = nextHeight
        invalidatePreferredSize()
    }

    func consumeFocusRequest(_ token: UUID?) {
        configuration?.onFocusRequestConsumed(token)
    }

    func consumeFocusRequestIfNeeded(_ token: UUID?) {
        guard let token,
              token != lastConsumedFocusRequestToken else {
            return
        }
        lastConsumedFocusRequestToken = token
        focusBlockInputWhenReady(token: token, attempt: 0)
    }

    private func focusBlockInputWhenReady(token: UUID, attempt: Int) {
        guard configuration?.requestFirstResponder == token,
              bridgeController != nil else {
            return
        }
        guard window != nil else {
            guard attempt < 4 else {
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.focusBlockInputWhenReady(token: token, attempt: attempt + 1)
            }
            return
        }

        bridgeController?.view.focusEditor()
        consumeFocusRequest(token)
    }

    func invalidatePreferredSize() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        superview?.needsLayout = true
        onPreferredSizeInvalidated?()
    }
}

private extension NSBezierPath {
    /// Builds the editor outline used by the native composer body.
    ///
    /// Queued messages sit directly above the editor as part of one visual
    /// control, so the editor's top corners are squared only in that state.
    static func appKitComposerEditorPath(
        in rect: NSRect,
        radius: CGFloat,
        squaresTopCorners: Bool
    ) -> NSBezierPath {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        guard squaresTopCorners else {
            return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        }

        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - radius))
        path.curve(
            to: NSPoint(x: rect.maxX - radius, y: rect.maxY),
            controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY - radius * 0.45),
            controlPoint2: NSPoint(x: rect.maxX - radius * 0.45, y: rect.maxY)
        )
        path.line(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
        path.curve(
            to: NSPoint(x: rect.minX, y: rect.maxY - radius),
            controlPoint1: NSPoint(x: rect.minX + radius * 0.45, y: rect.maxY),
            controlPoint2: NSPoint(x: rect.minX, y: rect.maxY - radius * 0.45)
        )
        path.close()
        return path
    }
}
