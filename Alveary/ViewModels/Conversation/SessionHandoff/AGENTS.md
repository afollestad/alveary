## Session Handoff

These instructions cover `Alveary/ViewModels/Conversation/SessionHandoff/` — the between-turn hidden flow that carries a conversation into a fresh provider session: when it starts, its steering, notes, and command entry point. Prompt building and the handoff settings are `Alveary/Services/Settings/`; `Alveary/Views/Chat/AGENTS.md` owns what a chat surface must not break while one runs.

- **Handoff is terminal-aware.** Context-window token rows may mark handoff pending before the turn completes, but handoff starts only from a successful terminal token stop. Queued messages stay behind a pending handoff, and pending state clears on errors, interruptions, explicit stops, or handoff start.
- **A nonterminal scheduled run blocks handoff entirely** — see `Alveary/ViewModels/Conversation/ControllerRegistry/AGENTS.md`, which owns that gate and the other producers it stops.
