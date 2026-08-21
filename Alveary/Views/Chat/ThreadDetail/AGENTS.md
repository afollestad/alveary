## Thread Detail

These instructions cover `Alveary/Views/Chat/ThreadDetail/` — the thread shell that resolves a thread's conversations, gates the tab strip, and fronts project trust. The conversation inside it is `Alveary/Views/Chat/Conversation/AGENTS.md`; the tab row it mounts is `Alveary/Views/Chat/ConversationTabs/AGENTS.md`.

**Keep a rule here only when the code that would violate it is not the code that documents it.** The deferred selection task and `statusVersion` invalidation, `ThreadDetailView+StatusInputs`'s read site, and `ThreadDetailConversationResolver`'s transient-fetch fallbacks each carry theirs.

- **Fetch live conversations before sorting or rendering tabs.** Sorting `thread.conversations` in the render path can trap on stale relationship entries when SwiftUI refreshes after a conversation delete. `ThreadDetailConversationResolver` owns the fallbacks that keep an empty fetch from reading as "no conversations".
- **Gate the strip through `ConversationStripPresentation.shouldShow(...)` and keep `newConversationAction` disabled on the same boundary** — before initial setup completes, or while project trust blocks the thread, an additional conversation has no usable runtime context. `Alveary/Views/Chat/ConversationTabs/AGENTS.md` owns what the strip itself renders once mounted.
- **Keep `updateRestoreSelection` gated on `thread.archivedAt == nil`**, and keep `ContentView` from re-adding selection-change observers for the restore selection and mark-read that the selection task already owns.
- **Trust denial deletes through the injected provider-aware thread deletion lifecycle**, never a direct `AgentThread` delete. `ThreadDetailView+ProjectTrust.swift` owns the trust checks and denial selection; composer surfaces take a plain disabled flag instead of reading provider config.
