## AppKit Transcript Blocks

AppKit-native transcript row primitives live here, because SwiftUI lazy-list recycling and measurement could not hold Alveary's variable-height transcript without scroll-position and performance problems. Host MCP tool cards are `Alveary/Views/Chat/Blocks/AppKit/Widgets/AGENTS.md`; `Alveary/Views/Chat/AGENTS.md` owns the rule that transcript rows stay AppKit.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `AppKitTranscriptTextBubbleRowView`'s exact overflow measurement, `AppKitTranscriptApprovalSplitControl`'s independently dimming halves, `AppKitTranscriptPullRequestPromptView`'s alignment and select-never-act menus, and `AppKitScheduledTaskListDetailView`'s grid, connector, and empty state each carry theirs.

### Row Contract

- **Stay adapter-friendly.** Keep rows configured through explicit data objects so the AppKit transcript container can cache and refresh them by stable id.
- **Own height invalidation.** Rows must invalidate intrinsic height and call their height handler when markdown, expansion, toggles, or width changes alter layout.
- **Use dynamic color primitives.** A row writing dynamic colors into layer `CGColor`s or `contentTintColor` takes the shared helpers from `Components/AppKit`, so theme changes need no leaf-specific appearance observer.
- **Use flipped row containers.** Layer-backed child containers inside flipped transcript rows should also be flipped, such as `AppKitFlippedDynamicColorView`; an unflipped container lays out prompt/tool children bottom-up.
- **Keep identity stable.** Row ids come from `ChatItem.id` or the row's stable child id, never a generated view-lifetime id, and nested tool and sub-agent rows reuse child views by stable child id so local expansion survives a parent refresh.
- **Share semantics.** Use shared markdown, typography, and transcript constants; do not fork parser or palette behavior here.
- **Treat typography as live configuration.** Chat font size and code font family/size changes flow through `TranscriptTypography`, reconfigure cached rows, and invalidate measured heights instead of requiring row recreation.

### Tool, Approval, And Prompt Rows

- **Mirror the tool-row rules owned by `Alveary/Views/Chat/Blocks/Tools/AGENTS.md`** — output paging, code highlighting, no-output behavior, the shared summary formatter, non-expandable Skill rows, and sub-agent expansion shapes all match the SwiftUI rules there.
- **Prewarm tool details.** Collapsed inline tool rows prepare their retained details view offscreen after configuration so the first expansion does not synchronously pay detail construction cost.
- **Ignore expansion echoes.** Local AppKit expand/collapse updates are echoed back through SwiftUI as persisted row ids; rebuilding an unchanged tool row for that echo interrupts coordinated frame animations.
- **Clip expandable row containers to bounds.** Expanded children may be laid out at target height before the row's frame animation reaches it.
- **Debounce group status.** Multi-tool AppKit group headers delay terminal icons like SwiftUI so streaming siblings do not flash done.
- **Mirror approvals.** AppKit approval blocks read copy, summaries, session scopes, and resolved-state labels from `ToolApprovalRequest`.
- **Hug approval bubbles.** Measure natural header/summary/action width and cap only at transcript max width, and keep the SwiftUI button sizing, split-button chrome, hover/press feedback, and denial-slot animation.
- **Defer measured animations.** Measurement can call `layoutSubtreeIfNeeded()` before a row is visibly presented, so a SwiftUI-parity animation captures stable start/end state, leaves measured frames final during layout, then queues interpolation on the next main-queue pass.
- **Mirror prompts.** AppKit prompt blocks share submitted-response parsing and keep custom responses serialized as typed text.
- **Keep prompt toggles cheap.** Update existing option rows in place, and do not force synchronous whole-window display from click tracking.

### Streaming And Transient Rows

- **Do not animate streaming frames.** Streaming bubbles update faster than AppKit frame animations finish; reveal text monotonically and update bubble/text/caret frames directly so stale animation frames cannot flash or rewind the row.
- **Keep streaming monotonic.** Live bubble text only advances within a mounted stream: ignore stale shorter partials, and place the cursor at the final line's insertion advance rather than the full line width or the last glyph's ink bounds.
- **Mirror task lists.** AppKit task rows share SwiftUI ordering/accessibility labels and keep 16pt status slots stable across progress changes.
- **Mirror notes and errors.** AppKit transcript notes are text-only and follow `TranscriptNoteAlignment`; error rows mirror inline-banner width caps and red chrome.
- **Keep transient rows lightweight** — inherit transcript typography, report streaming height changes directly, and reveal appended text over frames instead of swapping whole provider chunks.
- **Align transient indicators.** Standalone working/thinking indicators align their dots with row-leading content, not text-bubble interior padding.

### Text Bubbles And Hydration

- **A hydrated shell must stay layout-neutral.** The shell reserves its measured markdown slot first, and hydration attaches into that slot rather than forcing a full row layout that could perturb document height or scroll anchors; a measurement mismatch falls back to synchronous hydrated measurement.
- **Token async prep.** Off-main markdown document preparation is accepted only when the row id, content, width, typography, appearance, expansion, and retry inputs still match; stale results may not hydrate or invalidate removed rows.
- **Mirror user retries.** AppKit user bubbles preserve the `Not sent` footer and retry callback when a persisted send is retryable.

### Custom Tool Detail Views

`AppKitTranscriptToolDetailsView` renders a custom view for a tool ahead of the usual extractors, as it does `AppKitScheduledTaskListDetailView` for `list_scheduled_tasks`. Such a view is still an ordinary tool row's expanded detail, not a widget.

- **Report your own height.** The container hands each child a full-width frame with an unbounded height and reads back `intrinsicContentSize`, falling back to `fittingSize`. A child pinned on all four edges stretches into that frame and lays out over the header; pin top/leading/trailing only.
- **Render an empty result as a row, not blank space.** The custom view replaces the Input/Output blocks, so nothing else fills the gap when the tool returns nothing.
- **Reuse `AppKitTranscriptElbowConnectorView` for nested content** so custom detail reads as a hierarchy like grouped tools and parallel sub-agents.
- **Forward a detail view's actions down every fork.** A groupable tool also travels `AppKitTranscriptActivityGroupView` → `AppKitTranscriptMixedActivityRowsView`, and `AppKitTranscriptToolGroupView` renders a one-tool group through `singleToolRow`. A missed fork fails silently on the default no-op handlers, so `ScheduledTaskListToolRowTests` drives the real factory tree.

### Approval Split Control

- **`AppKitTranscriptApprovalSplitControl`'s `primaryIcon` and `actionStyle` default to the approval look.** Changing those defaults shifts every approval baseline, so keep new callers configuring the properties instead.
- Transcript buttons take the same `ActionIcon` values as SwiftUI (see `Alveary/Views/Components/AGENTS.md`), so a concept keeps one glyph across surfaces. They paint their own contents, so `NSButton.image` and its positioning properties are inert — set `icon`.
- **An octicon must be tinted from the button's resolved title colour**, which `ActionIcon.nsImage(side:color:)` does; that is what dims the glyph with its label, the way `hierarchicalColor` does for SF Symbols.
