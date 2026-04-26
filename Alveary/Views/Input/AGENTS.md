## Composer And Autocomplete Behavior

These instructions cover composer-specific view code under `Alveary/Views/Input/`.

> **READ FIRST — Focus and keyboard rules are centralized.** Before touching `@FocusState`, `.focusedSceneValue`, `.onKeyPress`, or `.keyboardShortcut` in this folder, consult the **Focus And Keyboard Coordination** section in `Alveary/Views/AGENTS.md`. It owns the composer's `focusedSceneValue(\.chatComposerFocus, ...)` publisher contract and the companion NSTextView resign branch in `AppTextEditor+AppKit.swift`'s `syncFocusIfNeeded()`. `ChatInputField` is the sole publisher of that key — additional input surfaces here must follow the same pattern rather than introducing a second publisher.

## AppKit Text Editor

- `TextSelection` values flowing through the AppKit editor can briefly refer to an older string right after send/reset updates. Any code that maps those indices into the current string, including `NSTextView` sync and autocomplete helpers, must treat stale indices as invalid and normalize or bail out instead of assuming the indices still belong to the new text.
- Keep selection and replacement offsets in UTF-16 units to match AppKit `NSRange` behavior; mixing them with `String.count` breaks emoji and other composed-character handling.
- Apply composer token styling as attributed ranges while keeping the editor's base `textColor` and typing color pinned to the normal label color. Deriving the base color from already-styled text can cause accent-colored mentions or slash commands to bleed into later plain text or persist after clearing the input.

## Slash-Command Argument Hints

- Slash-command argument hints are visual-only `AppKitTextView` inline hints driven by skill frontmatter (`argument-hint`). Keep them out of the underlying composer `text` and hide them once the user starts typing real arguments or moves the caret away from the end of the command.

## Autocomplete

- Composer autocomplete source loading and filtering must not inherit the live-turn `MainActor` workload. Run the expensive work off-main and only hop back to publish `activeAutocomplete` state so `@` mentions and `/` skills stay responsive while a turn is streaming.
- Composer autocomplete is anchored to the top edge of the editor itself, not above the entire composer stack. Keep the popup as an overlay on `AppTextEditor` so it floats over queued-message rows, while file suggestions show canonical display paths and skill suggestions stay in the single-line icon/name/description/scope layout.
- Composer autocomplete loading and empty placeholder states should share the same full-width popup container and surface color as populated suggestions; keep focused snapshots for files, skills, empty, and loading variants when changing popup styling.
- Composer autocomplete popup scrolling should target each suggestion's stable `id`, not list indices or whole-array change observation. File-mention filtering replaces rows aggressively while typing, and index-driven scroll bookkeeping can leave `@` results visually stale or glitchy.
- Slash-command autocomplete accepts on `Tab`, but `Return` must fall through to send when the highlighted skill already exactly matches the typed `/command`. Without that carve-out, pressing Enter on an exact skill match silently rewrites the token to itself plus a space and makes slash commands feel inert.

## Worktree Picker And Session Location

- The composer worktree-location picker is an empty-thread-only control for git-backed threads. New threads seed `AgentThread.useWorktree` from the global `createWorktreeByDefault` setting, the picker edits that per-thread override before first send, and it should disappear for that thread once `hasCompletedInitialSetup` flips true.
- Once the worktree picker is hidden (git-backed thread past initial setup), surface the committed location as a subtle read-only label in the same row slot.
    - **Render as `sessionLocationLabel`.** The label reads `"Local"` when `useWorktree == false`, or `"Worktree (<last-path-component of worktreePath>)"` when `useWorktree == true`. It replaces the picker in-place; the two states are mutually exclusive by design.
    - **Gate production in `ChatView.sessionLocationLabel`.** It is the sole producer and must require both `project.isGitRepository` and `thread.hasCompletedInitialSetup` so non-git projects and pre-setup threads stay label-free. `ChatInputField` is a dumb renderer — do not re-gate inside it.
    - **Format through `ChatInputFieldTextSupport.sessionLocationLabel(useWorktree:worktreePath:)`.** It is the single source of truth for the text. If the display format ever needs to diverge (e.g. showing branch instead of path component), change it here so unit and snapshot coverage move in lockstep.

## File Mention Encoding

- File-mention storage in the composer is percent-encoded via `CanonicalPath.encodeStoredMentionPath(_:)` so the mention regex (`[^\s\)\]\}>"']+`) can hold a complete path that contains spaces, narrow no-break spaces (U+202F — macOS screenshot filenames use this), brackets, or other terminators as a single chip/token.
    - **Encode at every insertion site.** Drag-drop in `ChatInputField+Interactions.handleDroppedFiles` and autocomplete in `ChatInputAutocomplete.fileMatches` must both encode the path before prefixing `@`. A raw path like `/foo/My File.png` would break the regex at the first space, chip only the prefix, and leave the rest as plain text.
    - **Decode only at render read sites.** `AppKitTextView.drawCompactChipLabels` decodes when painting the composer's compact chip label, and `AppMarkdownParser.applyComposerChip` (invoked from `attachComposerChips(to:)`) decodes when substituting the chip range in chat bubbles.
    - **Outbound messages keep the encoded form.** `ChatInputFieldTextSupport.outboundMessage(from:workingDirectory:)` (called via `ChatView.outboundMessage(from:)`) normalizes each `@` mention through `CanonicalPath.normalizeMentionPath` (tilde expand + relative-to-CWD), then re-encodes via `CanonicalPath.encodeStoredMentionPath` and re-prefixes `@` before it hits the transport. The `@` re-prefix is load-bearing: `FileMentionMatch.highlightRange` starts *at* the `@`, so a naive `prefix + normalizedPath` replacement silently drops the `@` from the outbound text and the persisted user bubble. Persisted user messages therefore share the composer's stored shape, which is what lets `AppMarkdownParser.attachComposerChips` re-detect mentions in `UserBubble` and render chips (the mention regex terminates on whitespace, so a raw-spaced path would chip only its leading run). Do not reintroduce a "send the decoded path" branch — it silently breaks bubble chips for every mention with a space or regex terminator. Regression coverage lives in `AppKitTextEditorCoordinatorTests+OutboundMessage.testOutboundMessage*`.
    - **Keep `mentionChipDisplayText` stored-form.** It returns `@<encoded last-path-component>` — render sites own the decode step. Do not decode inside `ChatInputFieldTextSupport` or it becomes another source that disagrees with the stored form.

## Composer Action Row

- Use `blockedComposerCursorOverlay(when:)` for SwiftUI composer controls that are disabled by the project-trust gate. The AppKit editor path uses `AppTextEditor.showsDisabledCursor` instead.
- `ComposerMode.ProgressReason.canStop` is the single source of truth for whether the composer's action slot renders a stop button and whether double-tap-escape is armed. `.initialSetup` is the only reason that opts in today; `.cancellingInitialSetup`, `.reconfiguringSession`, and `.toolApproval` deliberately opt out so the user cannot double-cancel or send while a non-text action is pending.
- Tool-specific waiting copy for deferred tools must flow through the `ComposerMode.ProgressReason.toolApproval(...)` payload, not through new `toolName` switches in `ChatInputField` or `ChatInputFieldTextSupport`.
    - **Keep `ChatInputField` dumb.** The composer should render the `DeferredToolComposerStatusText` it receives; it should not know that `AskUserQuestion` or `ExitPlanMode` are special cases.
    - **Cover visible copy changes.** When you change deferred-tool placeholder or progress text, add or update focused unit coverage for the text helper and a focused snapshot for the affected composer state.
- The composer's bottom picker/action row is locked to `composerActionRowHeight` (30pt — the `.regular` `ProminentActionButtonStyle` height from `Components/ActionControls.swift`) via `.frame(minHeight:)` on the outer HStack and `.frame(height:)` on the progress HStack inside the `!reason.canStop` branch. This keeps the composer from shifting vertically when the right-hand slot swaps between a 30pt Send/Stop button and the much shorter `ProgressView + caption` indicator used for `.cancellingInitialSetup`, `.reconfiguringSession`, and `.toolApproval`. If the primary action button's control size changes, update `composerActionRowHeight` in lockstep.
