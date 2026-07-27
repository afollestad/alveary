## Release CI Scripts

- **Keep YAML thin.** Put release implementation logic here; keep `.github/workflows/release.yml` as orchestration.
- **Protect secrets.** Never print signing/notarization secret values, enable shell tracing, or write secrets outside `$RUNNER_TEMP`.
- **Fail before publishing.** Validate versions, tags, signatures, notarization, stapling, and ZIP creation before creating the GitHub Release.
- **Build notes with Copilot.** Resolve the previous version tag and candidate commit count deterministically, then let Copilot CLI inspect `git log` and `git show` and write only `.release-notes.md`; authenticate with the built-in `GITHUB_TOKEN` and verify no other workspace file changed.
    - **Ask for user-facing changes only.** CI, tests, refactors, dependency bumps, docs, and agent-guidance commits are excluded. A release with nothing user-facing still emits one `- **Other**` group summarizing the internal work, so the "non-empty range must produce bullets" guard stays meaningful.
    - **Validate the grouped shape.** Header-free body of bold theme groups (`- **Theme**`), each with at least one indented italic child bullet carrying its merged commits' hash links, plus exactly one final Full Changelog footer. Keep the structural checks in the single awk pass; group and child bullets are only valid relative to each other, so independent line matchers cannot see orphan children or childless groups.
    - **Print diagnostics on rejection.** Dump the counters and the generated file to stderr. Notes are generated after signing and notarization, so a rejection wastes a full build; the file is about to be published publicly, so this does not conflict with the secrets rule.
- **Keep dry runs non-publishing.** Manual `workflow_dispatch` runs may build, notarize, staple, zip, and upload an artifact, but only push-triggered releases may create tags or GitHub Releases.
