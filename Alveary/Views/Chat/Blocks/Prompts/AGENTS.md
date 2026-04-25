## Prompt Blocks

Rules for `PromptBlock` and `AskUserQuestion` cards.

- The prompt bubble should hug content instead of filling transcript width.
- Measure the real visible cards before applying shared width.
- Sync all question cards to the widest measured card, capped by bubble max width.
- Do not add trailing spacers or full-width footer layout that expands the bubble to `transcriptBubbleMaxWidth`.
- Center choice glyphs against the full title+description stack, not the first text line.
- Synthesize an `Other` choice when custom responses are allowed.
- Reveal the inline text field inside the selected option's content area.
- Serialize the typed custom text, not the literal word `Other`.
- Focus the inline custom-response field in the same interaction that selects `Other`.
- Keep a snapshot with `Other` selected so inline-field layout regressions show up.
- Answered prompts render as structured Q/A rows.
    - Title: `Submitted responses`.
    - Put each question and answer on separate lines.
    - Keep 8pt between Q/A pairs.
