## Settings Services

These instructions cover the settings services under `Alveary/Services/Settings/`.

- `.alveary.json` writes are a selective round-trip, not a wholesale rewrite. The project settings editor only owns `scripts.setup`, `scripts.teardown`, `preservePatterns`, and `actions`; when saving supported config, preserve non-editable supported fields such as `scripts.setupTimeoutSeconds` and `shellSetup` instead of dropping them. If the merged supported config normalizes to no meaningful values, delete `.alveary.json` instead of persisting an empty `{}` file.
- Persisted UI enum/string settings should decode missing or invalid values to their packaged defaults instead of failing settings load.
- Persisted UI numeric settings should decode missing values to defaults and clamp invalid values to their supported ranges.
