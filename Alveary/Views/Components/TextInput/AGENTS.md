## Text Inputs

Rules for `AppMarkdownEditor`, `AppTextEditor`, `AppKitTextView`, and their companions.

## AppMarkdownEditor

`AppMarkdownEditor` + `AppMarkdownDraft` are the app's shared BlockInputKit host. This section owns their rules; `Alveary/Views/PullRequests/`, `Alveary/Views/Settings/`, `Alveary/Views/Skills/`, `Alveary/Views/Scheduled/`, and `Alveary/Views/DiffViewer/` consume them.

- **Reach for it whenever the content is markdown prose** — comments, agent prompts, commit messages, skill and scheduled-task instructions. Keep `AppTextEditor` for raw non-markdown text a block editor would reformat, such as `MCPServerPane`'s headers and env blocks, and `AppTextField` for single-line values.
- **Never write serialized markdown back into a `String` while the user types.** `BlockInputView.configure` always reloads the document from its store, so a per-keystroke write-back reconfigures the editor mid-edit. Hosts hold the draft and read `draft.markdown` at their own commit point — Save, Submit, and `onDisappear` when a closed pane must reopen with its text.
- **Swap a whole document with `resetContent(to:)`, splice with `replaceText(_:)`.** `resetContent` bumps `contentGeneration`, which keys the editor and rebuilds it — a caret left from the old document otherwise scrolls the new one under its top inset and clips the first block against the chrome. Reset, disk reloads, and generated bodies reset; mid-edit rewrites that must keep the caret (PR attachment links, composer text sync) use `replaceText`.
- **Publish coarse state only on transitions.** `isEffectivelyEmpty` and `matchesReference` re-render the host, which reconfigures the editor; the guards in `AppMarkdownDraft` are what keep that to once per transition rather than once per keystroke. A new flag follows the same shape.
- **Size by line count, not pixels.** `.growsToLineCount` grows with content then scrolls; `.fillsAvailableHeight` takes the host's frame, for a resizable sheet. A `ScrollView` host needs neither — put the editor in a sheet instead, rather than reintroducing a fixed-height mode to survive the unbounded vertical proposal.
- **Text put into a draft has to come back out unchanged.** `AppMarkdownDraftTests` covers commit-message and instruction shapes; `PromptDefaultsMarkdownRoundTripTests` covers the packaged prompts, whose authoring rules live in `Alveary/Services/Settings/AGENTS.md`.

## AppTextField

- `showsClearButton` draws `AppTextField`'s own trailing clear affordance and is off by default; it owns the binding, so callers pass a flag rather than supplying a button. While visible it takes over the trailing inset so scrolled text and the caret cannot run underneath it, and clearing keeps focus in the field the way `NSSearchField` does.

## AppKit Bridge

- Draw the placeholder inside `AppKitTextView`, not as a SwiftUI overlay, so insets and caret placement match the real text view.
- Keep the empty editor's caret and placeholder text on the same x-origin. Do not add a focused-only placeholder offset; it makes the caret appear left of the placeholder instead of lined up with the first typed character.
- Keep `AppKitTextView.allowsVibrancy = false`.
    - Vibrancy can shift AppKit-drawn chip fills away from the literal `NSColor` used by matching SwiftUI accent surfaces.
    - Disabling vibrancy keeps editor chips stable across composer panels, sheets, popovers, and future host surfaces.
- Selection-change callbacks must not synchronously trigger layout-dependent restyling.
    - Lightweight typing state may update inline.
    - Full chip/code restyles should defer to the next main-runloop turn.
- Prime text-container width with `updateTextContainerForCurrentBounds()` from layout or measurement, not from `draw(_:)`.
    - `draw(_:)` and chip/hint rect helpers may call `prepareForSafeTextLayout()` as a read-only guard.
    - Use `markTextLayoutNeedsPriming()` after text/attribute changes and `primeTextLayoutForDrawing()` from measurement/layout before allowing `NSTextView.draw(_:)` to fill layout holes.
    - AppKit can draw during mount or SwiftUI update cycles while the text container still has a zero width.
    - Mutating the text container or forcing `NSLayoutManager` glyph layout in that state has caused crashes in `NSTextView.draw(_:)` and height measurement.
- `sizesToContent` editors must handle binding-driven text replacement before AppKit has a stable layout width.
    - Prime SwiftUI height from explicit line breaks for immediate growth.
    - Let the AppKit measured height refine the value after layout catches up.
    - Keep delayed measurement guarded by the text value that was measured so stale async work cannot resize a newer draft.
- Use `showsDisabledCursor` only for disabled editors that should show a blocked cursor; normal progress-only read-only editors should leave it false.
- Command-key equivalents can arrive through `performKeyEquivalent(with:)` instead of `textView(_:doCommandBy:)`; keep `AppKitTextView.onKeyEquivalent` forwarding into `AppKitTextEditorCoordinator.handleKeyEquivalent(_:)` for shared text-input callers that opt into key handling.
- Cache derived text-presentation outputs across identical SwiftUI updates; width-only layout may restyle chip geometry, but plain text should only recalculate internal AppKit height, and fixed-height editors must not publish unused measured-height state.

## Focus

- `focus: FocusState<Bool>.Binding?` is an AppKit-to-SwiftUI bridge.
- Programmatic focus must use `requestFirstResponder: UUID?` plus `onFocusRequestConsumed`, not direct writes to `@FocusState`.
- `handleFocusChange` backfills both the focus binding and the plain `isAppKitFirstResponder` mirror.
- Body-time reads of first-responder state must use `isAppKitFirstResponder`, not `@FocusState`.
- `syncFocusIfNeeded()` claims but never force-resigns — see the owning bullet in `Alveary/Views/AGENTS.md`'s Focus And Keyboard Coordination.
- `claimFirstResponder(on:retriesRemaining:)` polls short main-runloop ticks until the text view has a window.
- Do not replace the retry with one long sleep.
- Keep `firstResponderClaimInFlight` deduping around the retry chain.
- Keep that flag's writes inside the main-queue body and do not clear it between recursive retry hops.

## Chip Styling

- Keep base `textColor` and typing color pinned to normal label color. Styled chip colors must not bleed into later plain text.
- `applyTrailingKern` is only for `.slashCommand` chips. File mentions and inline code sit mid-line and should not gain asymmetric trailing room.
- Compact file-mention chips:
    - Hide the entire stored encoded range with clear foreground.
    - Use computed negative `.kern` so the enclosing rect shrinks to the decoded label width.
    - Draw `CanonicalPath.decodeStoredMentionPath(chip.displayText)` after `super.draw(_:)`.
    - Only draw compact labels for single-line chip rects.

## Drops And Paste

- `disablesAppKitDragDestination` is opt-in per editor.
- Set it to `true` only when a parent `.dropDestination(for: URL.self)` handles drops.
- Override `updateDragTypeRegistration()` so NSTextView cannot re-register drag types after state changes.
- Unregister all drag types when opting in; Finder also provides paths as `.string`.
- Do not override `readablePasteboardTypes`; that breaks paste.
