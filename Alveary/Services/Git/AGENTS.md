## Git And Worktree Services

These instructions cover the services under `Alveary/Services/Git/`, including worktree management (`DefaultWorktreeManager`), the GitHub CLI adapter, and low-level git invocations.

## Worktree Lifecycle

- Worktree roots are namespaced by canonical project path under the user-configurable `AppSettings.worktreesBaseDirectory` (default `~/Documents/worktrees`); preserve that namespacing so sibling clones with the same repo folder name cannot collide. `DefaultWorktreeManager.projectWorktreesDirectory(for:worktreesBase:)` reads the expanded base via `AppSettings.expandedWorktreesBaseDirectory`, and `create` / `createFromBranch` must `ensureWorktreeParentDirectoryExists` before invoking `git worktree add` so a fresh base directory is populated.
- Worktree lifecycle scripts from `.alveary.json` have stable defaults and rollback behavior. `scripts.setup` runs in the new worktree with a default 300-second timeout unless `scripts.setupTimeoutSeconds` overrides it; `scripts.teardown` runs during removal with a 60-second timeout; both receive `ALVEARY_THREAD_NAME`, `ALVEARY_PROJECT_PATH`, `ALVEARY_WORKTREE_PATH`, optional `ALVEARY_BRANCH_NAME`, and `ALVEARY_PORT_SEED`. If `scripts.setup` fails, the manager must attempt to remove the new worktree and delete the rollback branch before surfacing the error.
- Preserved-file copying during worktree creation defaults to `.env`, `.env.local`, and `.env.development` when `.alveary.json` omits `preservePatterns`. Custom `preservePatterns` replace that default list.
- `DefaultWorktreeManager.create()` is self-cleaning on any post-`git worktree add` failure, including task cancellation. The internal catch runs `detachedCleanupAfterFailedCreate` as a `Task.detached` so the caller's cancellation cannot abort the removal shell commands; the ViewModel's `rollbackFailedWorktreeCreation` therefore does not need to know about partially-created worktrees.
- `DefaultWorktreeManager.removeWorktree` must follow `git worktree remove --force` with a `FileManager.removeItem` on the exact thread worktree path, because git can leave the now-empty thread directory behind when untracked content or filesystem quirks interfere. Keep that cleanup scoped to the single worktree path — never the shared parent directory returned by `projectWorktreesDirectory`, which hosts sibling threads.

## GitHub CLI

- `gh auth login --web` does not auto-open the browser without a TTY. GitHub auth flows in the app must continue parsing the emitted URL/code and opening the browser explicitly.
