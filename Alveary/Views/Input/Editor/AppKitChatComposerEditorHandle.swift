import BlockInputKit
import Foundation

struct ComposerVoiceInsertionContext: Equatable, Sendable {
    let precedingText: String?
    let followingText: String?

    func replacementText(for transcript: String) -> String {
        let leading = needsLeadingSpace ? " " : ""
        let trailing = needsTrailingSpace ? " " : ""
        return leading + transcript + trailing
    }

    private var needsLeadingSpace: Bool {
        guard let precedingText, !precedingText.isEmpty else {
            return false
        }
        guard !precedingText.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) else {
            return false
        }
        return !Self.openingPunctuation.contains(precedingText)
    }

    private var needsTrailingSpace: Bool {
        guard let followingText, !followingText.isEmpty else {
            return false
        }
        guard !followingText.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) else {
            return false
        }
        return !Self.closingPunctuation.contains(followingText)
    }

    private static let openingPunctuation: Set<String> = ["(", "[", "{", "\"", "'", "“", "‘"]
    private static let closingPunctuation: Set<String> = [")", "]", "}", ".", ",", "!", "?", ";", ":", "\"", "'", "”", "’"]
}

/// Stable weak reference to the mounted BlockInputKit editor. Routine SwiftUI
/// reconfiguration rebinds the same handle without clearing it.
@MainActor
final class AppKitChatComposerEditorHandle {
    private weak var controller: AppKitChatComposerEditorController?
    private(set) var draftIdentity: String?
    private var inputDraftRevision: Int?
    private(set) var draftGeneration: UInt64 = 0
    var onWillInvalidate: (() -> Void)?
    var onDraftGenerationChange: (() -> Void)?

    var isMounted: Bool {
        controller?.view?.window != nil
    }

    var supportsVoiceInputSelection: Bool {
        controller?.supportsVoiceInputSelection ?? false
    }

    var hasPresentedEditorInteractionUI: Bool {
        controller?.view?.hasPresentedEditorInteractionUI ?? false
    }

    var canStartVoiceInput: Bool {
        guard let view = controller?.view else {
            return false
        }
        return view.window != nil &&
            view.isEditable &&
            supportsVoiceInputSelection &&
            !view.hasPresentedEditorInteractionUI
    }

    func bind(
        _ controller: AppKitChatComposerEditorController,
        draftIdentity: String,
        inputDraftRevision: Int
    ) {
        if self.controller !== controller ||
            self.draftIdentity != draftIdentity ||
            self.inputDraftRevision != inputDraftRevision {
            draftGeneration &+= 1
            onDraftGenerationChange?()
        }
        self.controller = controller
        self.draftIdentity = draftIdentity
        self.inputDraftRevision = inputDraftRevision
    }

    func recordDraftMutation() {
        draftGeneration &+= 1
        onDraftGenerationChange?()
    }

    func invalidateBinding(to controller: AppKitChatComposerEditorController) {
        guard self.controller === controller else {
            return
        }
        onWillInvalidate?()
        self.controller = nil
        draftIdentity = nil
        inputDraftRevision = nil
        draftGeneration &+= 1
        onDraftGenerationChange?()
    }

    func insertionContext() -> ComposerVoiceInsertionContext? {
        controller?.voiceInsertionContext()
    }

    func beginProvisionalTextReplacement() -> BlockInputProvisionalTextBeginResult {
        guard let view = controller?.view else {
            return .unavailable(.editorNotMounted)
        }
        return view.beginProvisionalTextReplacement()
    }

    func updateProvisionalTextReplacement(
        _ session: BlockInputProvisionalTextSession,
        text: String
    ) -> BlockInputProvisionalTextUpdateResult {
        controller?.view?.updateProvisionalTextReplacement(session, text: text) ?? .invalidated
    }

    func finishProvisionalTextReplacement(
        _ session: BlockInputProvisionalTextSession,
        disposition: BlockInputProvisionalTextDisposition
    ) -> BlockInputProvisionalTextFinishResult {
        controller?.view?.finishProvisionalTextReplacement(session, disposition: disposition) ?? .invalidated
    }
}

private extension AppKitChatComposerEditorController {
    var supportsVoiceInputSelection: Bool {
        guard let document = bridgeController?.documentStore.document else {
            return false
        }
        switch latestSelection {
        case .cursor(let cursor):
            guard let block = document.blocks.first(where: { $0.id == cursor.blockID }) else {
                return false
            }
            return block.kind.supportsVoiceInput && cursor.utf16Offset >= 0 && cursor.utf16Offset <= block.utf16Length
        case .text(let selection):
            guard let block = document.blocks.first(where: { $0.id == selection.blockID }) else {
                return false
            }
            let range = selection.range
            return block.kind.supportsVoiceInput &&
                range.location >= 0 &&
                range.length >= 0 &&
                range.location <= block.utf16Length &&
                range.length <= block.utf16Length - range.location
        case .blocks, .mixed:
            return false
        case nil:
            return document.blocks.contains { $0.kind.supportsVoiceInput }
        }
    }
}

extension BlockInputBlockKind {
    var supportsVoiceInput: Bool {
        switch self {
        case .horizontalRule, .table, .image:
            false
        case .paragraph, .heading, .code, .frontMatter, .quote,
             .bulletedListItem, .numberedListItem, .checklistItem, .rawMarkdown:
            true
        }
    }
}

extension ComposerVoiceInsertionContext {
    static func capture(blockText: String, range: NSRange) -> ComposerVoiceInsertionContext? {
        let text = blockText as NSString
        guard range.location >= 0,
              range.length >= 0,
              range.location <= text.length,
              range.length <= text.length - range.location else {
            return nil
        }

        let precedingText: String?
        if range.location > 0 {
            let precedingRange = text.rangeOfComposedCharacterSequence(at: range.location - 1)
            precedingText = text.substring(with: precedingRange)
        } else {
            precedingText = nil
        }

        let end = NSMaxRange(range)
        let followingText: String?
        if end < text.length {
            let followingRange = text.rangeOfComposedCharacterSequence(at: end)
            followingText = text.substring(with: followingRange)
        } else {
            followingText = nil
        }
        return ComposerVoiceInsertionContext(precedingText: precedingText, followingText: followingText)
    }
}
