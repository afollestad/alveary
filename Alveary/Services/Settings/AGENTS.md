## Settings Services

These instructions cover the settings services under `Alveary/Services/Settings/`.

- `.alveary.json` writes are a selective round-trip, not a wholesale rewrite. The project settings editor only owns `scripts.setup`, `scripts.teardown`, `preservePatterns`, and `actions`; when saving supported config, preserve non-editable supported fields such as `scripts.setupTimeoutSeconds` and `shellSetup` instead of dropping them. If the merged supported config normalizes to no meaningful values, delete `.alveary.json` instead of persisting an empty `{}` file.
- Persisted UI enum/string settings should decode missing or invalid values to their packaged defaults instead of failing settings load.
- Persisted UI numeric settings should decode missing values to defaults and clamp invalid values to their supported ranges.
- `rightPaneWidth` is one persisted width for the whole right-pane lane, clamped to `320...960` and defaulting to `380`. Diff, Skills, MCP, Scheduled, and Pull requests each stored their own before; switching panes then resized the *main* pane, which re-wrapped chat bubbles the user had not touched. Do not reintroduce a per-destination width. The retired keys live on in `LegacyCodingKeys` for decode only — `diffViewerWidth` seeds the shared value and re-encoding drops all five.
- Screen tab selections (`pullRequestsSelectedTab`, `scheduledTasksSelectedTab`) persist as raw tab-title strings; a stored value that no longer names a tab falls back to the packaged default at the restore site. The Pull Requests filter sets (`pullRequestsStatusFilters`, `pullRequestsRepositoryFilters`) persist alongside them; unknown status strings drop out element-wise during decode.
