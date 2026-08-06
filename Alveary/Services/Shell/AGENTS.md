# Shell Services

These instructions apply to process execution helpers under `Alveary/Services/Shell/`.

- **Drain pipes while waiting.** `DefaultShellRunner` must drain stdout and stderr concurrently with process execution; waiting for exit before draining can deadlock children whose output fills the pipe buffer.
- **Preserve raw stdout bytes.** `ShellResult.stdoutData` is required for binary-safe callers such as Git image blob loading; do not rebuild binary output from the UTF-8 `stdout` string.
- **Keep user tools visible.** `DefaultShellRunner` appends the shared fallback executable directories to every child `PATH` while preserving existing path order, so Finder-launched app processes can still resolve Homebrew/local tools such as Git LFS filter helpers.
- **`DefaultExecutablePathResolver` caches resolved paths for the life of the process**, which is app-lifetime because `AppComponent.executablePathResolver` is the single shared instance. Resolving spawns `/usr/bin/which` and, on a miss, a login shell per candidate shell, and every `gh` call plus every provider re-check goes through it.
    - **Cache successes only.** Onboarding re-checks a dependency immediately after installing it and the post-wake sweep re-checks every provider, so a cached negative would report a binary that now exists as still missing.
    - **Re-validate a hit with `isExecutableFile` and dedupe concurrent misses through `pendingResolutions`.** The stat catches an uninstall without a subprocess; the shared `Task` is required because the actor suspends at its first `await`, so a cache alone still lets simultaneous callers each spawn their own probe.
- **Cover pipe capacity.** Shell runner output tests should include output larger than the platform pipe buffer when changing bounded capture, timeout, or cancellation behavior.
