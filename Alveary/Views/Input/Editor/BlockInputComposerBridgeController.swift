import AppKit
import BlockInputKit

@MainActor
struct BlockInputComposerBridgeConfiguration {
    var markdown: String
    /// App-owned draft replacement revision; mirrored user edits do not advance this value.
    var markdownRevision: Int
    var placeholder: String?
    var isEditable: Bool
    var disabledCursor: NSCursor?
    /// Composer image handling for both draft Markdown import and editor presentation.
    var imagePresentation: BlockInputImagePresentation
    var editorHorizontalInset: CGFloat
    var editorVerticalInset: CGFloat
    var editorRoundedCorners: BlockInputEditorChromeCorners
    var editorStrokedEdges: BlockInputEditorChromeEdges
    var location: BlockInputComposerLocation
    var urlOpener: BlockInputURLOpener
    var localCommands: ComposerLocalCommandAvailability
    var passthroughSlashCommands: [ComposerPassthroughSlashCommand]
    var loadFileCompletions: @Sendable () async -> [String]
    var loadSkillCompletions: @Sendable () async -> [Skill]
    var keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler]
    var completionPopupOverlayProvider: (@MainActor (BlockInputCompletionPopupOverlayContext) -> BlockInputCompletionPopupOverlay?)?
    var modalOverlayProvider: (@MainActor (BlockInputModalOverlayContext) -> BlockInputModalOverlay?)?
    var onSelectionChange: (BlockInputSelection?) -> Void
    var onEditorInteractionUIChange: (Bool) -> Void
    var onDocumentMutation: (BlockInputDocumentChange, Bool) -> Void
    var onDocumentChange: (BlockInputDocument) -> Void
    var onPreferredHeightTransition: @MainActor @Sendable (BlockInputEditorHeightTransition) -> Void

    init(
        markdown: String,
        markdownRevision: Int = 0,
        placeholder: String? = nil,
        isEditable: Bool = true,
        disabledCursor: NSCursor? = nil,
        imagePresentation: BlockInputImagePresentation = .inlineBlocks,
        editorHorizontalInset: CGFloat = BlockInputConfiguration.defaultEditorHorizontalInset,
        editorVerticalInset: CGFloat = BlockInputConfiguration.defaultEditorVerticalInset,
        editorRoundedCorners: BlockInputEditorChromeCorners = .all,
        editorStrokedEdges: BlockInputEditorChromeEdges = .all,
        location: BlockInputComposerLocation,
        urlOpener: @escaping BlockInputURLOpener = { NSWorkspace.shared.open($0) },
        localCommands: ComposerLocalCommandAvailability = ComposerLocalCommandAvailability(),
        passthroughSlashCommands: [ComposerPassthroughSlashCommand] = [],
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] = [:],
        completionPopupOverlayProvider: (@MainActor (BlockInputCompletionPopupOverlayContext) -> BlockInputCompletionPopupOverlay?)? = nil,
        modalOverlayProvider: (@MainActor (BlockInputModalOverlayContext) -> BlockInputModalOverlay?)? = nil,
        onSelectionChange: @escaping (BlockInputSelection?) -> Void = { _ in },
        onEditorInteractionUIChange: @escaping (Bool) -> Void = { _ in },
        onDocumentMutation: @escaping (BlockInputDocumentChange, Bool) -> Void = { _, _ in },
        onDocumentChange: @escaping (BlockInputDocument) -> Void = { _ in },
        onPreferredHeightTransition: @escaping @MainActor @Sendable (BlockInputEditorHeightTransition) -> Void = { _ in }
    ) {
        self.markdown = markdown
        self.markdownRevision = markdownRevision
        self.placeholder = placeholder
        self.isEditable = isEditable
        self.disabledCursor = disabledCursor
        self.imagePresentation = imagePresentation
        self.editorHorizontalInset = editorHorizontalInset
        self.editorVerticalInset = editorVerticalInset
        self.editorRoundedCorners = editorRoundedCorners
        self.editorStrokedEdges = editorStrokedEdges
        self.location = location
        self.urlOpener = urlOpener
        self.localCommands = localCommands
        self.passthroughSlashCommands = passthroughSlashCommands
        self.loadFileCompletions = loadFileCompletions
        self.loadSkillCompletions = loadSkillCompletions
        self.keyboardShortcuts = keyboardShortcuts
        self.completionPopupOverlayProvider = completionPopupOverlayProvider
        self.modalOverlayProvider = modalOverlayProvider
        self.onSelectionChange = onSelectionChange
        self.onEditorInteractionUIChange = onEditorInteractionUIChange
        self.onDocumentMutation = onDocumentMutation
        self.onDocumentChange = onDocumentChange
        self.onPreferredHeightTransition = onPreferredHeightTransition
    }
}

@MainActor
final class BlockInputComposerBridgeController {
    static let minVisibleLineCount = 2
    static let maxVisibleLineCount = 9
    static let blockVerticalInsetMultiplier: CGFloat = 0.7

    let view = BlockInputView()
    private(set) var documentStore: BlockInputMemoryDocumentStore
    private(set) var undoController = BlockInputUndoController()
    private(set) var commandDispatcher = BlockInputEditorCommandDispatcher()
    private(set) var completionProvider: BlockInputComposerCompletionProvider
    private var currentConfiguration: BlockInputComposerBridgeConfiguration
    private var appliedViewConfigurationKey: BridgeViewConfigKey
    private var lastConfiguredMarkdownRevision: Int
    private var lastConfiguredImagePresentation: BlockInputImagePresentation
    #if DEBUG
    private(set) var viewConfigureCountForTesting = 0
    #endif

    init(configuration: BlockInputComposerBridgeConfiguration) {
        let document = BlockInputDocument(
            markdown: configuration.markdown,
            imageParsingMode: Self.imageParsingMode(for: configuration.imagePresentation)
        )
        documentStore = BlockInputMemoryDocumentStore(document: document)
        completionProvider = Self.makeCompletionProvider(configuration)
        currentConfiguration = configuration
        appliedViewConfigurationKey = Self.viewConfigurationKey(for: configuration)
        lastConfiguredMarkdownRevision = configuration.markdownRevision
        lastConfiguredImagePresentation = configuration.imagePresentation
        configureBlockInputView(for: configuration)
    }

    @discardableResult
    func configure(_ configuration: BlockInputComposerBridgeConfiguration) -> Bool {
        currentConfiguration = configuration
        let replacedDocument = replaceExternalMarkdownIfNeeded(configuration)
        updateCompletionProvider(configuration)
        let nextViewConfigurationKey = Self.viewConfigurationKey(for: configuration)
        guard replacedDocument || nextViewConfigurationKey != appliedViewConfigurationKey else {
            return false
        }
        appliedViewConfigurationKey = nextViewConfigurationKey
        configureBlockInputView(for: configuration)
        return replacedDocument
    }

    private func replaceExternalMarkdownIfNeeded(_ configuration: BlockInputComposerBridgeConfiguration) -> Bool {
        let imagePresentationChanged = configuration.imagePresentation != lastConfiguredImagePresentation
        if configuration.markdownRevision != lastConfiguredMarkdownRevision || imagePresentationChanged {
            lastConfiguredMarkdownRevision = configuration.markdownRevision
            lastConfiguredImagePresentation = configuration.imagePresentation
            if configuration.markdown != documentStore.document.markdown || imagePresentationChanged {
                documentStore.replaceDocument(BlockInputDocument(
                    markdown: configuration.markdown,
                    imageParsingMode: Self.imageParsingMode(for: configuration.imagePresentation)
                ))
                undoController = BlockInputUndoController()
                return true
            }
        }
        return false
    }

    func currentMarkdown() -> String {
        documentStore.document.markdown
    }

    func focusEditorAtDocumentEnd() {
        guard let lastBlock = documentStore.document.blocks.last else {
            view.focusEditor()
            return
        }
        view.focus(blockID: lastBlock.id, utf16Offset: lastBlock.cursorUTF16Length)
    }

    func blockInputConfiguration(
        for configuration: BlockInputComposerBridgeConfiguration
    ) -> BlockInputConfiguration {
        let completionProvider = completionProvider
        return BlockInputConfiguration(
            documentStore: documentStore,
            allowsBlockReordering: false,
            allowsDrops: false,
            editorHorizontalInset: configuration.editorHorizontalInset,
            editorVerticalInset: configuration.editorVerticalInset,
            blockVerticalInsetMultiplier: Self.blockVerticalInsetMultiplier,
            placeholder: configuration.placeholder,
            isEditable: configuration.isEditable,
            disabledCursor: configuration.disabledCursor,
            inlineHintProvider: { [completionProvider] context in
                completionProvider.inlineHint(for: context)
            },
            rawSlashCommandChips: true,
            dropIndicatorColor: .controlAccentColor,
            style: BlockInputComposerStyle.make(
                roundedCorners: configuration.editorRoundedCorners,
                strokedEdges: configuration.editorStrokedEdges
            ),
            selectAllBehavior: .document,
            heightSizing: heightSizing(),
            imagePresentation: configuration.imagePresentation,
            imageBaseURL: configuration.location.imageBaseURL,
            fileBaseURL: configuration.location.fileBaseURL,
            urlOpener: { [weak self] url in
                self?.currentConfiguration.urlOpener(url) ?? false
            },
            undoController: undoController,
            commandDispatcher: commandDispatcher,
            keyboardShortcuts: keyboardShortcuts(for: configuration),
            completionProvider: completionProvider,
            completionReturnBehavior: .passthroughExactMatch,
            slashCommandAvailability: .documentStart,
            modalOverlayProvider: { [weak self] context in
                self?.currentConfiguration.modalOverlayProvider?(context)
            },
            completionPopupConfiguration: completionPopupConfiguration(),
            onEditorInteractionUIChange: { [weak self] isPresented in
                self?.currentConfiguration.onEditorInteractionUIChange(isPresented)
            },
            onDocumentMutation: documentMutationHandler(),
            onDocumentChange: { [weak self] document in
                self?.currentConfiguration.onDocumentChange(document)
            },
            onSelectionChange: selectionChangeHandler()
        )
    }

    private func documentMutationHandler() -> (BlockInputDocumentChange) -> Void {
        { [weak self] change in
            guard let self else { return }
            currentConfiguration.onDocumentMutation(change, documentStore.document.isEffectivelyEmpty)
        }
    }

    private func selectionChangeHandler() -> (BlockInputSelection?) -> Void {
        { [weak self] selection in
            self?.currentConfiguration.onSelectionChange(selection)
        }
    }

    private func heightSizing() -> BlockInputEditorHeightSizing {
        BlockInputEditorHeightSizing(
            defaultVisibleLineCount: Self.minVisibleLineCount,
            maximumVisibleLineCount: Self.maxVisibleLineCount,
            animation: .default,
            onPreferredHeightTransition: { [weak self] transition in
                self?.currentConfiguration.onPreferredHeightTransition(transition)
            }
        )
    }

    private func completionPopupConfiguration() -> BlockInputCompletionPopupConfiguration {
        BlockInputCompletionPopupConfiguration(
            placement: .overlay,
            style: BlockInputComposerStyle.completionPopupStyle(),
            overlayProvider: { [weak self] context in
                self?.currentConfiguration.completionPopupOverlayProvider?(context)
            }
        )
    }

    private func keyboardShortcuts(
        for configuration: BlockInputComposerBridgeConfiguration
    ) -> [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] {
        var forwardedShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] = [:]
        for shortcut in configuration.keyboardShortcuts.keys {
            forwardedShortcuts[shortcut] = { [weak self] context in
                self?.currentConfiguration.keyboardShortcuts[shortcut]?(context) ?? .ignored
            }
        }
        return forwardedShortcuts
    }

    private func configureBlockInputView(for configuration: BlockInputComposerBridgeConfiguration) {
        view.configure(blockInputConfiguration(for: configuration))
        #if DEBUG
        viewConfigureCountForTesting += 1
        #endif
    }

    private static func imageParsingMode(
        for imagePresentation: BlockInputImagePresentation
    ) -> BlockInputMarkdownImageParsingMode {
        imagePresentation == .inlineBlocks ? .imageBlocks : .preserveSourceText
    }

    private static func makeCompletionProvider(
        _ configuration: BlockInputComposerBridgeConfiguration
    ) -> BlockInputComposerCompletionProvider {
        BlockInputComposerCompletionProvider(
            location: configuration.location,
            localCommands: configuration.localCommands,
            passthroughSlashCommands: configuration.passthroughSlashCommands,
            loadFileCompletions: configuration.loadFileCompletions,
            loadSkillCompletions: configuration.loadSkillCompletions
        )
    }

    private func updateCompletionProvider(_ configuration: BlockInputComposerBridgeConfiguration) {
        if completionProvider.location == configuration.location {
            completionProvider.update(
                location: configuration.location,
                localCommands: configuration.localCommands,
                passthroughSlashCommands: configuration.passthroughSlashCommands,
                loadFileCompletions: configuration.loadFileCompletions,
                loadSkillCompletions: configuration.loadSkillCompletions
            )
        } else {
            completionProvider = Self.makeCompletionProvider(configuration)
        }
    }

    private static func viewConfigurationKey(
        for configuration: BlockInputComposerBridgeConfiguration
    ) -> BridgeViewConfigKey {
        BridgeViewConfigKey(
            placeholder: configuration.placeholder,
            isEditable: configuration.isEditable,
            disabledCursor: configuration.disabledCursor.map { ObjectIdentifier($0) },
            imagePresentation: configuration.imagePresentation,
            editorHorizontalInset: configuration.editorHorizontalInset,
            editorVerticalInset: configuration.editorVerticalInset,
            editorRoundedCorners: configuration.editorRoundedCorners.rawValue,
            editorStrokedEdges: configuration.editorStrokedEdges.rawValue,
            location: configuration.location,
            localCommands: configuration.localCommands,
            passthroughSlashCommands: configuration.passthroughSlashCommands,
            keyboardShortcuts: Set(configuration.keyboardShortcuts.keys)
        )
    }
}

private struct BridgeViewConfigKey: Equatable {
    var placeholder: String?
    var isEditable: Bool
    var disabledCursor: ObjectIdentifier?
    var imagePresentation: BlockInputImagePresentation
    var editorHorizontalInset: CGFloat
    var editorVerticalInset: CGFloat
    var editorRoundedCorners: Int
    var editorStrokedEdges: Int
    var location: BlockInputComposerLocation
    var localCommands: ComposerLocalCommandAvailability
    var passthroughSlashCommands: [ComposerPassthroughSlashCommand]
    var keyboardShortcuts: Set<BlockInputKeyboardShortcut>
}
