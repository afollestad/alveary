## Needle And DI

These instructions apply to files under `Alveary/DI/` and `Alveary/DI/Generated/`.

- `Alveary/DI/Generated/NeedleGenerated.swift` is generated output (it carries no header saying so): keep it committed, never hand-edit it.
- Add Needle `Component` files under `Alveary/DI/`. Keep component declarations generator-visible, not `private`.
- If you add or change components, refresh `NeedleGenerated.swift` before you finish by building the app target or running the `needle generate` command from `project.yml`.
- `AppComponent` is the root component and owns app-scoped service instances. Feature components are generator-visible scopes; do not reintroduce resolver containers or sibling-component lookups.
- Construct the app-scoped `ConversationControllerRegistry` with `modelContainer.mainContext` so controller writes and SwiftUI `@Query` reads share one context.
- Keep diff-related singletons app-scoped together: `GitService`, `FileListManager`, `WorktreeManager`, and `DiffWorkspaceStore`.
- `DataComponent` owns the on-disk SwiftData location. Keep the app store scoped under `~/Library/Application Support/Alveary/Alveary.store` so local resets stay app-specific and never fall back to the generic `default.store` path.
- Preserve an unopenable store and present Retry/Quit before creating database-dependent services. `ProjectWorkspaceStoreUpgrade` stages upgrades and recovers interrupted installations; never substitute an empty store.
- `AppStorageProfile.wipesSettingsDefaultsOnExit`, not a non-nil suite name, decides teardown. The debug `scratch(name:)` profile behind `ALVEARY_STORAGE_PROFILE` names a suite it must keep across launches so first-run flows stay repeatable by hand.
- The DEBUG-only `demo()` profile behind `ALVEARY_DEMO_MODE` is `scratch`'s opposite: wiped on *entry*, never on exit, because a relaunching successor would otherwise race the instance it replaces. Its swapped services branch on `storageProfile.isDemo` — never `AppRuntimeProfile.current` — through the `demoX` accessors in `AppComponent+Demo.swift`, so a registration reads `demoX ?? RealX(...)` and storage cannot disagree with the services beside it. `Alveary/Demo/AGENTS.md` owns the rest.
