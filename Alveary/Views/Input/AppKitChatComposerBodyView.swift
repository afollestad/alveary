@preconcurrency import AppKit
import SwiftUI

/// Composer state and callbacks consumed by the native AppKit body.
///
/// Keep this as a value boundary between `ChatView` state and AppKit rendering:
/// the view may measure, focus, and draw locally, but source-of-truth composer
/// state should still flow through these fields and closures.
struct AppKitChatComposerBodyConfiguration {
    let text: String
    let mode: ComposerMode
    let defaultEnterBehavior: ThreadEnterDefaultBehavior
    let isStopConfirmationArmed: Bool
    let supportsMidTurnSteering: Bool
    let isProjectTrustBlocked: Bool
    let isHandoffSteeringPromptActive: Bool
    let isHandoffOutputPromptActive: Bool
    let handoffSteeringCountdown: Int?
    let sendCountdown: Int?
    let hasQueuedMessages: Bool
    let hasTopContent: Bool
    let workingDirectory: String?
    let requestFirstResponder: UUID?
    let colorScheme: ColorScheme
    let loadFileCompletions: @Sendable () async -> [String]
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let onTextChange: (String) -> Void
    let onSubmit: () -> Void
    let onSteer: () -> Void
    let onStop: () -> Void
    let onStopConfirmationChange: (Bool) -> Void
    let onFocusRequestConsumed: (UUID?) -> Void
}

/// Native production composer body: editor, autocomplete state, drop handling,
/// and keyboard behavior.
///
/// `ChatInputField` remains for legacy SwiftUI snapshots, but active chat
/// surfaces should configure this view through `AppKitChatComposerPanelView` so
/// editor measurement and autocomplete state stay on the native path.
@MainActor
final class AppKitChatComposerBodyView: NSView {
    let editorView = ChatTextEditorView()
    let autocompletePopupView = AppKitComposerAutocompletePopupView()

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
    // NSTextView edits can trigger AppKit-side refreshes before SwiftUI calls
    // back into `configure(_:)`, so editor/autocomplete paths read this mirror
    // instead of the last configuration value.
    var currentText = ""
    var onPreferredSizeInvalidated: (() -> Void)?

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
        let previousText = self.configuration?.text
        let previousWorkingDirectory = lastWorkingDirectory
        self.configuration = configuration
        lastWorkingDirectory = configuration.workingDirectory
        currentText = configuration.text

        if previousWorkingDirectory != configuration.workingDirectory {
            skillArgumentHints = [:]
            hasLoadedSkillArgumentHints = false
            skillHintLoadTask?.cancel()
            skillHintLoadTask = nil
        }
        normalizeSelection(for: configuration.text)
        if previousText != configuration.text {
            primeMeasuredHeight(for: configuration.text)
        }

        editorView.configure(editorConfiguration(for: configuration))

        if configuration.text.hasPrefix("/") {
            loadSkillArgumentHintsIfNeeded()
        }
        if previousText != configuration.text {
            refreshAutocomplete()
        } else if previousWorkingDirectory != configuration.workingDirectory, isComposerFirstResponder {
            refreshAutocomplete(forceReload: true)
        }
        if presentation(for: configuration).isTextEditorDisabled {
            dismissAutocomplete()
        }
        configureAutocompletePopup()
        needsLayout = true
        needsDisplay = true
        invalidatePreferredSize()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil else {
            return
        }
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
        editorView.frame = NSRect(
            x: 0,
            y: topPadding,
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

        (isDropTargeted ? NSColor.controlAccentColor : appKitComposerSecondaryColor(in: self, opacity: 0.18)).setStroke()
        path.lineWidth = isDropTargeted ? 1.5 : Self.borderWidth
        path.stroke()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileURLs(in: sender.draggingPasteboard) else {
            return []
        }
        isDropTargeted = true
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargeted = false
        needsDisplay = true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTargeted = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            isDropTargeted = false
            needsDisplay = true
        }
        guard let configuration,
              let urls = sender.draggingPasteboard.readObjects(
                  forClasses: [NSURL.self],
                  options: [.urlReadingFileURLsOnly: true]
              ) as? [URL] else {
            return false
        }
        return handleDroppedFiles(urls, configuration: configuration)
    }

    private func setup() {
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        addSubview(editorView)
        autocompletePopupView.configure(autocomplete: nil, onSelect: { _ in }, onHighlight: { _ in })
    }
}

extension AppKitChatComposerBodyView {
    nonisolated static let editorHorizontalPadding: CGFloat = 10
    nonisolated static let editorVerticalPadding: CGFloat = 10
    nonisolated static let editorBaseHeight: CGFloat = 68
    nonisolated static let editorMaxHeight: CGFloat = 144
    nonisolated static let editorCornerRadius: CGFloat = 18
    nonisolated static let borderWidth: CGFloat = 1
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
        min(max(measuredEditorHeight, Self.editorBaseHeight), Self.editorMaxHeight)
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
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
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
        currentText = newText
        configuration.onTextChange(newText)
        if newText.hasPrefix("/") {
            loadSkillArgumentHintsIfNeeded()
        }
        refreshAutocomplete(text: newText)
    }

    func handleSelectionChange(_ range: NSRange) {
        selectedRange = range
        refreshAutocomplete()
    }

    func handleMeasuredHeightChange(_ height: CGFloat) {
        guard abs(measuredEditorHeight - height) > 0.5 else {
            return
        }
        measuredEditorHeight = height
        invalidatePreferredSize()
    }

    func handleFocusChange(_ isFocused: Bool) {
        isComposerFirstResponder = isFocused
        if isFocused {
            refreshAutocomplete()
        } else {
            dismissAutocomplete()
        }
    }

    func consumeFocusRequest(_ token: UUID?) {
        configuration?.onFocusRequestConsumed(token)
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
