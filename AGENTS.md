## Validating the Plan

**WHEN** I ask you to validate the plan. First, inspect `PLAN.md` and markdown files under `plan/`. Split everything into chunks at spots where we can hand-off in Amp as the context window gets large.

For each step, tell me which one you are on. **DO NOT** cache any results or memory. **DO A DEEP DIVE ON EACH STEP**.

1. Anything stale or outdated? Any factual errors?
2. Anything broken? Any potential bugs?
3. Any performance issues? Can anything be optimized?
4. Any lifecycle issues? Anything that should be longer living? Anything that is too long living?
5. Any concurrency or actor issues? Any race conditions?
6. Any UI issues? Any bad state management?
7. Any dependencies being used directly that should be resolved via DI? Any DI scoping issues?
8. Any missing documentation or comments? **COMMENTS IN CODE BLOCKS SHOULD BE MINIMAL AND CONCISE.**
9. Anything that can be improved, have more examples, additional diagrams and/or UI sketches?
10. Any unnecessarily duplicated logic that can be shared? Anything that can be extracted into a protocol/implementation?
11. Any protocol implementations missing? Any type definitions missing?
12. Any formatting issues in the plan docs? Any unclosed blocks? Any double separators?
13. Is unit test or snapshot test coverage missing or stale anywhere? Only document things that are not obvious. Also do not attempt to test real file system or process interactions (mocks/fakes for those). *Be concise*.
14. Anything out of order? Any sections depend on things are defined later? An agent should be able to implement sequentially. If a forward reference is necessary for a dependency, evaluate whether a placeholder (i.e. using `fatalError(…)`) would make sense until a later implementation is available.
15. Anything that would prevent us from adding support for additional agents later? Is everything properly modularized and extensible?
16. Anything that should be tested/validated ahead of time? Check existing entries in the "Validation" section, also evaluate if anything needs to be added, modified, or is no longer applicable.
17. Are any of the plan files over 10,000 tokens? Before splitting files, see if any files can be reduced (i.e. by making code blocks more concise, making comments more concise, removing unnecessary diagrams, etc).

**AFTER EACH STEP**, do *NOT* automatically move on if there are any potential gaps or issues to address. **IF NO ISSUES OR GAPS ARE FOUND AT ALL**, automatically continue to the next step.
**AFTER ISSUES ARE ADDRESSED** for a given step, summarize changes & fixes in a table view before moving to the next step.
**AFTER ALL STEPS** summarize everything in a table view, and do an additional *deep audit* to make sure nothing was missed. Also make sure plan files remain under 10,000 tokens.

## Linting

The project uses [SwiftLint](https://github.com/realm/SwiftLint) for code style and linting (`brew install swiftlint`).

**BEFORE** committing, run `swiftlint` from the project root to check for violations. Fix any errors before committing. Warnings are acceptable but should be minimized.

**WHEN** writing new Swift files, follow the rules in `.swiftlint.yml`. Key rules: no force unwraps outside of tests, no force casts, prefer `let` over `var`, max line length 150.

Additionally, private types should always go *below* public types.

## XCode Project Generation

The XCode project (`Skep.xcodeproj`) is generated from `project.yml` using XcodeGen (`brew install xcodegen`). **Never edit the `.xcodeproj` directly.**

**WHEN** you create a new `.swift` file, run `xcodegen generate` afterward so the file is included in the Xcode project. The glob-based `sources` in `project.yml` picks up files automatically from the folder structure, but the `.xcodeproj` must be regenerated to reflect the change.

**WHEN** you add a new SPM dependency, add it to the `packages` and `dependencies` sections of `project.yml`, then run `xcodegen generate`.

**WHEN** you add a new Knit `ModuleAssembly` file, place it in `Skep/DI/` (the path configured in `knitconfig.json`). Run `xcodegen generate` to pick up the new file.

**DO NOT** commit `Skep.xcodeproj/` — it is gitignored and regenerated from `project.yml`.
