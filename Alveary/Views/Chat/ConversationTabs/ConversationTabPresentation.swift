import Foundation
import SwiftData

/// Everything a conversation tab chip renders, plus the identifiers its actions re-resolve with,
/// snapshotted off the live `Conversation` while `ThreadDetailView.body` still holds one.
///
/// The tab strip and each chip re-run `body` from their *own* `@State` — the scroll-geometry
/// snapshot, a rename field's focus — with no parent pass in between, so either can fire after a
/// conversation delete has committed. A persisted-property read there traps inside SwiftData with
/// `_assertionFailure`. Value types cannot, so chips never store a model; actions hand back
/// `conversationModelID` for the parent to re-resolve.
struct ConversationTabPresentation: Equatable, Identifiable {
    let conversationModelID: PersistentIdentifier
    /// UUID-string `Conversation.id`, captured so removal's async path never re-reads the model.
    let conversationID: String
    /// Markdown-capable chip title.
    let displayName: String
    let plainDisplayName: String
    /// Seed for inline rename: the custom title when set, else the display name.
    let renameSeedText: String
    /// Snapshot of `ThreadDetailConversationDeletion.canRemove`; the commit-time guard in
    /// `removeConversation` stays the backstop for a stale value.
    let canRemove: Bool
    let status: ThreadStatus

    var id: PersistentIdentifier { conversationModelID }

    init(
        conversationModelID: PersistentIdentifier,
        conversationID: String,
        displayName: String,
        plainDisplayName: String,
        renameSeedText: String,
        canRemove: Bool,
        status: ThreadStatus
    ) {
        self.conversationModelID = conversationModelID
        self.conversationID = conversationID
        self.displayName = displayName
        self.plainDisplayName = plainDisplayName
        self.renameSeedText = renameSeedText
        self.canRemove = canRemove
        self.status = status
    }
}

extension ConversationTabPresentation {
    /// Declared in an extension so the memberwise initializer above survives for tests.
    @MainActor
    init(conversation: Conversation, status: ThreadStatus) {
        let displayName = conversation.displayName()
        self.init(
            conversationModelID: conversation.persistentModelID,
            conversationID: conversation.id,
            displayName: displayName,
            plainDisplayName: AppMarkdownInlineLabel.plainText(from: displayName),
            renameSeedText: conversation.customTitle ?? displayName,
            canRemove: ThreadDetailConversationDeletion.canRemove(conversation),
            status: status
        )
    }
}

/// The conversation a remove confirmation is armed against, captured as values.
///
/// A `confirmationDialog`'s `message:` closure re-evaluates on every host body pass for as long
/// as the dialog stays armed, so a `@Model` held here would let the message read a row that a
/// delete committed in the meantime and trap inside SwiftData — the same contract as
/// `SidebarPendingThreadCleanup`. The destructive button passes the stored identifiers straight
/// into `removeConversation(id:conversationIDString:)`, which re-resolves live.
struct ThreadDetailPendingConversationRemoval: Equatable {
    let conversationModelID: PersistentIdentifier
    let conversationID: String
    let displayName: String

    init(tab: ConversationTabPresentation) {
        conversationModelID = tab.conversationModelID
        conversationID = tab.conversationID
        displayName = tab.plainDisplayName
    }
}
