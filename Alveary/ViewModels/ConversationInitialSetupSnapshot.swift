struct ConversationInitialSetupSnapshot {
    let draft: String
    let draftSource: ComposerDraftSource
    let stagedContext: String?
    let stagedImageAttachments: [LocalImageAttachment]
}
