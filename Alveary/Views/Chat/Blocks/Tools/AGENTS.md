## Tool Rows And Details

Rules for tool rows, groups, sub-agents, headers, and expanded details.

## Row Anatomy

- Tool transcript blocks render as inline rows, not bubble/pill chrome.
- Use AppKit header rows with dynamic leading slot, summary text column, and dynamic status slot derived from `TranscriptTypography`.
- Keep slots near glyph size so rows do not grow wider or taller than needed.
- Tool rows use semantic SF Symbols:
    - Command-like rows such as `Bash` and `CommandExecution` use `terminal`.
    - `LS` uses `folder`; grep/glob/search rows use `magnifyingglass`.
    - `Read`, grep, glob, and search rows use `magnifyingglass`; `Skill` uses `book`; write/edit rows use `pencil`.
- Static approval headers use `lock.fill`.
- Do not use chevron/caret symbols as the leading inline tool-row icon. Expansion state is available through row accessibility state, not the visible glyph.
- Keep status indicators inside the dynamic status frame.
- Terminal tool rows do not show trailing success/error glyphs. Collapsed rows reveal the rotating disclosure chevron only on row hover; expanded rows may keep the chevron visible.
- Inline tool rows use `transcriptInlineToolRowColor` for leading icons, summary text, loading spinners, and disclosure chevrons. Approval prompts keep separate approval typography and chrome.
- Inline code and chip backgrounds inside tool summaries should stay lighter than regular markdown chips so they do not overpower muted row text.
- Expanded rows keep `transcriptToolExpandedContentTopSpacing` between header and content.
- Inline rows use `transcriptInlineToolRowVerticalPadding`; keep approval prompt spacing on its separate approval layout path.
- Single tools use current tense while running and past tense when complete.
- Skill invocation rows use the `book` SF Symbol, stay standalone, and do not expand.
- Completed no-output rows that would render empty details should not show disclosure state or button accessibility; use a static icon instead.
- Group headers stay current tense until all children complete, then switch every category summary to past tense.
- Preserve `TranscriptToolSummaryFormatter` so inline-code, slash-command, and file-mention chips render together.

## Toggle And Expansion State

- Expand/collapse headers use AppKit header toggle controls.
- Keep keyboard and accessibility activation on the row controls, not only mouse dispatch.
- Keep pressed feedback routed through the AppKit header control.
- Do not move row toggling to scroll-view hit dispatch or bubble-wide gestures.
- Expanded details stay as a sibling below the header so output selection and horizontal scrolling still work.
- `ChatTranscriptView` owns top-level expansion bindings keyed by visible row ids; visual activity groups use prefixed ids such as `activity-...`.
- Row-local state is only for previews, snapshots, and nested rows.
- Single-entry groups pass the parent-owned expansion state into the inline row.

## Groups And Sub-Agents

- Collapsed visual activity-group headers use generic grouping copy like `Read 2 files, searched code, and edited 1 file`.
- Groups of size 1 render the single tool row directly with specific text.
- Standalone tools use the same inline row primitive and stay specific when alone; adjacent standalone tools may be visually wrapped in an activity group.
- `AskUserQuestion` prompt usage rows participate in the same visual activity grouping as tool and sub-agent rows.
    - Pending prompts summarize as `Asking N question(s)` and are not expandable.
    - Submitted prompts summarize as `Asked N question(s)` and expand to question/answer details.
- Expanded visual activity-group children keep their specific row text, file names, commands, and nested details.
- A single-agent sub-agent block expands directly to that agent's tool rows.
- Multi-agent expanded sub-agent blocks show nested sub-agent rows collapsed until explicitly opened.
- Sub-agent blocks use the same explicit animation pattern as tool rows.

## Details And Connectors

- Expanded content routes through AppKit tool detail, code block, highlighted code block, or error content views.
- Default AppKit detail code block surfaces use the shared code palette chrome; keep tinted variants as explicit exceptions such as `stderr`.
- Shared tool-summary parsing lives in `TranscriptToolSummaryFormatter`; update AppKit rows and tests together when chip rules change.
- Shared tool-content extraction and output paging live in `TranscriptToolDetailPresentation.swift`; keep it UI-free so AppKit rows and tests can reuse the same parsing behavior.
- Markdown `Write`, `Edit`, and `MultiEdit` previews should also flow through `TranscriptToolDetailPresentation.swift`. Markdown mutation tool rows are manual-expansion-only; completed rows must not auto-expand. Known markdown `Edit` and `MultiEdit` rows should render reconstructed full-document previews from `ToolEntry.previewOverride`; unknown markdown edits should fall back to provider-supplied replacement snippets. `exitPlanModeFollowUp` previews replace the tool row with an assistant-style plan bubble, not a pre-expanded tool detail.
- Do not dump raw text directly under a row.
- Inline row details are indented by the dynamic inline tool-row summary-column inset.
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
- Command-like tools such as `Bash` and `CommandExecution` tail 10 lines; `Read` tails 20 lines.
- `Show N more` extends the window upward.
- Other tools render full output through the AppKit detail code block.
- Keep command-tool tail-not-head behavior so streaming shows the latest line at the bottom.
- Thinking events are dropped by the grouper. Do not add a persisted `ThinkingRow`/`ThinkingBlock`; the transient AppKit thinking indicator is the only thinking affordance.
- Tune tool dimensions only in `ChatBlocks.swift`.
- Use `AppKitStatusIndicatorSpinner` for AppKit tool-row loading states; keep spinner construction centralized instead of adding one-off loading animations.
- Transcript tool-row loading spinners are intentionally sized from inline tool-row metrics; do not change task-list/sidebar/tab spinner sizing when tuning tool rows.
- Multi-entry group headers debounce terminal status indicators.
    - Terminal states wait 250ms.
    - Loading applies immediately when a new child streams in.
    - Prefer loading over partial failure while siblings run.
- Status indicator branch swaps should snap, while parent layout movement animates.
