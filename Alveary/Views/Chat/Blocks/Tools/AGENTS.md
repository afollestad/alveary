## Tool Rows And Details

Rules for tool rows, groups, sub-agents, headers, and expanded details.

## Row Anatomy

- Tool transcript blocks render as inline rows, not bubble/pill chrome.
- Use AppKit header rows with fixed leading slot, summary text column, and fixed status slot.
- Keep slots near glyph size so rows do not grow wider or taller than needed.
- Bash rows use `dollarsign`; generic tools, groups, and sub-agents use a disclosure chevron; static approval headers use `lock.fill`.
- AppKit tool rows use native `chevron.right`/`chevron.down` symbols instead of layer rotation so SF Symbol bounds stay stable.
- Keep status indicators inside the fixed status frame.
- Use platform progress controls, green `checkmark`, or red `xmark`; do not tint summary text red.
- Expanded rows keep `transcriptToolExpandedContentTopSpacing` between header and content.
- Single tools use current tense while running and past tense when complete.
- Skill invocation rows use the `book` SF Symbol, stay standalone, and do not expand.
- Group headers stay current tense until all children complete, then switch every category summary to past tense.
- Preserve `TranscriptToolSummaryFormatter` so inline-code, slash-command, and file-mention chips render together.

## Toggle And Expansion State

- Expand/collapse headers use AppKit header toggle controls.
- Keep keyboard and accessibility activation on the row controls, not only mouse dispatch.
- Keep pressed feedback routed through the AppKit header control.
- Do not move row toggling to scroll-view hit dispatch or bubble-wide gestures.
- Expanded details stay as a sibling below the header so output selection and horizontal scrolling still work.
- `ChatTranscriptView` owns top-level expansion bindings keyed by `ChatItem.id`.
- Row-local state is only for previews, snapshots, and nested rows.
- Single-entry groups pass the parent-owned expansion state into the inline row.

## Groups And Sub-Agents

- Tool group rows own grouping copy like `Reading 3 files, searching for 2 patterns`.
- Groups of size 1 render the single tool row directly.
- Standalone tools use the same inline row primitive; never wrap standalone rows in a parent group.
- A single-agent sub-agent block expands directly to that agent's tool rows.
- Multi-agent expanded sub-agent blocks open each nested sub-agent row by default.
- Sub-agent blocks use the same explicit animation pattern as tool rows.

## Details And Connectors

- Expanded content routes through AppKit tool detail, code block, highlighted code block, or error content views.
- Default AppKit detail code block surfaces use the shared code palette chrome; keep tinted variants as explicit exceptions such as `stderr`.
- Shared tool-summary parsing lives in `TranscriptToolSummaryFormatter`; update AppKit rows and tests together when chip rules change.
- Shared tool-content extraction and output paging live in `TranscriptToolDetailPresentation.swift`; keep it UI-free so AppKit rows and tests can reuse the same parsing behavior.
- Markdown `Write`, `Edit`, and `MultiEdit` previews should also flow through `TranscriptToolDetailPresentation.swift`. Completed markdown mutation rows may auto-expand to show the preview; `Edit` and `MultiEdit` previews are provider-supplied replacement snippets, not reconstructed full-file contents.
- Do not dump raw text directly under a row.
- Inline row details are indented by `transcriptToolDetailLeadingInset`.
- Rounded code/output containers start under the summary column, not the leading icon.
- Do not "fix" expanded-detail trailing alignment by changing transcript scroll insets; those also affect user bubble alignment.
- Expanded details own bottom spacing; collapsed row padding must not change.
- Use AppKit nested tool rows for nested connectors.
- Preserve connector geometry:
    - Vertical line starts at `transcriptToolNestedTopSpacing`.
    - Child rows use compact nested-row spacing.
    - `transcriptToolElbowGap` separates elbow tips from row frames.
- Track dynamic row centers in AppKit layout, not SwiftUI preference keys.

## Output And Status

- AppKit tool output views own output paging.
- `Bash` tails 10 lines; `Read` tails 20 lines.
- `Show N more` extends the window upward.
- Other tools render full output through the AppKit detail code block.
- Keep Bash tail-not-head behavior so streaming shows the latest line at the bottom.
- Thinking events are dropped by the grouper. Do not add a persisted `ThinkingRow`/`ThinkingBlock`; the transient AppKit thinking indicator is the only thinking affordance.
- Tune tool dimensions only in `ChatBlocks.swift`.
- Use platform progress controls over custom spinners; a prior custom spinner caused blank thread-open renders until scrolling.
- Multi-entry group headers debounce terminal status indicators.
    - Terminal states wait 250ms.
    - Loading applies immediately when a new child streams in.
    - Prefer loading over partial failure while siblings run.
- Status indicator branch swaps should snap, while parent layout movement animates.
