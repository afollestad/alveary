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

## Projects and source folders

A project groups zero or more source folders. Folders can be ordinary directories or Git repositories, and the same folder can belong to multiple projects. Create or edit a project to add folders and choose its primary folder. Removing a folder from a project does not delete it from disk.

**New thread** opens one draft. Choose a project, Tasks, or a custom section without losing your composer content, then configure its workspace using the adjacent control. Git folders show the selected Local or Worktree mode. A project supplies its current primary folder and grants access to its other folders; change the primary folder in project settings. Each thread has at most one primary worktree. Empty projects and standalone threads receive a private workspace.

Once a thread starts, its workspace is saved independently. Later project edits seed new threads; they do not change existing sessions or scheduled runs. Additional folder grants can be edited while a thread's sole conversation is idle and no schedule owns its workspace.

The toolbar's folder picker chooses the repository for diffs, commits, pushes, pull requests, project actions, and new terminals. A thread's primary folder maps to its worktree; secondary folders use their local checkout. Each source folder keeps its own `.alveary.json`. File completion searches every granted folder and inserts absolute file references, with folder labels when names overlap.

## Development

Alveary is built with XcodeGen, `xcsift`, SwiftLint, Needle, AgentCLIKit, BlockInputKit, FluidAudio, and SwiftTerm. AgentCLIKit owns provider processes and resumable sessions; Alveary owns provider-neutral scheduled-task persistence, execution, and recovery. Alveary's app-scoped conversation controllers share each conversation's subscription and persistence path across visible and background work. BlockInputKit provides the markdown editors. FluidAudio provides English speech recognition for on-device voice input on Apple silicon. Primer Octicons supplies the pull-request status glyphs. The embedded terminal runs local PTYs, and project actions are injected into the user's interactive zsh so their real prompt and startup environment apply. The app target intentionally remains unsandboxed while keeping hardened runtime enabled. Run setup once per clone:

```sh
./scripts/setup.sh
```

The AgentCLIKit pin includes explicit-root overrides on Codex resume, including launches without host tools. `swift-custom-dump` is pinned to a release using the current IssueReporting package identity to keep package resolution compatible with snapshot testing.

Validation and release builds run on GitHub's `xcode-27` runner with Xcode 27.0 explicitly selected in both workflows. Each job installs the optional Metal toolchain for SwiftTerm's shaders and logs its macOS and compiler versions for comparison with local runs.

Project upgrades migrate a copy of the database before installing it. The original database and SQLite companions remain available beside the store. A failed upgrade shows recovery details with Retry and Quit; it never substitutes an empty database.

Provider-session cleanup borrows the runtime's AgentCLIKit adapters so Codex archive and delete requests reach the server holding each thread's writer lock. Approval continuations explicitly resume runtime activity so the transcript and task indicators stay synchronized.

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

# Run in demo mode: a DEBUG-only isolated profile, wiped and reseeded with fake
# data each launch, for screenshots
./scripts/run.sh --demo

# Run the whole test suite
./scripts/test.sh

# Run a focused test class
./scripts/test.sh AlvearyTests/AppDelegateTests
```

Release workflow details live in [RELEASING.md](RELEASING.md).

## Menu Bar

Alveary keeps a system menu bar item with your five most recent threads plus New Thread, Open Alveary, Settings, and Quit. Because that item is a way back into the app, closing the main window no longer quits Alveary: agent runs, scheduled tasks, and the app-shot shortcut keep going, and clicking the Dock icon or **Open Alveary** brings the window back. Turn the item off in **Settings → Menu bar**; the Dock icon remains either way.

The same tab has **Launch at startup**, which registers Alveary as a macOS login item. macOS owns that registration, so the switch reflects System Settings → General → Login Items rather than a saved preference, and it tells you when the item is switched off there.

## Pull Request Reviews

Single-agent review is the default. In **Settings → Git → Pull requests**, choose **Review team** to configure one team of 2–5 distinct models. Reviewers inspect independently, cross-check findings, and propose comments supported by a fixed majority. The lead also consolidates findings. One task shows progress, failures, votes, cancellation, and retry controls; nothing is submitted without confirmation.

**Manage** edits the lead and peers together. Single-agent review shows its agent controls inline; **Address feedback** has independent agent and permission settings.

**Run details** exposes per-reviewer attempts, exact app prompts and final responses, pinned input files, candidate consolidation, and vote decisions. History stays local to the task, survives proposal handling, and is deleted with the task. Older runs retain validated results but may lack exact execution history.

If a reviewer fails, the review pauses before proposing feedback. Retry only the failed reviewers, or explicitly continue with the available majority. Paused runs stay paused after relaunch; insufficient quorum cannot continue.

Team workers use sessionless, read-only CLI configurations without user hooks, plugins, MCP servers, or extra arguments. Their app-owned packets contain the complete diff and published feedback. This is not an OS-level packet-only read boundary or a guarantee of network isolation. Unsupported CLI capabilities or unavailable model pins block launch; availability checks do not send paid prompts.

Review-team worker process groups use the system `/usr/bin/perl` launcher and fail preflight when it is unavailable.

Large pull-request reviews automatically fall back to a temporary bare Git repository when GitHub refuses the full diff. Alveary uses your existing GitHub CLI sign-in, then serves the complete textual diff in resumable pages. Preparation may take several minutes; review tasks do not need a project checkout.

## GitHub Attachments

Comment and review attachments use GitHub CLI 2.99.0 or newer with repository write access. Supported images and videos upload using your existing GitHub CLI sign-in. See [attachment implementation and troubleshooting](docs/github-attachments.md) for formats, limits, and repair guidance.

## Voice Input

Voice input records from the system-default microphone and transcribes English speech on device. Microphone audio and recognition output are not stored separately or sent to remote servers; committed dictation becomes ordinary composer text. Dictation requires Apple silicon, while Alveary remains a universal app.

The first use opens a blocking setup modal that downloads the approximately 600 MB Parakeet Unified model from Hugging Face and caches validated model files by revision under `~/Library/Application Support/com.afollestad.alveary/VoiceInput/Models/`, excluded from backups. Later launches skip the modal when the microphone is authorized and the cached model is still valid: warmup happens in place, and a still-valid activation starts dictation automatically.

Alveary pins FluidAudio exactly and downloads the model from the exact Hugging Face revision in `VoiceInputModelDescriptor.json`. There is no periodic or manual model-update check; changing the pin requires a new Alveary release. Model files are distributed separately on demand under the model's CC-BY-4.0 license, and the app bundles the required dependency and model attribution.

Maintainers regenerate the sorted descriptor and its verification digest with an explicit 40-character revision; the script never selects `main`:

```sh
./scripts/update-voice-model-descriptor.py --revision <hugging-face-commit>
```

Debug builds expose **Developer → Clear Voice Model Cache**, which refuses while dictation or model preparation is active and otherwise removes validated and resumable model data.

## License

Alveary is licensed under the [GNU General Public License v3.0](LICENSE.md).
