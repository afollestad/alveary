struct ConversationInitialSetupSnapshot {
    let draft: String
    let draftSource: ComposerDraftSource
    let stagedContext: String?
    let stagedImageAttachments: [LocalImageAttachment]
    let stagedAppShots: [AppShotAttachment]

    init(
        draft: String,
        draftSource: ComposerDraftSource,
        stagedContext: String?,
        stagedImageAttachments: [LocalImageAttachment],
        stagedAppShots: [AppShotAttachment] = []
    ) {
        self.draft = draft
        self.draftSource = draftSource
        self.stagedContext = stagedContext
        self.stagedImageAttachments = stagedImageAttachments
        self.stagedAppShots = stagedAppShots
    }
}
