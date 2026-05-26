@preconcurrency import AppKit
import BlockInputKit
import SwiftUI

/// Native production composer body that mounts the BlockInputKit editor inside
/// Alveary's composer shell.
///
/// `ChatInputField` remains for legacy SwiftUI snapshots, but active chat
/// surfaces should configure this view through `AppKitChatComposerPanelView` so
/// editor measurement stays on the native AppKit path.
@MainActor
final class AppKitChatComposerBodyView: NSView {
    let editorView = ChatTextEditorView()
    let autocompletePopupView = AppKitComposerAutocompletePopupView()
    var bridgeController: BlockInputComposerBridgeController?

    var configuration: AppKitChatComposerBodyConfiguration?
    var selectedRange: NSRange?
    var measuredEditorHeight: CGFloat = AppKitChatComposerBodyView.editorBaseHeight
    var activeAutocomplete: ComposerAutocompleteState?
    var loadTask: Task<Void, Never>?
    var filterTask: Task<Void, Never>?
    var skillArgumentHints: [String: String] = [:]
    var hasLoadedSkillArgumentHints = false
    var skillHintLoadTask: Task<Void, Never>?
    var stopConfirmationResetTask: Task<Void, Never>?
    var isComposerFirstResponder = false
    var isDropTargeted = false
    var lastWorkingDirectory: String?
    // Legacy text-editor helpers still read this mirror until Phase 5 removes
    // the old composer path.
    var currentText = ""
    var currentDocument = ComposerDocument()
    var currentProjection = ComposerProjection(document: ComposerDocument())
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
        loadTask?.cancel()
        filterTask?.cancel()
        skillHintLoadTask?.cancel()
        stopConfirmationResetTask?.cancel()
    }

    func configure(_ configuration: AppKitChatComposerBodyConfiguration) {
        let previousWorkingDirectory = lastWorkingDirectory
        let previousConfiguration = self.configuration
        previousConfiguration?.onDraftSnapshotProviderChange(nil)
        if let previousConfiguration,
           previousConfiguration.draftIdentity != configuration.draftIdentity {
            bridgeController?.view.removeFromSuperview()
            bridgeController = nil
            lastConsumedFocusRequestToken = nil
        }
        self.configuration = configuration
        lastWorkingDirectory = configuration.workingDirectory
        currentText = configuration.text

        if previousWorkingDirectory != configuration.workingDirectory {
            skillArgumentHints = [:]
            hasLoadedSkillArgumentHints = false
            skillHintLoadTask?.cancel()
            skillHintLoadTask = nil
        }
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
        loadTask?.cancel()
        filterTask?.cancel()
        skillHintLoadTask?.cancel()
        stopConfirmationResetTask?.cancel()
        loadTask = nil
        filterTask = nil
        skillHintLoadTask = nil
        stopConfirmationResetTask = nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        autocompletePopupView.needsDisplay = true
    }

    override func layout() {
        super.layout()
        let editorHeight = resolvedEditorHeight
        let horizontalCompensation = Self.blockInputGutterOffset
        bridgeController?.view.frame = NSRect(
            x: -horizontalCompensation,
            y: topPadding,
            width: bounds.width + horizontalCompensation,
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

        (isDropTargeted ? NSColor.controlAccentColor : appKitComposerSecondaryColor(in: self, opacity: 0.18)).setStroke()
        path.lineWidth = isDropTargeted ? 1.5 : Self.borderWidth
        path.stroke()
    }

    private func setup() {
        wantsLayer = true
        autocompletePopupView.configure(autocomplete: nil, onSelect: { _ in }, onHighlight: { _ in })
    }
}

extension AppKitChatComposerBodyView {
    nonisolated static let editorHorizontalPadding: CGFloat = 10
    nonisolated static let editorVerticalPadding: CGFloat = 10
    nonisolated static let editorBaseHeight: CGFloat = 68
    nonisolated static let editorCornerRadius: CGFloat = 18
    nonisolated static let borderWidth: CGFloat = 1
    // BlockInputKit's reorder handle gutter is editor-owned, but Alveary's
    // composer placeholder still aligns to the action-row control column.
    nonisolated static let blockInputGutterOffset: CGFloat = 9
    nonisolated static let autocompleteVerticalOffset: CGFloat = 8
    nonisolated static let autocompleteDebounceNanoseconds: UInt64 = 75_000_000
    nonisolated static let maxAutocompleteResults = 50
    nonisolated static let stopConfirmationTimeoutNanoseconds: UInt64 = 1_000_000_000

    var topPadding: CGFloat {
        guard let configuration else {
            return 0
        }
        return configuration.hasQueuedMessages || configuration.hasTopContent ? 0 : ChatComposerPanelLayout.nativeInputPadding.top
    }

    var resolvedEditorHeight: CGFloat {
        max(0, measuredEditorHeight)
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        topPadding + resolvedEditorHeight
    }

    var autocompletePopupFrame: NSRect {
        let popupHeight = AppKitComposerAutocompletePopupView.measuredHeight(for: activeAutocomplete)
        return NSRect(
            x: 0,
            y: topPadding - popupHeight - Self.autocompleteVerticalOffset,
            width: bounds.width,
            height: popupHeight
        )
    }

    var hasVisibleAutocompletePopup: Bool {
        activeAutocomplete != nil && !autocompletePopupView.isHidden && !autocompletePopupFrame.isEmpty
    }

    func autocompletePopupFrame(in view: NSView) -> NSRect? {
        guard hasVisibleAutocompletePopup else {
            return nil
        }
        return view.convert(autocompletePopupFrame, from: self)
    }

    func presentation(for configuration: AppKitChatComposerBodyConfiguration) -> ComposerPresentation {
        ComposerPresentation(
            text: currentText,
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

    func editorConfiguration(for configuration: AppKitChatComposerBodyConfiguration) -> ChatTextEditorConfiguration {
        let presentation = presentation(for: configuration)
        let activeFocusRequestToken = configuration.requestFirstResponder
        return ChatTextEditorConfiguration(
            text: currentText,
            selectedRange: selectedRange,
            placeholder: presentation.placeholder,
            horizontalPadding: Self.editorHorizontalPadding,
            verticalPadding: Self.editorVerticalPadding,
            isDisabled: presentation.isTextEditorDisabled,
            showsDisabledCursor: configuration.isProjectTrustBlocked,
            colorScheme: configuration.colorScheme,
            textHighlightRanges: ChatInputFieldTextSupport.highlightedTokenRanges(in:),
            textChips: ChatInputFieldTextSupport.composerTextChips(in:),
            codeBlockRanges: { [weak self] _ in self?.currentProjection.codeBlockRanges ?? [] },
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges },
            inlineHint: inlineSlashCommandHint(for: configuration),
            keyPressKeys: [.upArrow, .downArrow, .tab, .escape, .return],
            requestFirstResponder: activeFocusRequestToken,
            disablesAppKitDragDestination: true,
            onTextChange: { [weak self] newText in
                self?.handleTextChange(newText)
            },
            onSelectionChange: { [weak self] range in
                self?.handleSelectionChange(range)
            },
            onMeasuredHeightChange: { [weak self] height in
                self?.handleMeasuredHeightChange(height)
            },
            onFocusChange: { [weak self] isFocused in
                self?.handleFocusChange(isFocused)
            },
            onKeyPress: { [weak self] keyPress in
                self?.handleKeyPress(keyPress) ?? .ignored
            },
            onShouldChangeText: { [weak self] range, replacement in
                self?.handleProjectedTextChange(range: range, replacement: replacement) ?? true
            },
            onFocusRequestConsumed: { [weak self] in
                self?.consumeFocusRequest(activeFocusRequestToken)
            }
        )
    }

    func normalizeSelection(for text: String) {
        guard let selectedRange else {
            return
        }
        let textLength = (text as NSString).length
        if selectedRange.location > textLength || NSMaxRange(selectedRange) > textLength {
            self.selectedRange = NSRange(location: textLength, length: 0)
        }
    }

    func primeMeasuredHeight(for text: String) {
        measuredEditorHeight = ChatTextEditor.primedMeasuredHeight(
            for: text,
            minHeight: Self.editorBaseHeight,
            verticalPadding: Self.editorVerticalPadding
        )
    }

    func handleTextChange(_ newText: String) {
        guard let configuration else {
            return
        }
        guard newText != currentText else {
            refreshAutocomplete(text: currentText)
            return
        }
        currentText = newText
        currentDocument = ComposerDocument(markdown: newText)
        currentProjection = currentDocument.projection
        configuration.onTextChange(newText)
        if newText.hasPrefix("/") {
            loadSkillArgumentHintsIfNeeded()
        }
        refreshAutocomplete(text: newText)
    }

    func handleProjectedTextChange(range: NSRange, replacement: String?) -> Bool {
        guard let configuration,
              let result = ComposerTransaction.replacingVisibleText(
                  in: currentDocument,
                  projection: currentProjection,
                  range: range,
                  replacement: replacement ?? ""
              ) else {
            return true
        }

        applyDocumentResult(result, configuration: configuration)
        // The NSTextView is a projection. After the document transaction applies,
        // we re-render the projection ourselves instead of letting AppKit mutate
        // text storage into a state that no longer matches `ComposerDocument`.
        return false
    }

    func assertNoDocumentOwnedBlockFences() {
        #if DEBUG
        guard !currentProjection.codeBlockRanges.isEmpty else {
            return
        }
        let nsText = currentText as NSString
        var location = 0
        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let line = nsText.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let isInsideCodeBlock = currentProjection.codeBlockRanges.contains { range in
                NSIntersectionRange(range, lineRange).length > 0
            }
            if line.hasPrefix("```"), !isInsideCodeBlock {
                assertionFailure("Composer projection leaked a block-code fence into NSTextView text storage.")
            }
            location = NSMaxRange(lineRange)
        }
        #endif
    }

    func handleSelectionChange(_ range: NSRange) {
        selectedRange = range
        refreshAutocomplete()
    }

    func handleMeasuredHeightChange(_ height: CGFloat) {
        let clampedHeight = max(height, Self.editorBaseHeight)
        guard abs(measuredEditorHeight - clampedHeight) > 0.5 else {
            return
        }
        measuredEditorHeight = clampedHeight
        invalidatePreferredSize()
    }

    func handlePreferredHeightChange(_ height: CGFloat) {
        let nextHeight = max(0, ceil(height))
        guard abs(measuredEditorHeight - nextHeight) > 0.5 else {
            return
        }
        measuredEditorHeight = nextHeight
        invalidatePreferredSize()
    }

    func handleFocusChange(_ isFocused: Bool) {
        isComposerFirstResponder = isFocused
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

    func refreshEditorConfiguration() {
        guard let configuration else {
            return
        }
        editorView.configure(editorConfiguration(for: configuration))
    }

    func invalidatePreferredSize() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        superview?.needsLayout = true
        onPreferredSizeInvalidated?()
    }
}
