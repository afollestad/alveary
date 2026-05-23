## Repo-Local Checks

- **Keep `.agents/checks` canonical.** Store review, audit, and check workflows under `.agents/checks`; expose them to individual agents through symlinks like `.claude/checks` and `.codex/checks`.
- **Keep checks flat.** Put each check in a top-level `.agents/checks/*.md` file with `name` and `description` frontmatter; do not put checks in child folders.
- **Use self-review check.** For self reviews or audits, follow `.agents/checks/self-review.md`.
- **Keep checks concise.** Put only agent-facing review workflow details in check Markdown files; keep human workflow docs in `README.md`.
- **Validate changes.** Run the workflow validator after editing `.agents/checks/*.md` when one is available.
