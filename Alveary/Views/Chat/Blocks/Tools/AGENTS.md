## Tool Rows And Details

Rules for tool rows, groups, sub-agents, headers, and expanded details.

## Row Anatomy

- Tool transcript blocks render as inline rows, not bubble/pill chrome.
- Use `ToolHeaderRow` and `TranscriptDisclosureHeaderRow`: fixed leading slot, summary text column, fixed status slot.
- Keep slots near glyph size so rows do not grow wider or taller than needed.
- Bash rows use `dollarsign`; generic tools, groups, and sub-agents use a disclosure chevron; static approval headers use `lock.fill`.
- SwiftUI tool rows rotate one `chevron.right` with `appExpansionAnimation`; do not swap static chevrons there.
- AppKit tool rows use native `chevron.right`/`chevron.down` symbols instead of layer rotation so SF Symbol bounds stay stable.
- Keep `ToolStatusIndicator` inside the fixed status frame.
- Use `ProgressView()`, green `checkmark`, or red `xmark`; do not tint summary text red.
- Keep row padding in `TranscriptToolHeaderContent`.
- Expanded rows keep `transcriptToolExpandedContentTopSpacing` between header and content.
- Single tools use current tense while running and past tense when complete.
- Skill invocation rows use the `book` SF Symbol, stay standalone, and do not expand.
- Group headers stay current tense until all children complete, then switch every category summary to past tense.
- Preserve `TranscriptToolSummaryFormatter` so SwiftUI and AppKit inline-code, slash-command, and file-mention chips render together.

## Toggle And Expansion State

- Expand/collapse headers use `AppHeaderToggle`.
- Keep the plain SwiftUI `Button` path for keyboard and accessibility activation.
- `AppMouseTarget` should catch mouse hits only inside the control it overlays. Its AppKit local-monitor fallback is secondary to the SwiftUI button and exists for stale lazy-list hit regions after animated height changes.
- Keep pressed feedback routed through `AppHeaderToggle`.
- Do not move row toggling to scroll-view hit dispatch or bubble-wide gestures.
- Expanded `ToolDetails` stays as a sibling below the header so output selection and horizontal scrolling still work.
- `ChatTranscriptView` owns top-level expansion bindings keyed by `ChatItem.id`.
- Row-local state is only for previews, snapshots, and nested rows.
- Single-entry groups pass the parent-owned binding into `InlineToolRow`.

## Groups And Sub-Agents

- `ToolGroupBlock` owns grouping copy like `Reading 3 files, searching for 2 patterns`.
- Groups of size 1 render the single tool row directly.
- `StandaloneToolRow` delegates to `InlineToolRow`; never wrap standalone rows in a parent `ToolGroupBlock`.
- A single-agent `SubAgentBlock` expands directly to that agent's tool rows.
- Multi-agent expanded sub-agent blocks open each `SubAgentInlineRow` by default.
- `SubAgentBlock` uses the same explicit animation pattern as tool rows.

## Details And Connectors

- Expanded content routes through `ToolDetails`, `DetailCodeBlock`, `HighlightedCodeBlock`, or `ErrorContentBlock`.
- AppKit counterparts live under `../AppKit/`; keep their paging and syntax-highlighting behavior aligned with these SwiftUI views.
- Default `DetailCodeBlock` surfaces use the shared code palette chrome; keep tinted variants as explicit exceptions such as `stderr`.
- Shared tool-summary parsing lives in `TranscriptToolSummaryFormatter`; update SwiftUI and AppKit together when chip rules change.
- Do not dump raw text directly under a row.
- Inline row details are indented by `transcriptToolDetailLeadingInset`.
- Rounded code/output containers start under the summary column, not the leading icon.
- Do not "fix" expanded-detail trailing alignment by changing transcript scroll insets; those also affect user bubble alignment.
- Expanded details own bottom spacing; collapsed row padding must not change.
- Use `TranscriptElbowStack` / `TranscriptNestedToolRows` for nested connectors.
- Preserve connector geometry:
    - Vertical line starts at `transcriptToolNestedTopSpacing`.
    - Child rows use compact nested-row spacing.
    - `transcriptToolElbowGap` separates elbow tips from row frames.
- Track dynamic row centers through `TranscriptNestedRowCenterPreferenceKey`.

## Output And Status

- `ToolOutputView` owns output paging.
- `Bash` tails 10 lines; `Read` tails 20 lines.
- `Show N more` extends the window upward.
- Other tools render full output through `DetailCodeBlock`.
- Keep Bash tail-not-head behavior so streaming shows the latest line at the bottom.
- Thinking events are dropped by the grouper. Do not add a `ThinkingRow`/`ThinkingBlock`; `ActiveTurnThinkingIndicator` is the only thinking affordance.
- Tune tool dimensions only in `ChatBlocks.swift`.
- Use `ProgressView()` over a custom SwiftUI spinner; a prior custom spinner caused blank thread-open renders until scrolling.
- Multi-entry group headers use `DebouncedToolStatusIndicator`.
    - Terminal states wait 250ms.
    - Loading applies immediately when a new child streams in.
    - Prefer loading over partial failure while siblings run.
- `ToolStatusIndicator` branch swaps snap, but parent layout movement animates.
    - Use `.transaction(value: branchKey) { $0.animation = nil }`, not a bare `.transaction`.
    - `branchKey` only needs to change when spinner/checkmark/xmark branches change.
