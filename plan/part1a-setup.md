# Part 1a: Setup

Xcode project generation, SPM dependencies, library stack, project structure, Knit DI. Build this first.

## Implementation Status

- [x] Xcode project generation
- [x] Dependency management: SPM
- [x] Library stack validation
- [x] Project structure
- [x] App bootstrap stub
- [x] Dependency injection: Knit

Validated implementation note: under Xcode 26.3, older Knit releases can fail in `ExtractAppIntentsMetadata` while parsing Knit's generic container surface. Keep `project.yml` pinned to Knit revision `3d4afea562b95a95725f689be819b10ff93351fc` until a tagged release includes the upstream `KnitResolver` workaround.

## Xcode Project Generation: XcodeGen

The Xcode project is generated from a YAML spec (`project.yml`) using **XcodeGen** (`brew install xcodegen`). This is essential for agent-driven development:

- Agents can create and edit YAML files but cannot manipulate `.xcodeproj` bundles (complex `pbxproj` plists with UUIDs).
- After adding new source files, run `xcodegen generate` to regenerate the `.xcodeproj`. New files in the folder structure are picked up automatically if the spec uses glob patterns.
- The generated `Skep.xcodeproj` is **gitignored** — the YAML spec is the source of truth.
- XcodeGen keeps the project reproducible and agent-editable. The current plan uses `knit-cli gen` instead of `KnitBuildPlugin`, but the generated Xcode project still leaves room for future plugin experimentation.

### Install

```bash
brew install xcodegen swiftlint mint
mint install cashapp/knit knit-cli
```

### project.yml

```yaml
name: Skep
options:
  bundleIdPrefix: com.afollestad
  deploymentTarget:
    macOS: "26.0"
  xcodeVersion: "26.3"
  generateEmptyDirectories: true
settings:
  base:
    SWIFT_VERSION: "6.0"  # Language mode (strict concurrency); compiler is Swift 6.2 (bundled with Xcode 26.3)
    MACOSX_DEPLOYMENT_TARGET: "26.0"
targets:
  Skep:
    type: application
    platform: macOS
    sources:
      - path: Skep
        excludes:
          - "**/.DS_Store"
    dependencies:
      - package: knit
        product: Knit
      - package: textual
        product: Textual
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.afollestad.skep
        INFOPLIST_KEY_LSApplicationCategoryType: "public.app-category.developer-tools"
        ENABLE_HARDENED_RUNTIME: YES
        CODE_SIGN_ENTITLEMENTS: Skep/Resources/Skep.entitlements
    preBuildScripts:
      - name: "Knit Code Generation"
        script: |
          KNIT_CLI=""
          if command -v knit-cli &> /dev/null; then
            KNIT_CLI="knit-cli"
          elif [ -f "$HOME/.mint/bin/knit-cli" ]; then
            KNIT_CLI="$HOME/.mint/bin/knit-cli"
          fi
          if [ -z "$KNIT_CLI" ]; then
            echo "error: knit-cli is required for code generation. Install via 'mint install cashapp/knit knit-cli'."
            exit 1
          fi
          mkdir -p "${SRCROOT}/Skep/DI/Generated"
          "$KNIT_CLI" gen \
            --assembly-input-path "${SRCROOT}/Skep/DI" \
            --type-safety-extensions-output-path "${SRCROOT}/Skep/DI/Generated/KnitExtensions.swift"
        inputFiles: []
        outputFiles: []
    postBuildScripts:
      - name: "SwiftLint"
        script: |
          if command -v swiftlint &> /dev/null; then
            swiftlint
          fi
  SkepTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: SkepTests
        excludes:
          - "**/.DS_Store"
    dependencies:
      - target: Skep
      - package: swift-snapshot-testing
        product: SnapshotTesting
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.afollestad.skep.tests
packages:
  knit:
    url: https://github.com/cashapp/knit
    revision: "3d4afea562b95a95725f689be819b10ff93351fc"
  textual:
    url: https://github.com/gonzalezreal/textual
    from: "0.3.1"
  swift-snapshot-testing:
    url: https://github.com/pointfreeco/swift-snapshot-testing
    from: "1.17.0"
```

### Workflow

1. **First time**: create `project.yml` and folder structure, create a placeholder `Skep/DI/Generated/KnitExtensions.swift`, then run `xcodegen generate`. The pre-build `knit-cli gen` step overwrites that file later, but the placeholder must exist before project generation so the initial `.xcodeproj` includes it.
2. **Adding files**: create the `.swift` file in the correct folder, run `xcodegen generate`. The glob-based `sources` picks it up automatically.
3. **Adding dependencies**: add to the `packages` and `dependencies` sections of `project.yml`, run `xcodegen generate`.
4. **CI/agents**: `mkdir -p Skep/DI/Generated && touch Skep/DI/Generated/KnitExtensions.swift && xcodegen generate && xcodebuild -project Skep.xcodeproj -scheme Skep -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` — fully reproducible from the YAML spec and explicit about the macOS target/scheme.

### knitconfig.json

Retained for Knit's **Xcode build plugin** documentation. Lives at the project root:

```json
{
  "assemblyInputPaths": [
    "Skep/DI"
  ]
}
```

This tells Knit where `ModuleAssembly` files live when using `KnitBuildPlugin`. The current build pipeline does **not** read this file — `knit-cli gen` uses `--assembly-input-path` directly in the pre-build script above. Keep `knitconfig.json` in the repo for parity with Knit docs and future plugin experimentation, but do not rely on it for CLI-based generation.

### .swiftlint.yml

```yaml
included:
  - Skep
  - SkepTests
excluded:
  - Skep/DI/Generated  # Knit-generated files
line_length:
  warning: 150
  error: 200
type_body_length:
  warning: 400
  error: 600
file_length:
  warning: 500
  error: 800
disabled_rules:
  - trailing_whitespace
  - opening_brace      # Conflicts with some Swift 6 patterns
opt_in_rules:
  - force_unwrapping
  - force_cast
```

Force unwraps and force casts are acceptable in test code. A separate `SkepTests/.swiftlint.yml` disables these rules for tests:

```yaml
# SkepTests/.swiftlint.yml
parent_config: ../.swiftlint.yml
disabled_rules:
  - force_unwrapping
  - force_cast
```

Run `swiftlint` from the project root before committing. Do **not** pass `--config` in the root command or Xcode build phase here, because that bypasses nested config discovery and would make the test override above ineffective.

### Skep.entitlements

The app uses **Hardened Runtime** (required for notarization) but **not App Sandbox** (needs unrestricted process spawning and filesystem access). Enable Hardened Runtime via the target build setting (`ENABLE_HARDENED_RUNTIME: YES` in `project.yml` above). The entitlements file at `Skep/Resources/Skep.entitlements` stays intentionally empty for v1:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

- **No App Sandbox** — omitting `com.apple.security.app-sandbox` (or setting it to `false`) allows unrestricted `Process` spawning and filesystem access.
- **Hardened Runtime** — controlled by the Xcode/XcodeGen build setting, not by the contents of this plist. An empty entitlements file does not enable Hardened Runtime by itself.
- **`allow-unsigned-executable-memory`** — do **not** add this. Validation confirmed Textual's JavaScriptCore usage does not need it under Hardened Runtime; Prism.js runs fine without JIT-specific entitlements.
- **Notifications** — notification authorization is optional UX polish, not a core dependency. Validation confirmed the authorization request is safe even when permission cannot be granted; verify delivery end-to-end in the signed app target during implementation.

### .gitignore additions

```
Skep.xcodeproj/
*.xcworkspace/
```

---

## Dependency Management: Swift Package Manager

All Swift dependencies are declared in `project.yml` (see above) and managed via SPM through the generated Xcode project.

| Dependency | Purpose | URL |
|---|---|---|
| Knit | Dependency injection | https://github.com/cashapp/knit |
| Textual | Markdown rendering and syntax highlighting for chat messages | https://github.com/gonzalezreal/textual |
| swift-snapshot-testing | Snapshot testing for SwiftUI views | https://github.com/pointfreeco/swift-snapshot-testing |

Future providers may require additional dependencies (e.g. SQLite.swift for reading agent databases).

SPM handles version resolution, dependency graphs, and build integration. No CocoaPods or Carthage needed -- all libraries support SPM natively.

---

## Library Stack

| Purpose | Library | Notes |
|---|---|---|
| Agent process management | Foundation `Process` | Piped stdin/stdout for bidirectional JSON streaming |
| App database | SwiftData | `@Model` macros, automatic migrations, `@Query` for SwiftUI |
| Dependency injection | Knit | Type-safe DI with code generation, built on Swinject |
| Markdown rendering + syntax highlighting | Textual | Successor to MarkdownUI by the same author. `StructuredText` for block-level markdown, `InlineText` for inline. Built-in syntax highlighting via Prism.js (~55 languages bundled, extensible). Includes `diff` language mode with `.inserted`/`.deleted` token types. Theming via `StructuredText.HighlighterTheme` API (nested type; `TokenType` is `StructuredText.HighlighterTheme.TokenType`). |
| Diff rendering | Custom `DiffParser` | Parses unified diff output (`git diff`) into structured models (`DiffFile`, `DiffHunk`, `DiffLine`). See **Diff Parser** section. |
| Networking | Foundation `URLSession` | skills.sh API, GitHub Trees API, raw SKILL.md content fetching |
| Cryptography | `CryptoKit` (SHA-256) | Short branch hash generation for worktree names |
| JSON parsing | Foundation `JSONSerialization` | For agent JSON line output and config files |
| File I/O | `FileManager` / `JSONSerialization` | Atomic writes via `replaceItemAt` |
| Snapshot testing | swift-snapshot-testing (Point-Free) | SwiftUI view snapshot comparison |

### Sandboxing Considerations

A Mac App Store app with App Sandbox **cannot** spawn arbitrary child processes or access arbitrary filesystem paths. The app must either:

1. **Distribute outside the App Store** (direct download, Homebrew, etc.) with Hardened Runtime but without App Sandbox.
2. **Use App Sandbox with temporary exceptions** -- entitlements like `com.apple.security.temporary-exception.files.absolute-path.read-only` for specific paths, but this is fragile and Apple may reject it.

The app needs unrestricted access to:
- `~/.claude/`, `~/.claude.json` (read and write)
- `<arbitrary-cwd>/.claude/settings.local.json` (read and write)
- `/usr/local/bin/`, `~/.local/bin/`, etc. (to find CLI executables)
- Child process spawning (Foundation `Process`)

**Hardened Runtime** (required for notarization) is fine -- it doesn't restrict process spawning or filesystem access. App Sandbox is the constraint.

---

## Project Structure

Source code is organized by responsibility into top-level folders:

```
Skep/
  App/                          — Phase 1 placeholder `SkepApp`, later real app entry point, AppDelegate, window setup, ContentView
  Data/                         — SwiftData models (Project, AgentThread, Conversation, ConversationEventRecord)
  Services/                     — All injectable service protocols and implementations
    Agent/                      — AgentsManager, ClaudeAdapter, AgentEnvironmentBuilder, ClaudeConfigStore, ProviderSetupService
    Git/                        — GitService, WorktreeManager, GitHubService, GitHubCLIService
    Session/                    — SessionManager
    Skills/                     — SkillsService
    MCP/                        — MCPService
    Settings/                   — SettingsService, SkepProjectConfig
    Detection/                  — ProviderDetectionService, ProviderRegistry
    Notification/               — NotificationManager
    Shell/                      — ShellRunner
    FileList/                   — FileListManager
  DiffParser/                   — DiffFile, DiffHunk, DiffLine, DiffParser (pure parsing, no dependencies)
  ViewModels/                   — All @Observable view models
    ConversationViewModel.swift
    DiffViewerViewModel.swift
    SidebarViewModel.swift
    SkillsViewModel.swift
    MCPViewModel.swift
    SettingsViewModel.swift
  Views/                        — All SwiftUI views
    Chat/                       — ChatView, ConversationView, message bubbles, working blocks
    Sidebar/                    — SidebarView, project/thread list
    DiffViewer/                 — DiffViewerPane, file list, inline diff rendering
    Skills/                     — SkillsScreen, skill cards, skill detail modal
    MCP/                        — MCPScreen, server list, add/edit form
    Settings/                   — SettingsScreen, tab content views
    Components/                 — Shared UI components (EmptyStateView, InlineBanner, etc.)
    Input/                      — ChatInputField, @-mention popup, /skill popup, StreamingBubble
  DI/                           — Knit ModuleAssembly definitions
    Generated/                  — Knit-generated resolver extensions (phase-1 placeholder file exists so XcodeGen includes the path; do not edit the generated contents)
  Utilities/                    — Extensions, helpers, AutoNaming, StderrBuffer, MessageQueue, TurnState, SetupPhase
  Resources/                    — Assets, sounds, app icon
SkepTests/
  Services/                     — Unit tests mirroring the Services/ structure
  ViewModels/                   — Unit tests for view models
  Snapshots/                    — Snapshot tests for views
```

Each `Services/` subfolder contains the protocol and concrete implementation for that service. Knit `ModuleAssembly` files live under `Skep/DI/`, and tests mirror the runtime structure under `SkepTests/`.

Because `Skep` is an application target rather than a library target, Phase 1 also includes a tiny compile-through app stub in `Skep/App/SkepApp.swift` plus an empty `Skep/App/AppDelegate.swift` shell:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {}

@main
struct SkepApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("Skep", id: "main") {
            EmptyView()
        }
    }
}
```

Part 4a replaces only the placeholder scene body with the real layout; Part 4e later fills in the already-existing `AppDelegate` with lifecycle behavior.

---

## Dependency Injection: Knit

Knit (https://github.com/cashapp/knit) is a compile-time code generation tool that adds type safety to Swinject. Created by Block, Inc. (Cash App/Square), MIT licensed, used in production at Cash App. Swinject provides the runtime DI container; Knit generates type-safe resolver extensions and module dependency validation on top of it. Knit can also generate resolver-test files when you wire extra outputs, but this plan's documented build only emits `KnitExtensions.swift`.

Throughout this plan, `Resolver` refers to the root Swinject/Knit resolver type used as the `TargetResolver` for app assemblies.

### What It Provides

Swinject's `resolve()` calls are stringly-typed and return optionals at runtime. Knit fixes this with:

- **Type-safe generated resolver functions** -- `resolver.gitService()` instead of `resolver.resolve(GitService.self)!`.
- **Module dependency tree validation** -- declare which modules depend on which; `ModuleAssembler` walks the tree depth-first.
- **Duplicate registration detection** -- compile-time (within a module) and runtime (across modules).
- **Optional generated resolver tests** -- available when you wire extra Knit outputs, but not relied on by the v1 build described here.
- **Module replacement for testing** -- `FakeAssembly` and `replaces` for swapping modules with fakes.

### How It Works

Define a module (note: `TargetResolver` associated type is required):
```swift
// Example pattern -- specific services are defined in later parts
final class ExampleAssembly: ModuleAssembly {
    typealias TargetResolver = Resolver
    static var dependencies: [any ModuleAssembly.Type] { [] }

    func assemble(container: Container<TargetResolver>) {
        container.register(SomeService.self) { resolver in
            DefaultSomeService()
        }
    }
}
```

Bootstrap and resolve:
```swift
// The assembler must be retained for the app's lifetime — it owns the
// Swinject Container. In the app, it's a module-scope `let` shared by
// SkepApp and AppDelegate (see SkepApp.swift).
let assembler = ScopedModuleAssembler<Resolver>(
    [AgentAssembly(), GitAssembly(), SessionAssembly()]
)
let resolver = assembler.resolver
let gitService = resolver.gitService()  // generated, type-safe
```

### Data Assembly

Registers the SwiftData `ModelContainer` (singleton) and `ModelContext` (transient). The container is created lazily on first resolve — safe because `assemble()` only stores the closure, and the first resolve happens after app launch.

Important scoping rule: `ModelContext` is operation-local infrastructure, not long-lived service state. `.container` services and actors must not store a resolved `ModelContext`; only SwiftUI environment code and short-lived `@MainActor` view models may hold one across method calls.

```swift
// Skep/DI/DataAssembly.swift
final class DataAssembly: ModuleAssembly {
    typealias TargetResolver = Resolver
    static var dependencies: [any ModuleAssembly.Type] { [] }

    func assemble(container: Container<TargetResolver>) {
        container.register(ModelContainer.self) { _ in
            try! ModelContainer(
                for: Project.self, AgentThread.self,
                Conversation.self, ConversationEventRecord.self
            )
        }
        .inObjectScope(.container)  // Singleton — one container for the app

        container.register(ModelContext.self) { resolver in
            ModelContext(resolver.modelContainer())
        }
        // Transient — each caller gets its own context (all on @MainActor)
    }
}
```

### Concrete Assembly Example

A real assembly for the Git service layer, showing dependencies, scoping, and test replacement. Assemblies are written last within each phase, after all the types they wire are implemented.

```swift
// Skep/DI/GitAssembly.swift
final class GitAssembly: ModuleAssembly {
    typealias TargetResolver = Resolver
    static var dependencies: [any ModuleAssembly.Type] { [ShellAssembly.self, SettingsAssembly.self] }

    func assemble(container: Container<TargetResolver>) {
        // ShellRunner is resolved from ShellAssembly (declared dependency above).
        container.register(GitService.self) { resolver in
            CLIGitService(shell: resolver.shellRunner())
        }
        .inObjectScope(.container)  // Singleton — shared across the app

        container.register(WorktreeManager.self) { resolver in
            DefaultWorktreeManager(
                settingsService: resolver.settingsService(),
                shell: resolver.shellRunner()
            )
        }
        .inObjectScope(.container)

        container.register(FileListManager.self) { resolver in
            GitFileListManager(gitService: resolver.gitService())
        }
        .inObjectScope(.container)
    }
}

// Skep/DI/GitFakeAssembly.swift (for tests)
final class GitFakeAssembly: ModuleAssembly {
    typealias TargetResolver = Resolver
    static var replaces: [any ModuleAssembly.Type] { [GitAssembly.self] }
    static var dependencies: [any ModuleAssembly.Type] { [] }

    func assemble(container: Container<TargetResolver>) {
        container.register(GitService.self) { _ in MockGitService() }
        container.register(WorktreeManager.self) { _ in MockWorktreeManager() }
        container.register(FileListManager.self) { _ in MockFileListManager() }
    }
}
```

Knit's generated code (via the pre-build `knit-cli gen` step in this project) produces type-safe resolver extensions from these registrations:
```swift
// Generated by Knit — do not edit
extension Resolver {
    func gitService() -> GitService { knitUnwrap(resolve(GitService.self)) }
    func worktreeManager() -> WorktreeManager { knitUnwrap(resolve(WorktreeManager.self)) }
    func fileListManager() -> FileListManager { knitUnwrap(resolve(FileListManager.self)) }
}
```

The full list of assemblies (one per service):
- `DataAssembly` — `ModelContainer` (singleton), `ModelContext` (transient — one per resolve, all on `@MainActor`)
- `ShellAssembly` — `ShellRunner`
- `SettingsAssembly` — `SettingsService`
- `DetectionAssembly` — `AgentRegistry`, `ProviderDetectionService`, `ProviderRegistry`
- `AgentAssembly` — `AgentsManager` plus its shared `ConversationRuntimeStore` alias (both backed by `DefaultAgentsManager`), `AgentEnvironmentBuilder`, `NotificationManager`, `ClaudeConfigStore`, `ProviderSetupService`
- `SessionAssembly` — `SessionManager`
- `GitAssembly` — `GitService`, `WorktreeManager`, `FileListManager`
- `GitHubAssembly` — `GitHubCLIService`, `GitHubService`
- `SkillsAssembly` — `SkillsService`
- `MCPAssembly` — `MCPService`

Every service above except `ModelContext` is registered with `.inObjectScope(.container)`. Do not rely on Swinject's transient default for stateful services such as `AgentsManager`, `SessionManager`, `SettingsService`, or `GitHubCLIService`.

### Code Generation

Knit uses **compile-time code generation via SwiftSyntax**, not runtime reflection. A CLI tool (`knit-cli`) and SPM build plugin parse assembly files and generate type-safe resolver extensions. They can also generate resolver test files when explicitly configured with those outputs. A `@Resolvable` macro can auto-generate factory functions from `init()` signatures.

**Important (validated)**: `KnitBuildPlugin` is **Xcode-project-only** — it uses `XcodeProjectPlugin` and requires a `knitconfig.json` file. It `fatalError`s for pure SPM targets. The project uses `knit-cli gen` as a pre-build script phase instead of the build plugin. The CLI accepts `--assembly-input-path` (not `--config`); `knitconfig.json` is only for the build plugin. The documented pre-build script generates `Skep/DI/Generated/KnitExtensions.swift` with type-safe resolver extensions only, so do not assume generated XCTest files exist unless you add those output paths later.

**Historical fallback validation (Knit 1.x)**: XcodeGen + `knit-cli gen` pipeline previously built under Xcode 26.3 / Swift 6.2. `knitconfig.json` is retained for documentation but not used by the CLI. **The current implementation stays on Knit 2.x but pins a main-branch revision** (`3d4afea562b95a95725f689be819b10ff93351fc`) because it contains the upstream `Resolver` → `KnitResolver` workaround required for Xcode 26.3's `ExtractAppIntentsMetadata` pass. Keep that pin until the next tagged Knit release includes the same fix. See `validation.md` for the current version-specific checks.

### SwiftUI Integration

Pass the resolver into views explicitly -- no built-in `@EnvironmentObject` integration:
```swift
// Simplified example -- see How View Models Are Created for the full App entry point
let assembler = ScopedModuleAssembler<Resolver>(...)
let resolver = assembler.resolver
let gitService = resolver.gitService()  // Type-safe, generated by Knit
```

### Considerations

- **macOS 26 minimum** (driven by Liquid Glass UI requirements; also satisfies Swift concurrency needs).
- **Swinject vendored directly** in Knit's source. No separate Swinject dependency. Knit re-exports Swinject types via `@_exported import`.
- **`assemble()` is `@MainActor`** -- all registration on the main actor.
- **Resolution is still runtime** under the hood -- Swinject's dictionary lookup. Knit's generated code force-unwraps with `knitUnwrap()` providing detailed error messages if resolution fails.
- **SwiftSyntax dependency** for code generation -- heavy, must match Swift toolchain version.
- **Low external adoption** but battle-tested internally at Block (Cash App).
- **Comment-driven configuration** (`// @knit public`, `// @knit alias("name")`) -- magic comments not checked by compiler.
- **Factory argument limit of 9** (inherited from Swinject).

---
