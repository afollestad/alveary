## Repo-Local Workflows

- **Keep workflow homes separate.** Store capability workflows under `.agents/skills`; store review, audit, and check workflows under `.agents/checks`.
- **Expose workflows through symlinks.** Link `.claude/skills` and `.codex/skills` to `.agents/skills`; link `.claude/checks` and `.codex/checks` to `.agents/checks`.
- **Keep workflows concise.** Put only agent-facing workflow details in `SKILL.md`; keep human workflow docs in `README.md`.
- **Use release skill.** For release bumps or release dry runs, follow `.agents/skills/release-alveary/SKILL.md`.
- **Use self-review check.** For self reviews or audits, follow `.agents/checks/self-review/SKILL.md`.
- **Protect secrets.** Never commit signing certificates, App Store Connect keys, passwords, or base64 secret values.
- **Validate changes.** Run the workflow validator after editing `.agents/skills/*/SKILL.md` or `.agents/checks/*/SKILL.md` when one is available.
