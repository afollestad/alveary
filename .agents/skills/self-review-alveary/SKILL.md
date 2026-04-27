---
name: self-review-alveary
description: Perform an Alveary self review or audit of current changes. Use when the user asks for a self review, audit, review of uncommitted changes, or a final quality pass before commit/PR in the Alveary repo.
---

# Self Review Alveary

## Overview

Perform a repo-aware quality audit of the current Alveary changes before they are committed or handed off. Prioritize concrete bugs, regressions, stale guidance, missing validation, and low-risk fixes.

## Workflow

1. First say exactly: `Performing a self review...`
2. Inspect `git status --short` and the relevant diffs.
3. Read the nearest `AGENTS.md` files for changed paths when they were not already read in the current turn.
4. Review uncommitted changes for:
   - bugs, edge cases, and behavior regressions
   - performance, dead code, stale code, and file-size pressure
   - missing unit or snapshot coverage
   - missing docs, comments, or stale guidance
   - lint risks and Swift style issues
   - accessibility issues in UI changes
5. Confirm snapshot recording or verification when UI snapshots are affected.
6. Fix low-risk issues directly.
7. Ask before risky or broad changes.
8. Report findings first, ordered by severity and grounded in file/line references.
9. When done, ask whether the user wants another pass.

## Output

Use the normal code-review shape:

- Findings first, with tight file and line references.
- Then open questions or assumptions.
- Then a brief summary of any fixes made and validation run.

If there are no findings, say that clearly and mention residual validation gaps.
