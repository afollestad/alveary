# Alveary

_An alveary is a place where bees are kept, including a beehive or apiary enclosure._

Alveary is a native macOS app for orchestrating AI coding agents. It's inspired by other apps like OpenAI's Codex.

![Alveary app screenshot](docs/hero.png)

## Download

Download the latest release from [GitHub Releases](https://github.com/afollestad/alveary/releases/latest). Releases are direct-download ZIPs named `Alveary.app.zip` and contain a signed, notarized `Alveary.app`.

After downloading:

1. Unzip `Alveary.app.zip`.
2. Move `Alveary.app` to `/Applications`.
3. Launch Alveary and follow the onboarding checks.

## Roadmap

The public backlog and roadmap are tracked in the [Alveary project board](https://github.com/users/afollestad/projects/3).

## Development

Alveary is built with XcodeGen, `xcsift`, SwiftLint, Needle, AgentCLIKit, and SwiftTerm. AgentCLIKit owns provider processes and resumable sessions; Alveary owns provider-neutral scheduled-task persistence, execution, and recovery. Alveary's app-scoped conversation controllers share each conversation's subscription and persistence path across visible and background work. The embedded terminal runs local PTYs, and project actions are injected into the user's interactive zsh so their real prompt and startup environment apply. The app target intentionally remains unsandboxed while keeping hardened runtime enabled. Run setup once per clone:

```sh
./scripts/setup.sh
```

Generate the Xcode project after project-structure changes:

```sh
xcodegen generate
```

To build, lint, or run the app:

```sh
# Build the app
./scripts/build.sh

# Lint the source
./scripts/lint.sh

 # Run the app without building
./scripts/run.sh

# Build and run the app
./scripts/run.sh -b

# Run the whole test suite
./scripts/test.sh

# Run a focused test class
./scripts/test.sh AlvearyTests/AppDelegateTests
```

Release workflow details live in [RELEASING.md](RELEASING.md).

## License

Alveary is licensed under the [GNU General Public License v3.0](LICENSE.md).
