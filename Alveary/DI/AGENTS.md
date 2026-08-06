## Needle And DI

These instructions apply to files under `Alveary/DI/` and `Alveary/DI/Generated/`.

- `Alveary/DI/Generated/NeedleGenerated.swift` is generated output (it carries no header saying so): keep it committed, never hand-edit it.
- Add Needle `Component` files under `Alveary/DI/`. Keep component declarations generator-visible, not `private`.
- If you add or change components, refresh `NeedleGenerated.swift` before you finish by building the app target or running the `needle generate` command from `project.yml`.
- `AppComponent` is the root component and owns app-scoped service instances. Feature components are generator-visible scopes; do not reintroduce resolver containers or sibling-component lookups.
- Construct the app-scoped `ConversationControllerRegistry` with `modelContainer.mainContext` so controller writes and SwiftUI `@Query` reads share one context.
- Keep diff-related singletons app-scoped together: `GitService`, `FileListManager`, `WorktreeManager`, and `DiffWorkspaceStore`.
- `DataComponent` owns the on-disk SwiftData location. Keep the app store scoped under `~/Library/Application Support/Alveary/Alveary.store` so local resets stay app-specific and never fall back to the generic `default.store` path.
- An unopenable store moves aside to `Alveary.store.corrupt-<timestamp>` (with its `-wal`/`-shm`) and the container retries once, because deleting the app leaves the store behind and a hard failure would make reinstalling unlaunchable. An absent store means the directory itself is unwritable, which moving files cannot fix, so that stays fatal. Report the recovery through `consumeLastRecoveredStoreURL()`; losing history silently is its own bug.
- `AppStorageProfile.wipesSettingsDefaultsOnExit`, not a non-nil suite name, decides teardown. The debug `scratch(name:)` profile behind `ALVEARY_STORAGE_PROFILE` names a suite it must keep across launches so first-run flows stay repeatable by hand.
