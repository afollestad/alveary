## AppKit Transcript Blocks

AppKit-native transcript row primitives live here.

- **Prefer AppKit here.** Transcript rows are AppKit-owned because SwiftUI lazy-list recycling and measurement were not adequate for Alveary's variable-height transcript UX at the time of writing; they caused scroll-position and performance issues.

### Row Contract

- **Stay adapter-friendly.** Keep rows configured through explicit data objects so the AppKit transcript container can cache and refresh them by stable id.
- **Own height invalidation.** Rows must invalidate intrinsic height and call their height handler when markdown, expansion, toggles, or width changes alter layout.
- **Use dynamic color primitives.** If a row writes dynamic colors into layer `CGColor`s or `contentTintColor`, use the shared AppKit dynamic-color/tint helpers from `Components/AppKit` so theme changes do not require fragile leaf-specific appearance observers.
- **Use flipped row containers.** Layer-backed child containers inside flipped transcript rows should also be flipped, such as `AppKitFlippedDynamicColorView`; an unflipped container will lay out prompt/tool children bottom-up.
- **Keep identity stable.** Row ids should come from `ChatItem.id` or the row's stable child id, not generated view lifetime ids.
- **Preserve nested identity.** Nested tool and sub-agent rows should reuse child views by stable child id so local child expansion survives parent refreshes.
- **Share semantics.** Use shared markdown, typography, and transcript constants; do not fork parser or palette behavior here.
- **Treat typography as live configuration.** Chat font size and code font family/size changes must flow through `TranscriptTypography`, reconfigure cached rows, and invalidate measured heights instead of requiring row recreation.

### Tool, Approval, And Prompt Rows

- **Mirror the tool-row rules owned by `Tools/AGENTS.md`** — output paging, code highlighting, no-output behavior, the shared summary formatter, non-expandable Skill rows, and sub-agent expansion shapes all match the SwiftUI rules there.
- **Prewarm tool details.** Collapsed inline tool rows should prepare their retained details view offscreen after configuration so the first user expansion does not synchronously pay detail construction cost.
- **Ignore expansion echoes.** Local AppKit expand/collapse updates are echoed back through SwiftUI as persisted row ids; do not rebuild unchanged tool rows for that echo or it can interrupt coordinated frame animations.
- **Clip expandable rows.** Expandable row containers must clip to bounds because expanded children may be laid out at target height before the row's frame animation reaches that height.
- **Debounce group status.** Multi-tool AppKit group headers delay terminal icons like SwiftUI so streaming siblings do not flash done.
- **Mirror approvals.** AppKit approval blocks read copy, summaries, session scopes, and resolved-state labels from `ToolApprovalRequest`.
- **Hug approval bubbles.** Approval blocks should measure natural header/summary/action width and only cap at transcript max width; custom AppKit action controls must preserve the SwiftUI button sizing, split-button chrome, hover/press feedback, and denial-slot animation.
- **Defer measured animations.** Measurement can call `layoutSubtreeIfNeeded()` before a row is visibly presented; SwiftUI-parity animations such as approval-slot moves should capture stable start/end state, leave measured frames final during layout, then queue interpolation on the next main-queue pass.

### Streaming And Transient Rows

- **Do not animate streaming frames.** Streaming bubbles update faster than AppKit frame animations finish; reveal text monotonically and update bubble/text/caret frames directly so stale animation frames cannot flash or rewind the row.
- **Mirror prompts.** AppKit prompt blocks share submitted-response parsing and keep custom responses serialized as typed text.
- **Mirror task lists.** AppKit task rows share SwiftUI ordering/accessibility labels and keep 16pt status slots stable across progress changes.
- **Mirror notes and errors.** AppKit transcript notes are text-only and follow `TranscriptNoteAlignment`; error rows mirror inline-banner width caps and red chrome.
- **Mirror transient rows.** AppKit streaming and thinking rows should stay lightweight, inherit transcript typography, report streaming height changes directly, and reveal appended streaming text over frames instead of swapping whole provider chunks.
- **Align transient indicators.** Standalone working/thinking indicators align their dots with row-leading content, not text-bubble interior padding.
- **Keep streaming monotonic.** Live streaming bubble text should only advance within a mounted stream; ignore stale shorter partials, and place the cursor at the final line's insertion advance rather than the full line width or the last glyph's ink bounds.

### Text Bubbles And Hydration

- **Trust rendered overflow.** AppKit text bubbles have exact markdown height measurements; do not reuse raw markdown line-count or character-count heuristics to decide whether Show more/less is needed.
- **Preserve shell invariants.** Text-bubble shells reserve their measured markdown slot before hydration; hydrated markdown must not change row height, and any mismatch should fall back through synchronous hydrated measurement.
- **Hydrate into measured slots.** Viewport hydration should attach markdown views into the existing measured slot instead of forcing a full row layout that can perturb document height or scroll anchors.
- **Token async prep.** Off-main markdown document preparation must be accepted only when the row id, content, width, typography, appearance, expansion, and retry inputs still match; stale results may not hydrate or invalidate removed rows.
- **Mirror user retries.** AppKit user bubbles must preserve the `Not sent` footer and retry callback when a persisted send is retryable.
- **Keep prompt toggles cheap.** Update existing prompt option rows in place and avoid synchronous whole-window display from click tracking.
- **Host MCP widgets are status blocks, not forms.** `AppKitTranscriptHostToolWidgetRowView` owns chrome, the one-line summary from `HostToolWidgetSummary`, and measurement; each feature adds a body view selected by `HostToolWidgetContent`. Copy stays present-tense while running and past-tense once resolved (`Creating new scheduled task…` → `Created new scheduled task: <name>`), with the leading glyph carrying state.
- **Reuse `AppKitTranscriptElbowConnectorView` for nested content**, as the scheduled-task list detail does, so custom detail reads as a hierarchy like grouped tools and parallel sub-agents. Two traps: size the connector from the content's own height rather than `bounds` (the container is still probing with an unbounded frame), and *convert* row centers into the connector's space instead of offsetting them — `NSGridView` is unflipped while transcript rows are flipped, so offsetting inverts row order and stops the trunk at the first row.
- **A custom tool-detail view must report its own height.** `AppKitTranscriptToolDetailsView` hands each child a full-width frame with an unbounded height and reads the height back from `intrinsicContentSize`, falling back to `fittingSize`. A child that pins its content to all four edges stretches into that unbounded frame and lays out on top of the header; pin top/leading/trailing only and override `intrinsicContentSize`.
- **A custom tool-detail view must surface its own errors and its own empty state.** It replaces the Input/Output blocks, so a failed call renders the error first and an empty result still renders a row — otherwise the row answers with host state the tool never returned, or with blank space.
- **`list_scheduled_tasks` is an ordinary tool row, not a widget.** Only its expanded detail is custom: `AppKitTranscriptToolDetailsView` renders `AppKitScheduledTaskListDetailView` for it, ahead of the usual extractors. Rows come from `ScheduledTasksViewModel` rather than the tool payload, so the row shows current status and still works for providers that surface only the tool's text fallback; each row's Edit opens the shared editor pane scoped to the originating thread. The live rows and that action reach the detail view through `scheduledTaskListActions`, forwarded down the same chain as `onOpenToolImage`. That chain forks more than it looks: the list tool is groupable, so it also travels the activity-group path (`AppKitTranscriptActivityGroupView` → `AppKitTranscriptMixedActivityRowsView`), and `AppKitTranscriptToolGroupView` renders a one-tool group through `singleToolRow` rather than `nestedRowsView`. Missing a fork fails silently — the detail view still builds, just with the default no-op handlers — so `ScheduledTaskListToolRowTests` drives the real factory tree and asserts the action arrives.
- **Hug host MCP widgets.** The card measures its natural header, detail, and body width and only caps at `bubbleMaxWidth`, like approval bubbles. The proposal body's action row carries a flexible spacer, so its natural width comes from the buttons, not the row.
- **Keep editing out of the transcript.** A scheduling proposal's create/edit review opens the shared `ScheduledTaskEditorPane` in the right-pane lane so it gets the app's real controls and full section set; the row only offers Reject plus Review or an in-place confirm.

### Pull-Request Link Prompts

- `AppKitTranscriptPullRequestPromptView` asks whether a pull request found in the message above should be linked. Its alignment follows the anchoring bubble — user messages trailing, assistant leading — so the question reads as belonging to that message.
- **Its split menus select, never act**, matching the rule in `Views/Components/AGENTS.md`: the menu swaps `Yes`→`Always` / `No`→`Never`, and only the primary half runs the selected action.
- **`AppKitTranscriptApprovalSplitControl`'s `primarySymbolName` and `actionStyle` default to the approval look.** Changing those defaults shifts every approval baseline, so keep new callers configuring the properties instead.
