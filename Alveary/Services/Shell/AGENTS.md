# Shell Services

These instructions apply to process execution helpers under `Alveary/Services/Shell/`.

- **Drain pipes while waiting.** `DefaultShellRunner` must drain stdout and stderr concurrently with process execution; waiting for exit before draining can deadlock children whose output fills the pipe buffer.
- **Cover pipe capacity.** Shell runner output tests should include output larger than the platform pipe buffer when changing bounded capture, timeout, or cancellation behavior.
