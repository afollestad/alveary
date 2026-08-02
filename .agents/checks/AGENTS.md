## Repo-Local Checks

- **Keep `.agents/checks` canonical.** Store review, audit, and check workflows under `.agents/checks`; expose them to individual agents through symlinks like `.claude/checks` and `.codex/checks`.
- **Keep checks flat.** Put each check in a top-level `.agents/checks/*.md` file with `name` and `description` frontmatter; do not put checks in child folders.
- Conciseness, self-review usage, and validation rules live in `.agents/AGENTS.md`.
