## Knit And DI

These instructions apply to files under `Alveary/DI/` and `Alveary/DI/Generated/`.

- The app uses `knit-cli gen` from the target pre-build script to generate `Alveary/DI/Generated/KnitExtensions.swift`. Treat that file as generated output: keep it in the repo, but do not hand-edit it.
- Add Knit `ModuleAssembly` files under `Alveary/DI/`.
- If you add a new assembly or change resolver registrations in a way that should produce new generated resolver accessors, refresh `Alveary/DI/Generated/KnitExtensions.swift` before you finish by building the app target or running the same `knit-cli gen` command used in `project.yml`.
- When you add a new Knit `ModuleAssembly` file, run `xcodegen generate` so the project reflects the new source file.
- Use the CLI-based Knit workflow documented in `project.yml`; do not switch the project over to `KnitBuildPlugin` unless the repo docs and build configuration are intentionally updated together.
