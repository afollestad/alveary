---
name: self-review-alveary
description: Perform an Alveary self review or audit of current changes. Use when the user asks for a self review, audit, review of uncommitted changes, or a final quality pass before commit/PR in the Alveary repo.
---

# Self Review Alveary

## Overview

Perform a repo-aware quality audit of the current Alveary changes before they are committed or handed off. Prioritize concrete bugs, regressions, stale guidance, missing validation, and low-risk fixes.

## Steps

1. First say exactly: `Performing a self review...`
2. Inspect `git status --short` and the relevant diffs.
3. Read the nearest `AGENTS.md` files for changed paths when they were not already read in the current turn.
4. Review changes for:
   - Bugs.
   - Edge cases.
   - Regressions (do a broad search for unintended consequences).
   - Performance issues. 
   - Dead or stale code.
   - Any external code that is now unused due to these changes.
   - File-size pressure.
   - Missing unit or snapshot test coverage.
   - Missing class docs, or code comments. 
   - Missing or stale `AGENTS.md` guidance.
   - Lint risks and Swift style issues.
   - Accessibility issues in UI changes.
5. Confirm snapshot recording or verification when UI snapshots are affected.
6. Fix low-risk issues directly. If a specific commit SHA was given to the skill, amend directly into the commit.
7. Ask before risky or broad changes.
8. Report findings first, ordered by severity and grounded in file/line references.

**WHEN DONE:** If anything was changed, loop and do another pass with fresh eyes. Continue to loop until there is nothing more to change. If nothing was changed, ask if the user wants another pass.

## Output

Use the normal code-review shape:

- Findings first, with tight file and line references.
- Then open questions or assumptions.
- Then a brief summary of any fixes made and validation run.

If there are no findings, say that clearly and mention residual validation gaps.
