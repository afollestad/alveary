## Prompt Blocks

Rules for `AskUserQuestion` transcript artifacts.

- Active unresolved `AskUserQuestion` prompts render as composer interaction
  overlays for answering, plus passive transcript usage rows. Do not put answer
  controls inside transcript rows.
- Transcript prompt usage rows show pending `Asking N question(s)` copy and
  become expandable submitted `Asked N question(s)` rows after responses are
  saved.
- Dismissed prompts are handled without a submitted-response card; normal
  interruption display is owned by the transcript-note path.
- Answered prompts render as structured Q/A rows.
    - Use passive usage-row expansion in the transcript, not prompt-card chrome.
    - Put each question and answer on separate lines.
    - Keep 8pt between Q/A pairs.
    - Measure submitted Q/A labels with wrapped text height; `sizeToFit()` can clip long questions after width is constrained.
    - Measure natural submitted Q/A width with the same AppKit label control used for rendering so the bubble grows before orphaning the final word.
