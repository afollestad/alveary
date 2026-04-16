## Session Management

These instructions cover the session manager under `Alveary/Services/Session/`.

- `SessionEntry`'s canonical cwd plus paired `appSessionId` / `launchSessionId` are required for Claude fork-session recovery and startup orphan cleanup. Resume/orphan flows must preserve both IDs and use canonicalized paths rather than recomputing ownership from raw process state alone.
- `SessionManager.persist()` must remain off `@MainActor`. `AppDelegate.applicationWillTerminate(_:)` bridges the final repair-path persist through `Task.detached` while synchronously blocking the main thread on a bounded semaphore; moving session persistence onto the main actor would deadlock shutdown.
