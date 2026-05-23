## Repo-Local Checks

- **Keep `.agents/checks` canonical.** Store review, audit, and check workflows under `.agents/checks`; expose them to individual agents through symlinks like `.claude/checks` and `.codex/checks`.
- **Use self-review check.** For self reviews or audits, follow `.agents/checks/self-review/SKILL.md`.
- **Keep checks concise.** Put only agent-facing review workflow details in `SKILL.md`; keep human workflow docs in `README.md`.
- **Validate changes.** Run the workflow validator after editing `.agents/checks/*/SKILL.md` when one is available.
