## Transcript Links

Rules for `ChatView+Transcript+LinkResolution.swift`.

- Markdown links open through the `.environment(\.openURL, ...)` modifier on `ChatTranscriptView`.
- Keep the modifier on the outer transcript so user and assistant bubbles inherit it.
- AppKit transcript rows must route markdown clicks through `AppKitTranscriptRowFactory.Configuration.onOpenMarkdownLink`.
    - Use the same resolver here before calling `NSWorkspace.shared.open`.
- Resolve schemeless URLs against `workingDirectory`; SwiftUI's default handler no-ops relative paths without `file://`.
- Expand `~` before working-directory resolution.
    - Decode percent escapes before `expandingTildeInPath`.
    - Otherwise `~/Desktop/my%20file.png` misses `my file.png`.
- Pass absolute URLs with schemes through unchanged.
- Pass fragment-only references like `#section` through unchanged so they silently no-op instead of opening the cwd.
- Keep `workingDirectory` plumbed from `ChatView` via `ConversationView.activeWorkingDirectory`.
- `ChatTranscriptLinkResolutionTests` pins each resolver branch; update tests with resolver changes.
- File-mention chips in `UserBubble` reuse the same handler.
    - `AppMarkdownParser.applyComposerChip` tags `.fileMention` replacements with `replacement.link`.
    - Absolute stored paths become `file://` URLs.
    - Relative stored paths stay schemeless and resolve at click time.
    - Slash-command chips stay visual-only.
