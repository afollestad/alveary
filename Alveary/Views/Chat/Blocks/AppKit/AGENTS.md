## AppKit Transcript Blocks

AppKit-native transcript row primitives live here.

- **Prefer AppKit here.** Transcript rows are AppKit-owned because SwiftUI lazy-list recycling and measurement were not adequate for Alveary's variable-height transcript UX at the time of writing; they caused scroll-position and performance issues.
- **Stay adapter-friendly.** Keep rows configured through explicit data objects so the AppKit transcript container can cache and refresh them by stable id.
- **Own height invalidation.** Rows must invalidate intrinsic height and call their height handler when markdown, expansion, toggles, or width changes alter layout.
- **Use dynamic color primitives.** If a row writes dynamic colors into layer `CGColor`s or `contentTintColor`, use the shared AppKit dynamic-color/tint helpers from `Components/AppKit` so theme changes do not require fragile leaf-specific appearance observers.
- **Use flipped row containers.** Layer-backed child containers inside flipped transcript rows should also be flipped, such as `AppKitFlippedDynamicColorView`; an unflipped container will lay out prompt/tool children bottom-up.
- **Keep identity stable.** Row ids should come from `ChatItem.id` or the row's stable child id, not generated view lifetime ids.
- **Preserve nested identity.** Nested tool and sub-agent rows should reuse child views by stable child id so local child expansion survives parent refreshes.
- **Share semantics.** Use shared markdown, typography, and transcript constants; do not fork parser or palette behavior here.
- **Treat typography as live configuration.** Chat font size and code font family/size changes must flow through `TranscriptTypography`, reconfigure cached rows, and invalidate measured heights instead of requiring row recreation.
- **Mirror tool output rules.** AppKit tool detail views must preserve SwiftUI paging, code highlighting, and no-output behavior.
- **Mirror tool rows.** AppKit tool headers and groups must use the shared summary formatter and keep Skill rows non-expandable.
- **Prewarm tool details.** Collapsed inline tool rows should prepare their retained details view offscreen after configuration so the first user expansion does not synchronously pay detail construction cost.
- **Ignore expansion echoes.** Local AppKit expand/collapse updates are echoed back through SwiftUI as persisted row ids; do not rebuild unchanged tool rows for that echo or it can interrupt coordinated frame animations.
- **Clip expandable rows.** Expandable row containers must clip to bounds because expanded children may be laid out at target height before the row's frame animation reaches that height.
- **Debounce group status.** Multi-tool AppKit group headers delay terminal icons like SwiftUI so streaming siblings do not flash done.
- **Mirror sub-agents.** Single AppKit sub-agent blocks expand directly to tool/result content; multi-agent blocks keep nested agents open by default.
- **Mirror approvals.** AppKit approval blocks read copy, summaries, session scopes, and resolved-state labels from `ToolApprovalRequest`.
- **Hug approval bubbles.** Approval blocks should measure natural header/summary/action width and only cap at transcript max width; custom AppKit action controls must preserve the SwiftUI button sizing, split-button chrome, hover/press feedback, and denial-slot animation.
- **Defer measured animations.** Measurement can call `layoutSubtreeIfNeeded()` before a row is visibly presented; SwiftUI-parity animations such as approval-slot moves should capture stable start/end state, leave measured frames final during layout, then queue interpolation on the next main-queue pass.
- **Do not animate streaming frames.** Streaming bubbles update faster than AppKit frame animations finish; reveal text monotonically and update bubble/text/caret frames directly so stale animation frames cannot flash or rewind the row.
- **Mirror prompts.** AppKit prompt blocks share submitted-response parsing and keep custom responses serialized as typed text.
- **Mirror task lists.** AppKit task rows share SwiftUI ordering/accessibility labels and keep 16pt status slots stable across progress changes.
- **Mirror notes and errors.** AppKit centered notes keep the `info.circle` treatment with compact vertical padding; error rows mirror inline-banner width caps and red chrome.
- **Mirror transient rows.** AppKit streaming and thinking rows should stay lightweight, inherit transcript typography, report streaming height changes directly, and reveal appended streaming text over frames instead of swapping whole provider chunks.
- **Align transient indicators.** Standalone working/thinking indicators align their dots with row-leading content, not text-bubble interior padding.
- **Keep streaming monotonic.** Live streaming bubble text should only advance within a mounted stream; ignore stale shorter partials, and place the cursor at the final line's insertion advance rather than the full line width or the last glyph's ink bounds.
- **Trust rendered overflow.** AppKit text bubbles have exact markdown height measurements; do not reuse raw markdown line-count or character-count heuristics to decide whether Show more/less is needed.
- **Preserve shell invariants.** Text-bubble shells reserve their measured markdown slot before hydration; hydrated markdown must not change row height, and any mismatch should fall back through synchronous hydrated measurement.
- **Hydrate into measured slots.** Viewport hydration should attach markdown views into the existing measured slot instead of forcing a full row layout that can perturb document height or scroll anchors.
- **Token async prep.** Off-main markdown document preparation must be accepted only when the row id, content, width, typography, appearance, expansion, and retry inputs still match; stale results may not hydrate or invalidate removed rows.
- **Mirror user retries.** AppKit user bubbles must preserve the `Not sent` footer and retry callback when a persisted send is retryable.
