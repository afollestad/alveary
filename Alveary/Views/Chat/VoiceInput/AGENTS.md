## Chat Voice Input

These instructions cover `Alveary/Views/Chat/VoiceInput/` — dictation for the chat composer: model preparation, capture, recognition, and the modal that fronts them. `Alveary/Services/VoiceInput/AGENTS.md` owns the speech services underneath, and the editor transaction dictation drives is `Alveary/Views/Input/Editor/AGENTS.md`. The panel's own `AppKitChatComposerPanelView+VoiceInput.swift` sits in `Alveary/Views/Chat/Composer/`.

- **The hold-to-dictate shortcut is the sole composer key-monitor exception.** Keep it on the mounted `AppKitChatComposerPanelView`, scoped to the visible supported composer in Alveary's key window, and synthesize a forced release when the monitor detaches or becomes invalid.
- **Mouse, shortcut, and accessibility activation share the coordinator reducer.** UI controls own only event tracking, visual state, and temporary focus restoration.
- **Model preparation blocks the window; it is not composer top content.** Installation, update, repair, and failure render through the chat window's shared `AppWindowModalOverlayPresenter`: window blocked, only Cancel until preparation finishes, then a green success check plus Continue.
- **Validated-cache warmup is the exception** — modal-free, microphone spinner only, auto-starting a still-valid activation.
- **Re-check the modal after every suspension** in thread-level actions that can restore or replace selection. An operation started before preparation must not unmount the blocking modal when it later completes.
