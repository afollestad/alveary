struct ConversationInitialSetupSnapshot {
    let draft: String
    let draftSource: ComposerDraftSource
    let stagedContext: String?
    let stagedImageAttachments: [LocalImageAttachment]
    let stagedFileAttachments: [LocalFileAttachment]
    let stagedAppShots: [AppShotAttachment]

    init(
        draft: String,
        draftSource: ComposerDraftSource,
        stagedContext: String?,
        stagedImageAttachments: [LocalImageAttachment],
        stagedFileAttachments: [LocalFileAttachment] = [],
        stagedAppShots: [AppShotAttachment] = []
    ) {
        self.draft = draft
        self.draftSource = draftSource
        self.stagedContext = stagedContext
        self.stagedImageAttachments = stagedImageAttachments
        self.stagedFileAttachments = stagedFileAttachments
        self.stagedAppShots = stagedAppShots
    }
}
