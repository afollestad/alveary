## Prompt Blocks

Rules for AppKit `AskUserQuestion` cards and submitted-response parsing.

- The prompt bubble should hug content instead of filling transcript width.
- Measure the real visible cards before applying shared width.
- Sync all question cards to the widest measured card, capped by bubble max width.
- Do not add trailing spacers or full-width footer layout that expands the bubble to the configured max width.
- Center choice glyphs against the full title+description stack, not the first text line.
- Synthesize an `Other` choice when custom responses are allowed.
- Reveal the inline text field inside the selected option's content area.
- Serialize the typed custom text, not the literal word `Other`.
- Focus the inline custom-response field in the same interaction that selects `Other`.
- Keep the full answer row clickable and give rows a visible pressed state; only the selected `Other` text field should take text-input clicks.
- Keep native radio/switch controls committing selection for keyboard and accessibility activation; full-row mouse overlays should only handle hit-area and pressed-state preview.
- Keep a snapshot with `Other` selected so inline-field layout regressions show up.
- Explain disabled submission caused by unanswered questions so multi-question prompts do not look stuck when required cards are off-screen.
- Answered prompts render as structured Q/A rows.
    - Title: `Submitted responses`.
    - Put each question and answer on separate lines.
    - Keep 8pt between Q/A pairs.
    - Measure submitted Q/A labels with wrapped text height; `sizeToFit()` can clip long questions after width is constrained.
    - Measure natural submitted Q/A width with the same AppKit label control used for rendering so the bubble grows before orphaning the final word.
