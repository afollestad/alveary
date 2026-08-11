# Flattened Diff Preview

These instructions cover `Alveary/Views/DiffViewer/Preview/` — `FlattenedDiffPreview`, its row stream and width measurement, the image preview, and the comment rows the pull-request pane renders through it. The pane that hosts it in the diff viewer is `Alveary/Views/DiffViewer/Pane/`.

**`FlattenedDiffPreview` has two hosts, and the second one is why most rules here exist.** The diff viewer renders it inert; the pull-request Changes tab drives it with comment annotations and interaction. A new parameter must keep the inert path's row stream byte-identical, or the diff viewer inherits pull-request chrome.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Most of this scope's mechanism is documented where it lives: `FlattenedDiffPreview`'s inset, caret-axis, and scroll-target properties (`scrollTarget`'s absence from `renderFingerprint`, `collapseCaretAxis` and its `fileHeaderTrailingExtension` derivation), `DiffPreviewWidthEstimator`'s measured metrics, `DiffPreviewScrollOffset`'s reference-type identity, `DiffCommentAnchor` / `DiffLineComment` / `DiffLineCommentThread` / `DiffCommentAnnotations` / `DiffCommentInteraction`'s per-field contracts, `DiffCommentCardChrome`, `DiffCommentRowWash`, and `DiffCommentCardInteriorPadding`'s arithmetic against the scroll indicator each carry theirs.

## Row Stream

- **One lazy row stream carries file headers, hunk headers, and line rows together**, across one or more `DiffFile` values — both diff viewer modes and the PR Changes tab render through it rather than nesting per-file previews. Large row models are prepared off the main actor.
- **Collapse commit file diffs only.** File-diff collapse is a Commits-mode affordance; Current changes shows no collapse caret. Keep collapse filtering inside the flattened row stream, animate reflow with transcript expansion timing, and reuse transcript header-toggle activation for the full-path header hit target.

## Host Insets

- **`contentTopInset` and `horizontalContentInset` are opt-in and scroll with the content**, which is the whole point: host-side padding would clip scrolled rows at a fixed top gap, and sideways it would inset the scroller along with the content instead of letting the scroll bars sit flush with the pane edge. The PR pane passes both; the diff viewer keeps the defaults (`0` and `diffPreviewHorizontalInset`). **The PR pane passes its pane inset alone** — adding the preview's own on top pushed the Changes tab 6pt deeper than every sibling surface.
- **`collapseCaretAxis` opts a host's file headers onto a trailing glyph lane**, and a host that passes it buys that much horizontal scroll range — the header frame reaches past the viewport, so even a fitting diff can be nudged sideways. See **Pane Insets And Chrome** in `Alveary/Views/Components/Panes/AGENTS.md`, which owns the rule.

## Scrollable Width

- **Only rows that render `fixedSize(horizontal: true)` contribute to `minimumScrollableContentWidth`.** A row contributing `0` must also clamp its rendered width to the viewport — `diffPreviewViewportContentWidthFrame()` for file headers, `DiffCommentRowWidthModifier` for comment rows — because the scroll container proposes nil width in its scroll axes, so an unclamped row's untruncated ideal widens the diff anyway.
- **Clamp to the viewport, never to the scrollable width.** The two are equal only while the diff fits; past that, clamping to the scrollable width pushes the file header's badges and collapse caret off the pane the moment a line overflows.
- `SnapshotTests+DiffViewerScroll.swift` guards both directions: fitting diffs must report zero horizontal overflow, long lines must still scroll with their headers clamped and pinned.

## Comment Rows

- **A comment row is only ever emitted from a rendered line row.** The builder walks lines asking whether each has a thread; it never asks a thread whether it found a line, so an anchor matching nothing is dropped silently. Three things can hide the line — context collapsing, file collapse, and the paging window. `DiffPreviewHunkDisplayRows.makeRows(for:commentPath:commentAnchors:)` takes the anchors so a commented context line survives collapsing; callers with no annotations pass an empty set. The other two are the pull-request pane's to reveal — see `PullRequestsViewModel.revealDiffFile(containing:)`.
    - **`propose_pr_review` validates anchors through the same `commentAnchor(for:path:)` mapping**, so a proposal cannot stage a comment the pane is unable to draw; see `Alveary/Services/PullRequests/HostTools/AGENTS.md`.
- **Anchors follow the GitHub model** — added and context lines anchor RIGHT on the new line number, deleted lines anchor LEFT on the old. `DiffCommentAnnotations` participates in the render fingerprint, so a changed thread or composer anchor must rebuild prepared rows.
- **Comment chrome is interaction-supplied**, so every affordance is absent on the diff viewer's inert path rather than conditionally hidden. A new affordance follows that shape: read it off `DiffCommentInteraction`, whose per-field docs say what each one gates, rather than branching on a host flag.
- **Attachment hooks are interaction-supplied too.** `DiffCommentInteraction.onAttachFiles` (nil on the inert path, which hides the paperclip) and `isUploadingAttachments` carry PR-pane attachment support into the composer controls; the upload itself is owned by `PullRequestsViewModel`. The drop target goes on `DiffCommentEditorControls`' outer `VStack`, never on `PullRequestCommentEditor` — see the drop-modifier bullet in `Alveary/Views/PullRequests/Comments/AGENTS.md`.
- **Comment rows fit the viewport, not the diff width.** `DiffPreviewScrollContainer` publishes `\.diffPreviewViewportContentWidth`; thread and composer rows frame to it so composing never needs horizontal scrolling. Do not shrink that width to dodge the scroll indicator — that was tried and read as a visible gap; the clearance lives inside the card instead.
