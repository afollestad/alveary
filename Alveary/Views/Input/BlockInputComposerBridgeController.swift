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
    var location: BlockInputComposerLocation
    var loadFileCompletions: @Sendable () async -> [String]
    var loadSkillCompletions: @Sendable () async -> [Skill]
    var keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler]
    var completionPopupOverlayProvider: (@MainActor (BlockInputCompletionPopupOverlayContext) -> BlockInputCompletionPopupOverlay?)?
    var onDocumentMutation: (BlockInputDocumentChange, Bool) -> Void
    var onDocumentChange: (BlockInputDocument) -> Void
    var onPreferredHeightChange: @MainActor @Sendable (CGFloat) -> Void
    var onFocusChange: (Bool) -> Void

    init(
        markdown: String,
        markdownRevision: Int = 0,
        placeholder: String? = nil,
        isEditable: Bool = true,
        disabledCursor: NSCursor? = nil,
        editorHorizontalInset: CGFloat = BlockInputConfiguration.defaultEditorHorizontalInset,
        editorVerticalInset: CGFloat = BlockInputConfiguration.defaultEditorVerticalInset,
        location: BlockInputComposerLocation,
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] = [:],
        completionPopupOverlayProvider: (@MainActor (BlockInputCompletionPopupOverlayContext) -> BlockInputCompletionPopupOverlay?)? = nil,
        onDocumentMutation: @escaping (BlockInputDocumentChange, Bool) -> Void = { _, _ in },
        onDocumentChange: @escaping (BlockInputDocument) -> Void = { _ in },
        onPreferredHeightChange: @escaping @MainActor @Sendable (CGFloat) -> Void = { _ in },
        onFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.markdown = markdown
        self.markdownRevision = markdownRevision
        self.placeholder = placeholder
        self.isEditable = isEditable
        self.disabledCursor = disabledCursor
        self.editorHorizontalInset = editorHorizontalInset
        self.editorVerticalInset = editorVerticalInset
        self.location = location
        self.loadFileCompletions = loadFileCompletions
        self.loadSkillCompletions = loadSkillCompletions
        self.keyboardShortcuts = keyboardShortcuts
        self.completionPopupOverlayProvider = completionPopupOverlayProvider
        self.onDocumentMutation = onDocumentMutation
        self.onDocumentChange = onDocumentChange
        self.onPreferredHeightChange = onPreferredHeightChange
        self.onFocusChange = onFocusChange
    }
}

@MainActor
final class BlockInputComposerBridgeController {
    static let minVisibleLineCount = 3
    static let maxVisibleLineCount = 9

    let view = BlockInputView()
    private(set) var documentStore: BlockInputMemoryDocumentStore
    private(set) var undoController = BlockInputUndoController()
    private(set) var commandDispatcher = BlockInputEditorCommandDispatcher()
    private(set) var completionProvider: BlockInputComposerCompletionProvider
    private(set) var lastMarkdown: String
    private var lastConfiguredMarkdownRevision: Int

    init(configuration: BlockInputComposerBridgeConfiguration) {
        let document = BlockInputDocument(markdown: configuration.markdown)
        documentStore = BlockInputMemoryDocumentStore(document: document)
        completionProvider = Self.makeCompletionProvider(configuration)
        lastMarkdown = configuration.markdown
        lastConfiguredMarkdownRevision = configuration.markdownRevision
        view.configure(blockInputConfiguration(for: configuration))
    }

    func configure(_ configuration: BlockInputComposerBridgeConfiguration) {
        if configuration.markdownRevision != lastConfiguredMarkdownRevision {
            lastConfiguredMarkdownRevision = configuration.markdownRevision
            if configuration.markdown != documentStore.document.markdown {
                documentStore.replaceDocument(BlockInputDocument(markdown: configuration.markdown))
                undoController = BlockInputUndoController()
            }
            lastMarkdown = configuration.markdown
        }
        completionProvider = Self.makeCompletionProvider(configuration)
        view.configure(blockInputConfiguration(for: configuration))
    }

    func currentMarkdown() -> String {
        documentStore.document.markdown
    }

    func blockInputConfiguration(
        for configuration: BlockInputComposerBridgeConfiguration
    ) -> BlockInputConfiguration {
        BlockInputConfiguration(
            documentStore: documentStore,
            allowsBlockReordering: false,
            editorHorizontalInset: configuration.editorHorizontalInset,
            editorVerticalInset: configuration.editorVerticalInset,
            placeholder: configuration.placeholder,
            isEditable: configuration.isEditable,
            disabledCursor: configuration.disabledCursor,
            rawSlashCommandChips: true,
            dropIndicatorColor: .controlAccentColor,
            style: BlockInputComposerStyle.make(),
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: Self.minVisibleLineCount,
                maximumVisibleLineCount: Self.maxVisibleLineCount,
                onPreferredHeightChange: configuration.onPreferredHeightChange
            ),
            imageBaseURL: configuration.location.imageBaseURL,
            fileBaseURL: configuration.location.fileBaseURL,
            undoController: undoController,
            commandDispatcher: commandDispatcher,
            keyboardShortcuts: configuration.keyboardShortcuts,
            completionProvider: completionProvider,
            completionReturnBehavior: .passthroughExactMatch,
            slashCommandAvailability: .documentStart,
            completionPopupConfiguration: BlockInputCompletionPopupConfiguration(
                placement: .overlay,
                overlayProvider: configuration.completionPopupOverlayProvider
            ),
            onDocumentMutation: { [weak self] change in
                configuration.onDocumentMutation(change, self?.documentStore.document.isEffectivelyEmpty ?? true)
            },
            onDocumentChange: { [weak self] document in
                self?.lastMarkdown = document.markdown
                configuration.onDocumentChange(document)
            },
            onFocusChange: configuration.onFocusChange
        )
    }

    private static func makeCompletionProvider(
        _ configuration: BlockInputComposerBridgeConfiguration
    ) -> BlockInputComposerCompletionProvider {
        BlockInputComposerCompletionProvider(
            location: configuration.location,
            loadFileCompletions: configuration.loadFileCompletions,
            loadSkillCompletions: configuration.loadSkillCompletions
        )
    }
}
