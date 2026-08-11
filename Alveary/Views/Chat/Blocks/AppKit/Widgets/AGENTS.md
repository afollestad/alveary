## Host Tool Transcript Widgets

These instructions cover `Alveary/Views/Chat/Blocks/AppKit/Widgets/` — the card an Alveary host MCP tool renders as: the shell (`AppKitTranscriptHostToolWidgetRowView`), its header pieces, and the per-feature body views. Enrolling a tool, its descriptor, and what the shell reads off `HostToolWidgetEntry` are `Alveary/Services/Agent/Transcript/HostToolWidgets/AGENTS.md`; the summary sentence a card shows is `HostToolWidgetSummary`. An ordinary tool row and its expanded detail are `Alveary/Views/Chat/Blocks/AppKit/AGENTS.md`.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: the shell's chrome and content hugging, `AppKitHostToolWidgetBubbleView`'s scroll- and resize-aware hover, `AppKitHostToolWidgetIconView` and `AppKitHostToolWidgetDisclosureSlotView`'s optical centering, `AppKitPullRequestListWidgetView`'s inert card and per-row controls, `AppKitReviewInstructionsWidgetView`'s view-local expansion, and the whole review-proposal diff preview each carry theirs.

### Adding A Widget

- **A widget is a status block, not a form.** The shell owns chrome, the summary line, and measurement; a feature contributes only a body view selected by `HostToolWidgetContent`.
- **Card-level interaction belongs on the shell's bubble, gated per configured content.** Every body sits in the shell's stack whether or not it is the configured one, so a body carrying its own always-pressable bubble makes an unrelated card's shell answer as a button — `PullRequestLinkWidgetRowTests` and `ThreadActionWidgetRowTests` assert against exactly that.
- **A new header glyph centers on the summary's cap height**, as the icon and disclosure slots do. AppKit's own baseline rides square octicon artwork high above the text.
- **A card that changes size must republish its row height.** The transcript measures rows from their content, so an expansion, a loaded inline image, or a removed comment that skips `onHeightInvalidated` leaves every row below it at the old offset.
- **Keep expansion two-way and content-scoped.** A grown card folds back through the same control, and only a change of *content* resets it — a reconfigure that merely restyles the rows must not collapse the card under the user.
- **Send real editing to the app's own surface.** A proposal's create/edit review opens `ScheduledTaskEditorPane`, so the card never grows a second form; `Alveary/Views/Scheduled/AGENTS.md` owns that routing.
- **A card that opens a pane shows no progress for it** — no waiting state in the chevron's slot, and no transcript-scoped state feeding one. `Alveary/App/Routing/AGENTS.md` owns why.

### The Instructions Card

- **It reveals, it does not navigate.** Checking what the agent was told must not leave the work the call is starting, so this is the one card the shell makes pressable without an `openableTarget`.
- **One card serves both `get_pr_review_instructions` and `get_pr_address_feedback_instructions`.** `ReviewInstructionsWidgetContent.Kind` may change only the summary sentence, never a glyph, control, or measurement, so a third instruction tool needs a case rather than a view.

### Review Proposal

`AppKitReviewProposalWidgetView` is the one widget that edits its own decision: the model proposes a verdict, the user changes it through the split control's menu, and confirming awaits GitHub. `Alveary/Views/PullRequests/Review/AGENTS.md` owns what the preview shows, what its two badges mean, and the one action a staged comment has.

- **Rebuild the pane's controls, do not invent transcript ones.** The comment card's jump and three-dot menu read their title, glyph, hit target, and tint from `PullRequestCommentActionsMenu` and `PullRequestCommentRevealAction` rather than respelling them: AppKit cannot mount the SwiftUI originals, and a part that drifts here stops reading as the same control.
