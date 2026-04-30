## Git And Worktree Services

These instructions cover the services under `Alveary/Services/Git/`, including worktree management (`DefaultWorktreeManager`), the GitHub CLI adapter, and low-level git invocations.

## Worktree Lifecycle

- Worktree roots are namespaced by canonical project path under the user-configurable `AppSettings.worktreesBaseDirectory` (default `~/Documents/worktrees`); preserve that namespacing so sibling clones with the same repo folder name cannot collide. `DefaultWorktreeManager.projectWorktreesDirectory(for:worktreesBase:)` reads the expanded base via `AppSettings.expandedWorktreesBaseDirectory`, and `create` / `createFromBranch` must `ensureWorktreeParentDirectoryExists` before invoking `git worktree add` so a fresh base directory is populated.
- `AppSettings.branchPrefix` is literal. Include the separator in the setting/default (for example `alveary/` or `af-`) instead of injecting `/` in `DefaultWorktreeManager`.
- Worktree lifecycle scripts from `.alveary.json` have stable defaults and rollback behavior. `scripts.setup` runs in the new worktree with a default 300-second timeout unless `scripts.setupTimeoutSeconds` overrides it; `scripts.teardown` runs during removal with a 60-second timeout; both receive `ALVEARY_THREAD_NAME`, `ALVEARY_PROJECT_PATH`, `ALVEARY_WORKTREE_PATH`, optional `ALVEARY_BRANCH_NAME`, and `ALVEARY_PORT_SEED`. If `scripts.setup` fails, the manager must attempt to remove the new worktree and delete the rollback branch before surfacing the error.
- Preserved-file copying during worktree creation defaults to `.env`, `.env.local`, and `.env.development` when `.alveary.json` omits `preservePatterns`. Custom `preservePatterns` replace that default list.
- `DefaultWorktreeManager.create()` and `createFromBranch()` are self-cleaning on any failure after `ensureWorktreeParentDirectoryExists`, including task cancellation that interrupts `git worktree add` itself (which can leave an empty target directory behind when SIGTERM arrives mid-add). The internal catch runs `detachedCleanupAfterFailedCreate` as a `Task.detached` so the caller's cancellation cannot abort the removal shell commands; the ViewModel's `rollbackFailedWorktreeCreation` therefore does not need to know about partially-created worktrees. `createFromBranch` passes `rollbackBranch: nil` because it reuses an existing branch.
- `DefaultWorktreeManager.removeWorktree` must always follow `git worktree remove --force` with a `FileManager.removeItem` on the exact thread worktree path — even when the git command fails — because git leaves the directory behind both when untracked content/filesystem quirks interfere and when it never registered the worktree at all (the cancel-during-add case, where git exits with "not a working tree"). Keep that cleanup scoped to the single worktree path — never the shared parent directory returned by `projectWorktreesDirectory`, which hosts sibling threads.

## GitHub CLI

- `gh auth login --web` does not auto-open the browser without a TTY. GitHub auth flows in the app must continue parsing the emitted URL/code and opening the browser explicitly.

## Ahead Commits

- `GitService.commitsAheadOfBase` and `commitsAheadOfBaseDetails` must share the same compare-ref resolution:
    - Prefer `remoteName/baseBranch` when `refs/remotes/<remoteName>/<baseBranch>` exists.
    - When `remoteName` is missing, prefer the current branch upstream, then `origin/baseBranch` if that remote-tracking ref exists.
    - Fall back to the local `baseBranch` only when no remote compare ref can be resolved.
    - Keep count and detail behavior aligned so contextual actions and commit views agree about which commits are ahead.

## Diff Stats

- `GitService.diffStats(in:knownStatuses:)` provides low-level line counts consumed by `DiffWorkspaceStore`:
    - **Use `git diff --numstat`.** Keep parsing machine-readable numstat output instead of localized shortstat text.
    - **Include both scopes.** Sum unstaged `git diff --numstat --` and staged `git diff --cached --numstat --` output so the toolbar reflects all tracked current changes.
    - **Include readable untracked files.** Since Git omits untracked files from `diff --numstat`, add Git-style new-file line counts from porcelain status for small readable untracked files.
    - **Reuse status rows.** When a caller already loaded `status(in:)`, pass those rows into `diffStats(in:knownStatuses:)` instead of running another porcelain status scan.
    - **Share synthetic new-file logic.** Keep untracked toolbar stats and `syntheticAddedDiff(for:in:)` using the same helper so the toolbar and lower-pane preview agree. Match Git intent-to-add behavior: a final newline terminates the last line, it does not add another blank line.
    - **Skip binary rows.** Numstat reports binary files as `-\t-`; ignore those rows rather than guessing line counts. Apply the same skip behavior to untracked files that are binary, too large, or unreadable.
