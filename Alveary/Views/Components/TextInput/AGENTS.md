## Text Inputs

Rules for `AppTextEditor`, `AppKitTextView`, and their companions.

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
- Command-Return can arrive through `performKeyEquivalent(with:)` instead of `textView(_:doCommandBy:)`; keep `AppKitTextView.onKeyEquivalent` forwarding into `AppKitTextEditorCoordinator.handleKeyEquivalent(_:)` so composer `onKeyPress` handlers see `.return` with `.command`.

## Focus

- `focus: FocusState<Bool>.Binding?` is an AppKit-to-SwiftUI bridge.
- Programmatic focus must use `requestFirstResponder: UUID?` plus `onFocusRequestConsumed`, not direct writes to `@FocusState`.
- `handleFocusChange` backfills both the focus binding and the plain `isAppKitFirstResponder` mirror.
- Body-time reads of "is composer focused?" must use `isAppKitFirstResponder`, not `@FocusState`.
- `syncFocusIfNeeded()` may claim first responder when focus is `true`; it must not force-resign when focus becomes `false`.
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

## Fenced Code Blocks

### Storage And Geometry

- Production composer code blocks are projected by `ComposerDocument`: the text view receives only visible editable code content, and markdown fences are serialized outside `AppKitTextView`.
- Fenced-code-block chrome remains opt-in through `codeBlockRanges`. Plain `AppTextEditor` uses, such as settings or skills fields, can still show literal triple backticks when they are not backed by a composer document projection.
- Keep delimiter structure out of visible text and selection geometry. Leading code blocks should start at the normal text inset, not below an invisible fence row.
- Leading opening delimiters reserve only code-block top padding, not the normal outer gap, so inserting the first code glyph does not shift the visual block downward.
- Code-block projection still needs code-block bottom padding plus the outside gap; collapsing that space makes text typed below overlap and clip the block chrome.
- A closed code block at EOF with a trailing newline also needs outside-line height below the chrome, not just the outer gap, so the caret and first typed line below it do not clip.
- Typing an opening fence before an existing line should insert the newline after the fence and move that line into the code block, not leave the line outside the block.
- Open code blocks whose editable content ends in a newline need a trailing editable-line rect; otherwise the caret can move to a new visual line while the rounded code-block chrome stays one line tall.
- Treat code-block spacing as additive:
    - The block owns equal outer gaps above and below its chrome.
    - The composer/text view still owns its own top and bottom insets outside those gaps.

### Caret And Selection

- Legacy raw-fence paths may still select hidden delimiters in the backing string; clip AppKit text/selection drawing around hidden delimiter rows so invisible fences cannot paint full-width selection bars there.
- Production composer selection should be projection-based. New composer-specific caret fixes should prefer `ComposerProjection` ranges over hidden-delimiter rects.
- Empty code-block caret drawing must use the block's visual content inset, not AppKit's default extra-line-fragment y-position.
- Empty code-block caret blinking must erase the same adjusted caret rect during the off phase; delegating that phase to AppKit can leave a tiny accent-colored remnant from the original extra-line-fragment rect.
- EOF after a closed code block must draw and erase the caret on the outside text line, not on the hidden closing-fence row.
- Backspace on the outside blank line after a document-owned code block should move the caret into the block through `ComposerTransaction`; never let AppKit remove individual serialized backticks.
- When emptying a code block, reset typing attributes back to base text styling so stale code-block paragraph indents cannot move the empty caret or placeholder.

### Tests

- Code-block caret erase helpers should no-op without `NSGraphicsContext.current`; unit tests that exercise the draw path need an explicit bitmap graphics context, not `NSImage.lockFocus()`.

## Drops And Paste

- `disablesAppKitDragDestination` is opt-in per editor.
- Set it to `true` only when a parent `.dropDestination(for: URL.self)` handles drops.
- Override `updateDragTypeRegistration()` so NSTextView cannot re-register drag types after state changes.
- Unregister all drag types when opting in; Finder also provides paths as `.string`.
- Do not override `readablePasteboardTypes`; that breaks paste.
