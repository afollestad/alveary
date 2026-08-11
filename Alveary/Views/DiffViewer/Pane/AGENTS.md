# Diff Viewer Pane

These instructions cover `Alveary/Views/DiffViewer/Pane/` — `DiffViewerPane`, its two modes, the header, the file and commit lists, and the footer with its `DiffViewerFooterAction` policy. The diff rendering both modes drop into is `Alveary/Views/DiffViewer/Preview/`.

> **READ FIRST:** Focus and keyboard rules are centralized in **Focus And Keyboard Coordination** in `Alveary/Views/AGENTS.md`; the file-list focus bullets below stack on top of that contract.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `DiffViewerVerticalSplit`, `DiffViewerHeaderActionContainer`, and `DiffViewerFileListScrollMonitor`, plus `DiffViewerHeaderBranchLabel`'s no-`minWidth` prohibition and vibrancy note, `DiffViewerPaneHeader`'s reserved close-button space, `DiffViewerTopListKeyboardMonitor`'s gating and key-repeat requirements, and `DiffViewerMode.title`'s length constraint (`Alveary/Services/Settings/DiffViewerMode.swift`) each carry theirs.

## Pane Modes

- **Keep pane edges aligned.** Header controls, selectable row backgrounds, and diff-preview content render `ContextualPaneLayout.horizontalInset` from the pane's horizontal edges in both modes — the same visible edge as the contextual panes this one shares the right-pane lane with, because the two swap in place and any difference reads as the pane shifting. Use `DiffViewerPaneMetrics` rather than inline padding, since macOS `List` and scroll views add different chrome, and keep its constants *derived* from the shared inset so the panes cannot drift apart again.
- **Both modes stay mounted once visited**, through `KeepAliveTabContainer` (see `Alveary/Views/Components/AGENTS.md`), so each mode's list and diff-preview scroll offsets — both axes — survive a mode switch. Mode side effects stay on the pane's `onChange(of: mode)`, which follows the selection rather than the children's lifetimes.
    - **Both list sections gate on `\.keepAliveTabIsActive`**, and both mode contents are `Equatable` applied with `.equatable()` — `DiffViewerPane` is not memoized at its host, so its body runs every resize-drag frame and keeping both mounted would otherwise rebuild two mode subtrees per frame.
- **Persist split positions by mode.** Current changes and commits have separate saved split fractions; do not reuse one mode's resize position for the other.

## Header

The header clips rather than compresses, so every rule here exists to keep something reachable at `AppSettings.supportedRightPaneWidthRange.lowerBound` (320).

- **Mode is a `TabChipButtonStyle` chip row matching the pull-request pane, not a `Menu`.** Keep 36pt chips beside the shared 30pt icon buttons — the two are deliberately different footprints, not a mismatch to reconcile.
- **The branch label is the header's only flexible child, and it must stay that way.** The chips are `fixedSize` and the action container a fixed-width frame, so the label is the only thing SwiftUI can shrink — which keeps a long branch name from pushing an action or the close button off a narrow pane.
- **Hide current-change actions outside current changes.** `Stage`, `Unstage`, and `Discard` are current-change actions, so Commit mode renders no header actions. Commit itself is **not** a header action any more — it leads the footer's ladder, which is what lets the chip row and close button fit 320pt.
- **Re-record the header width guards when a title, action, or metric changes.** `testDiffViewerPaneHeaderMinimumWidthAllActions`, `…MinimumWidthLongBranchName`, `…LongBranchNameTruncates`, `…DefaultWidthWithClose`, and `…MinimumWidthAllActionsWithClose` are what catch a control silently clipping away.

## Action Footer

- **The footer is one full-width button walking the branch workflow.** `DiffViewerFooterAction.available(...)` owns the policy and returns **default-first** — Commit while the tree is dirty, Push changes once it is clean, Create PR / View PR once everything is pushed — with every still-valid action behind the `SplitActionButton` caret. The ordering *is* the state machine: each transition falls out of the `.localGitMutation` refresh that recomputes `DiffViewerViewModel.workingState` (commit clears `hasChanges`, push clears `hasUnpushedCommits`) or, for Create PR → View PR, the observation-tracked link-count read. A stale caret pick retires through `effectiveAction`'s first-available fallback, like the pull-request footer's.
- **Create PR and View PR are mutually exclusive by construction.** Create needs zero linked pull requests on the selection and View exactly one; several linked leave both off and the footer renders the disabled Commit `placeholder` so the strip keeps its height — the toolbar popover owns that disambiguation. Commit and Push share the `canCommitDiffChanges` selection gate; View PR is pure navigation and survives without it.
- **The footer renders in both pane modes** whenever a directory is active, on `contextualPaneFooterChrome()` — never hand-rolled chrome. Its split button wears `.primary`: it is the row's only button, so the single-accent-voice rule that forces `.secondary` in the pull-request footer does not apply here.
- **Push runs inline, not in a modal.** The pane calls `DiffViewerViewModel.push(force:in:)` and surfaces failures through the existing `gitError` banner; a `GitError.nonFastForwardPushRequired` arms the lifted `DiffViewerForcePushDialog` offering a destructive Force push, mirroring the commit modal's affordance.
- **Footer-opened pull-request panes get the back stack** — View PR and the post-create open use `openLinkedPullRequest(_:preservingDiffViewer: true)`; see `Alveary/App/Routing/AGENTS.md`.

## File And Commit Lists

- **Preserve visible commits while refreshing.** If a same-target commit reload is loading or fails with existing commits still available, keep those rows visible; only use list-level loading/error states when there are no commits to preserve. Those states are labeled `else if` arms in `DiffViewerPane+CommitsContent.swift`; do not collapse them into one generic error view.
- **Claim keyboard focus on row clicks.** Both lists own local keyboard focus for arrow-key navigation and scoped Cmd+A. Row clicks must release `chatComposerFocus`, reapply list focus, and keep `DiffViewerTopListKeyboardMonitor` enabled so Up/Down, Shift-Up/Down, and Cmd+A stay in the diff pane.
- **Anchor keyboard navigation to preview selection** — `selectedFile` for files, `selectedCommit` for commits. Unmodified arrows select with `.single` and clear multi-selection; Shift-arrow variants extend the custom range selection. First and last rows scroll the backing `NSScrollView` to its content bounds directly, because row anchors can leave SwiftUI `List` insets unscrolled; middle rows take no explicit anchor. Ordinary row clicks must not inherit a pending keyboard scroll.
- **Keep right-click selection synchronous** through the shared `SecondaryClickTarget` (`Alveary/Views/Components/`), whose AppKit local event monitor selects the clicked row before SwiftUI opens the menu. Do not route that first visual selection through an async `Task`, and do not re-fork a diff-viewer-local copy of the helper.
- **Preserve top on inserts.** When the list is already at the top and rows are inserted above, scroll to the new top without animation so the first row is not clipped under the header.
- **File-row dots are staged/unstaged, not status.** Fixed-size `Circle` views like thread rows, green when staged and secondary when not; this pair is its own mapping and does not read against **Status Dot Colors** in `Alveary/Views/AGENTS.md`.
