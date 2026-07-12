## Needle And DI

These instructions apply to files under `Alveary/DI/` and `Alveary/DI/Generated/`.

- The app uses Needle from the target pre-build script to generate `Alveary/DI/Generated/NeedleGenerated.swift`. Treat that file as generated output: keep it in the repo, but do not hand-edit it.
- Add Needle `Component` files under `Alveary/DI/`. Keep component declarations generator-visible, not `private`.
- If you add or change components, refresh `Alveary/DI/Generated/NeedleGenerated.swift` before you finish by building the app target or running the same `needle generate` command used in `project.yml`.
- When you add a new Needle component file, run `xcodegen generate` so the project reflects the new source file.
- `AppComponent` is the root component and owns app-scoped service instances. Feature components are generator-visible scopes; do not reintroduce resolver containers or sibling-component lookups.
- Construct the app-scoped `ConversationControllerRegistry` with `modelContainer.mainContext` so controller writes and SwiftUI `@Query` reads share one context.
- Keep diff-related singletons app-scoped together: `GitService`, `FileListManager`, `WorktreeManager`, and `DiffWorkspaceStore`.
- `DataComponent` owns the on-disk SwiftData location. Keep the app store scoped under `~/Library/Application Support/Alveary/Alveary.store` so local resets stay app-specific and never fall back to the generic `default.store` path.
