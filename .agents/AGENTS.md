## Repo-Local Skills

- **Keep `.agents/skills` canonical.** Store project-local skills under `.agents/skills`; expose them to individual agents through symlinks like `.claude/skills` and `.codex/skills`.
- **Keep skills concise.** Put only agent-facing release workflow details in `SKILL.md`; keep human release docs in `README.md`.
- **Use release skill.** For release bumps or release dry runs, follow `.agents/skills/release-alveary/SKILL.md`.
- **Use self-review skill.** For self reviews or audits, follow `.agents/skills/self-review-alveary/SKILL.md`.
- **Protect secrets.** Never commit signing certificates, App Store Connect keys, passwords, or base64 secret values.
- **Validate changes.** Run the skill validator after editing `.agents/skills/*/SKILL.md`.
