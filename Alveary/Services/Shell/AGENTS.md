# Shell Services

These instructions apply to process execution helpers under `Alveary/Services/Shell/`.

- **Drain pipes while waiting.** `DefaultShellRunner` must drain stdout and stderr concurrently with process execution; waiting for exit before draining can deadlock children whose output fills the pipe buffer.
- **Preserve raw stdout bytes.** `ShellResult.stdoutData` is required for binary-safe callers such as Git image blob loading; do not rebuild binary output from the UTF-8 `stdout` string.
- **Keep user tools visible.** `DefaultShellRunner` appends the shared fallback executable directories to every child `PATH` while preserving existing path order, so Finder-launched app processes can still resolve Homebrew/local tools such as Git LFS filter helpers.
- **Cover pipe capacity.** Shell runner output tests should include output larger than the platform pipe buffer when changing bounded capture, timeout, or cancellation behavior.
