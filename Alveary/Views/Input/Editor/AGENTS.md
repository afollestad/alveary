## Composer Editor Bridge

These instructions cover `Alveary/Views/Input/Editor/` — the BlockInputKit bridge behind the composer: its controller, editor handle, completion provider, location, and style. The controls below the editor are `Alveary/Views/Input/ActionRow/AGENTS.md`; the AppKit panel around both is `Alveary/Views/Chat/Composer/AGENTS.md`.

> **READ FIRST — Focus and keyboard rules are centralized.** Before touching `@FocusState`, `.focusedSceneValue`, `.onKeyPress`, or `.keyboardShortcut` here, consult the **Focus And Keyboard Coordination** section in `Alveary/Views/AGENTS.md`. The production body consumes first-responder request tokens through `BlockInputView.focusEditor()` and must not add a second focus path.

### Ownership

- **Editing is BlockInputKit's.** Do not reimplement editor projection, completion UI, drops, undo, selection, IME behavior, copy/paste, or sizing in Alveary. Fill, border, radius, and clipping belong to its style config; `AppKitChatComposerEditorController` owns only the non-view bridge — focus-token consumption, stop confirmation, preferred-height invalidation, and draft snapshot lifecycle.
- **Keep sizing on BlockInputKit's terms.** Visible height uses its visible-line sizing and it owns the height animation, so the Alveary side is preferred-height invalidation only — applied immediately, or the editor and action-row bottoms drift while the editor grows upward. Do not reintroduce custom grow/shrink min/max-height logic.
- **Keep `BlockInputComposerCompletionProvider` identity stable across ordinary composer updates**, refreshing it through `update(...)`. BlockInputKit treats provider replacement as a semantic completion reset and dismisses the active popup.
- **Route key handling through `BlockInputConfiguration.keyboardShortcuts`.** Enter, Shift+Enter, Cmd+Enter, and Escape all go there; do not intercept composer keys outside BlockInputKit APIs.
- **Keep editor drops disabled in production.** File and image drops belong to the composer panel: route picked and dropped URLs through Alveary staging and render the attachment strip outside BlockInputKit so the editor never owns the top preview row.
- **Slash-command argument hints are inline hints, never draft text.** Back them with live local-command metadata or cached `Skill.argumentHint` values, and keep them current across model and provider refreshes without replacing the provider.
- App-shot preview chips are host-owned attachments whose AX tree and provider transport wrapper stay hidden from the editor and transcript. Removing the preview only unstages the app shot; it must not mutate composer Markdown.
- Composer selection background stays visually distinct from chip fill — a neutral non-accent token for selection chrome, chip fill and foreground tokens unchanged.

### Drafts

- **BlockInput Markdown is the sendable composer text**; `ComposerDraft.messageText` returns the stored Markdown directly.
- **Keep hot-path mutations cheap** — effective emptiness and dirty revisions only. Markdown serialization belongs in coalesced document-change publishing, or in an explicit `flushDraftFromEditor()` before send, queue, and steer flows.
- **Replace app-owned drafts through `replaceInputDraft` / `clearInputDraft`** so the bridge sees a revisioned external replacement without resetting selection for self-publishes.
- **Dictation owns a BlockInputKit provisional-text transaction.** Make the editor read-only while it runs, update only through its authorized token, finish with exactly one commit or a no-undo cancel, then call `flushDraftFromEditor()` synchronously before unlocking draft-mutating controls. Keep one stable weak editor handle across routine reconfiguration; draft identity replacement and detach must stop or commit synchronously before clearing the old editor or document store. `Alveary/Views/Chat/VoiceInput/AGENTS.md` owns the rest of dictation.
