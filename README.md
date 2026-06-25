# Alveary

_An alveary is a place where bees are kept, including a beehive or apiary enclosure._

Alveary is a native macOS app for orchestrating AI coding agents in parallel. Inspired by Conductor and Codex, and built in Swift with help from the agents themselves.

See the backlog/roadmap [here](https://github.com/users/afollestad/projects/3)!

# Development

## Setup

Alveary is built with XcodeGen, `xcsift`, SwiftLint, and Needle.

Run the bootstrap script once per clone:

```sh
./scripts/setup.sh
```

It installs the required CLI tools via Homebrew (including `xcsift` for agent-friendly TOON `xcodebuild` output), generates `Alveary.xcodeproj`, and configures the repo-local Git hooks so commits touching Swift files run `swiftlint` automatically.

## Build, Test, and Run

Generate the Xcode project after project-structure changes:

```sh
xcodegen generate
```

Build the app:

```sh
./scripts/build.sh
```

Lint the app:

```sh
./scripts/lint.sh
```

Run the app:

```sh
./scripts/run.sh
```

Force a fresh build before launching:

```sh
./scripts/run.sh -b
```

The wrapper scripts share the same build output path as the underlying `xcodebuild` commands.

Run the full test suite:

```sh
./scripts/test.sh
```

Run a focused test class:

```sh
./scripts/test.sh AlvearyTests/AppDelegateTests
```

## Agent Provider Runtime

Alveary uses `AgentCLIKit` for provider runtime integration, provider-owned config access, provider status, model discovery, and provider context-compaction lifecycle events. Claude and Codex are surfaced through the same provider/model settings and thread composer controls; disabled, missing, setup-blocked, and project-untrusted providers stay visible with actionable status.

Codex fast mode is exposed only when `AgentCLIKit` reports provider support. Speed is stored per thread, defaults to Standard, is applied through per-session runtime config, and is forced back to Standard when the selected provider does not support it.

Context-window usage keeps provider cache semantics distinct: Claude cache-read tokens are additive, while Codex cached-input tokens are already included in input tokens.

Project trust state and provider MCP config reads/writes flow through `AgentCLIKit`. Alveary owns app policy such as auto-trust, prompt UI, first-thread gating, and denial cleanup.

Local images picked from the composer or dropped onto it are copied into Alveary-owned Application Support storage. Providers that report local image input receive those copies as attachments; providers without that capability keep the existing Markdown image-link fallback.

## Snapshot Tests

Verify the full snapshot suite:

```sh
./scripts/snapshots.sh verify
```

Verify or record a focused snapshot test:

```sh
./scripts/snapshots.sh verify AlvearyTests/SnapshotTests/testSidebarViewPopulated
./scripts/snapshots.sh record AlvearyTests/SnapshotTests/testSidebarViewPopulated
```

When no test identifier is provided, `./scripts/snapshots.sh` defaults to `AlvearyTests/SnapshotTests`.
Recording snapshots immediately verifies the same test identifiers before reporting success. Snapshot artifacts are written under `.build/snapshot-failures` by default.

## Repo-Local Agent Workflows

Project-local agent workflows live under `.agents`: capability skills in `.agents/skills`, and review, audit, and check workflows in `.agents/checks`. Agent-specific folders such as `.claude/skills`, `.codex/skills`, `.claude/checks`, and `.codex/checks` are symlinks to those canonical directories.

## Releases

Alveary releases are direct-download ZIPs containing `Alveary.app`. The app version lives in `project.yml` under the app target build settings:

```yaml
MARKETING_VERSION: 0.1.0
CURRENT_PROJECT_VERSION: 1
```

Release automation runs from GitHub Actions when a push to `main` changes `MARKETING_VERSION`. CI creates the `vX.Y.Z` tag, signs with Developer ID, notarizes and staples `Alveary.app`, creates `Alveary.zip`, and uploads it to GitHub Releases. Manual workflow runs are dry runs: they sign, notarize, staple, zip, and upload an Actions artifact without creating a tag or GitHub Release. The workflow orchestration lives in `.github/workflows/release.yml`; the implementation scripts live under `scripts/ci/`.

# License

Alveary is licensed under the [GNU General Public License v3.0](LICENSE.md).
