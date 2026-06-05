## Prompt Blocks

Rules for `AskUserQuestion` transcript artifacts.

- Active unresolved `AskUserQuestion` prompts render as composer interaction
  overlays, not prompt cards inside the transcript. Keep new active-prompt UI
  behavior in the composer overlay path documented by `Alveary/Views/Chat/AGENTS.md`.
- Transcript prompt blocks are for submitted-response summaries and any
  compatibility display of already-handled prompt artifacts.
- Dismissed prompts are handled without a submitted-response card; normal
  interruption display is owned by the centered-note path.
- Answered prompts render as structured Q/A rows.
    - Title: `Submitted responses`.
    - Put each question and answer on separate lines.
    - Keep 8pt between Q/A pairs.
    - Measure submitted Q/A labels with wrapped text height; `sizeToFit()` can clip long questions after width is constrained.
    - Measure natural submitted Q/A width with the same AppKit label control used for rendering so the bubble grows before orphaning the final word.
