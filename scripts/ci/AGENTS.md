## Release CI Scripts

- **Keep YAML thin.** Put release implementation logic here; keep `.github/workflows/release.yml` as orchestration.
- **Protect secrets.** Never print signing/notarization secret values, enable shell tracing, or write secrets outside `$RUNNER_TEMP`.
- **Fail before publishing.** Validate versions, tags, signatures, notarization, stapling, and ZIP creation before creating the GitHub Release.
- **Build notes with Copilot.** Resolve the previous version tag and candidate commit count deterministically, then let Copilot CLI inspect `git log` and `git show` and write only `.release-notes.md`; authenticate with the built-in `GITHUB_TOKEN`, verify no other workspace file changed, and validate the exact header, single-line bullet body, and Full Changelog footer.
- **Keep dry runs non-publishing.** Manual `workflow_dispatch` runs may build, notarize, staple, zip, and upload an artifact, but only push-triggered releases may create tags or GitHub Releases.
