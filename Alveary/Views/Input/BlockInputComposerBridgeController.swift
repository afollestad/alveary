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
    var editorHorizontalInset: CGFloat
    var editorVerticalInset: CGFloat
    var editorRoundedCorners: BlockInputEditorChromeCorners
    var location: BlockInputComposerLocation
    var localCommands: ComposerLocalCommandAvailability
    var loadFileCompletions: @Sendable () async -> [String]
    var loadSkillCompletions: @Sendable () async -> [Skill]
    var keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler]
    var completionPopupOverlayProvider: (@MainActor (BlockInputCompletionPopupOverlayContext) -> BlockInputCompletionPopupOverlay?)?
    var modalOverlayProvider: (@MainActor (BlockInputModalOverlayContext) -> BlockInputModalOverlay?)?
    var onDocumentMutation: (BlockInputDocumentChange, Bool) -> Void
    var onDocumentChange: (BlockInputDocument) -> Void
    var onPreferredHeightTransition: @MainActor @Sendable (BlockInputEditorHeightTransition) -> Void

    init(
        markdown: String,
        markdownRevision: Int = 0,
        placeholder: String? = nil,
        isEditable: Bool = true,
        disabledCursor: NSCursor? = nil,
        editorHorizontalInset: CGFloat = BlockInputConfiguration.defaultEditorHorizontalInset,
        editorVerticalInset: CGFloat = BlockInputConfiguration.defaultEditorVerticalInset,
        editorRoundedCorners: BlockInputEditorChromeCorners = .all,
        location: BlockInputComposerLocation,
        localCommands: ComposerLocalCommandAvailability = ComposerLocalCommandAvailability(),
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] = [:],
        completionPopupOverlayProvider: (@MainActor (BlockInputCompletionPopupOverlayContext) -> BlockInputCompletionPopupOverlay?)? = nil,
        modalOverlayProvider: (@MainActor (BlockInputModalOverlayContext) -> BlockInputModalOverlay?)? = nil,
        onDocumentMutation: @escaping (BlockInputDocumentChange, Bool) -> Void = { _, _ in },
        onDocumentChange: @escaping (BlockInputDocument) -> Void = { _ in },
        onPreferredHeightTransition: @escaping @MainActor @Sendable (BlockInputEditorHeightTransition) -> Void = { _ in }
    ) {
        self.markdown = markdown
        self.markdownRevision = markdownRevision
        self.placeholder = placeholder
        self.isEditable = isEditable
        self.disabledCursor = disabledCursor
        self.editorHorizontalInset = editorHorizontalInset
        self.editorVerticalInset = editorVerticalInset
        self.editorRoundedCorners = editorRoundedCorners
        self.location = location
        self.localCommands = localCommands
        self.loadFileCompletions = loadFileCompletions
        self.loadSkillCompletions = loadSkillCompletions
        self.keyboardShortcuts = keyboardShortcuts
        self.completionPopupOverlayProvider = completionPopupOverlayProvider
        self.modalOverlayProvider = modalOverlayProvider
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
    #if DEBUG
    private(set) var viewConfigureCountForTesting = 0
    #endif

    init(configuration: BlockInputComposerBridgeConfiguration) {
        let document = BlockInputDocument(markdown: configuration.markdown)
        documentStore = BlockInputMemoryDocumentStore(document: document)
        completionProvider = Self.makeCompletionProvider(configuration)
        currentConfiguration = configuration
        appliedViewConfigurationKey = Self.viewConfigurationKey(for: configuration)
        lastConfiguredMarkdownRevision = configuration.markdownRevision
        configureBlockInputView(for: configuration)
    }

    func configure(_ configuration: BlockInputComposerBridgeConfiguration) {
        currentConfiguration = configuration
        let replacedDocument = replaceExternalMarkdownIfNeeded(configuration)
        updateCompletionProvider(configuration)
        let nextViewConfigurationKey = Self.viewConfigurationKey(for: configuration)
        guard replacedDocument || nextViewConfigurationKey != appliedViewConfigurationKey else {
            return
        }
        appliedViewConfigurationKey = nextViewConfigurationKey
        configureBlockInputView(for: configuration)
    }

    private func replaceExternalMarkdownIfNeeded(_ configuration: BlockInputComposerBridgeConfiguration) -> Bool {
        if configuration.markdownRevision != lastConfiguredMarkdownRevision {
            lastConfiguredMarkdownRevision = configuration.markdownRevision
            if configuration.markdown != documentStore.document.markdown {
                documentStore.replaceDocument(BlockInputDocument(markdown: configuration.markdown))
                undoController = BlockInputUndoController()
                return true
            }
        }
        return false
    }

    func currentMarkdown() -> String {
        documentStore.document.markdown
    }

    func blockInputConfiguration(
        for configuration: BlockInputComposerBridgeConfiguration
    ) -> BlockInputConfiguration {
        let completionProvider = completionProvider
        return BlockInputConfiguration(
            documentStore: documentStore,
            allowsBlockReordering: false,
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
            style: BlockInputComposerStyle.make(roundedCorners: configuration.editorRoundedCorners),
            selectAllBehavior: .document,
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: Self.minVisibleLineCount,
                maximumVisibleLineCount: Self.maxVisibleLineCount,
                animation: .default,
                onPreferredHeightTransition: { [weak self] transition in
                    self?.currentConfiguration.onPreferredHeightTransition(transition)
                }
            ),
            imageBaseURL: configuration.location.imageBaseURL,
            fileBaseURL: configuration.location.fileBaseURL,
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
            onDocumentMutation: { [weak self] change in
                guard let self else {
                    return
                }
                currentConfiguration.onDocumentMutation(change, documentStore.document.isEffectivelyEmpty)
            },
            onDocumentChange: { [weak self] document in
                self?.currentConfiguration.onDocumentChange(document)
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

    private static func makeCompletionProvider(
        _ configuration: BlockInputComposerBridgeConfiguration
    ) -> BlockInputComposerCompletionProvider {
        BlockInputComposerCompletionProvider(
            location: configuration.location,
            localCommands: configuration.localCommands,
            loadFileCompletions: configuration.loadFileCompletions,
            loadSkillCompletions: configuration.loadSkillCompletions
        )
    }

    private func updateCompletionProvider(_ configuration: BlockInputComposerBridgeConfiguration) {
        if completionProvider.location == configuration.location {
            completionProvider.update(
                location: configuration.location,
                localCommands: configuration.localCommands,
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
            editorHorizontalInset: configuration.editorHorizontalInset,
            editorVerticalInset: configuration.editorVerticalInset,
            editorRoundedCorners: configuration.editorRoundedCorners.rawValue,
            location: configuration.location,
            localCommands: configuration.localCommands,
            keyboardShortcuts: Set(configuration.keyboardShortcuts.keys)
        )
    }
}

private struct BridgeViewConfigKey: Equatable {
    var placeholder: String?
    var isEditable: Bool
    var disabledCursor: ObjectIdentifier?
    var editorHorizontalInset: CGFloat
    var editorVerticalInset: CGFloat
    var editorRoundedCorners: Int
    var location: BlockInputComposerLocation
    var localCommands: ComposerLocalCommandAvailability
    var keyboardShortcuts: Set<BlockInputKeyboardShortcut>
}
