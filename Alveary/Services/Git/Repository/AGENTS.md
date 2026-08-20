## Repository Git Invocations

These instructions cover `Alveary/Services/Git/Repository/` — the `GitService` protocol and `CLIGitService`'s low-level `git` invocations: status, commits, branches, diff stats, and blob reads.

## Ahead Commits

- The ahead-of-base family lives in `CLIGitService+AheadCommits.swift`: count, details, the unpushed check, and their shared ref helpers. `GitService.hasUnpushedCommits`'s distinction from `commitsAheadOfBase` is documented on the protocol.
- `GitService.commitsAheadOfBase` and `commitsAheadOfBaseDetails` must share the same compare-ref resolution, and it is anchored on the **resolved default branch**, not the caller's `baseBranch`:
    - Resolve the remote with `effectiveRemoteName`, then the default branch with `resolvedDefaultBranch`. Prefer `<remote>/<default>` when its remote-tracking ref is known to exist, otherwise the local default branch.
    - Only when nothing resolves does the caller's `baseBranch` come into play: `<remote>/<baseBranch>`, then the local `baseBranch`, then the current branch upstream, then `baseBranch` as-is.
    - **Treat `baseBranch` as a hint, never the authority.** It comes from `Project.baseRef`, which `SidebarViewModel.resolveBaseRef` captures once at project import and falls back to whichever branch was checked out then — there is no re-detection and no override UI. A project imported on a feature branch used to make this resolve to the current branch's upstream, which turned the Commits tab into "commits not yet pushed". A Task thread carries no project and so no `remoteName` at all, which hit the same path.
    - **On the default branch the answer is still the unpushed commits**, because the compare ref is the remote-tracking form; off it, the list is everything the default branch does not have yet. Both are wanted.
    - Keep count and detail behavior aligned so contextual actions and commit views agree about which commits are ahead.

## Default Branch

- `CLIGitService+DefaultBranch.swift` owns default-branch resolution; its doc comments cover the resolution order, `hasRemoteTrackingRef`, and the `effectiveRemoteName` fallback. The conventional `<remote>/main`/`<remote>/master` probes are load-bearing, not paranoia — only `git clone` writes `refs/remotes/<remote>/HEAD` and plenty of working clones lack it.
- The `refs/remotes/<remote>/HEAD` parsing is deliberately duplicated in `SidebarViewModel.parseRemoteHead`. That view model holds a `ShellRunner` rather than a `GitService`, so sharing would mean injecting a new dependency and churning the import-invocation assertions in `SidebarViewModelTests`.
- **`GitServiceTests+Commits.swift` asserts exact `MockShellRunner` invocation sequences.** Any probe added or removed here shifts those indices, so update the enqueued results and the asserted argv together.

## Diff Stats

- `GitService.diffStats(in:knownStatuses:)` (consumed by `DiffWorkspaceStore`):
    - **Use `git diff --numstat`.** Keep parsing machine-readable numstat output instead of localized shortstat text.
    - **Include both scopes.** Sum unstaged `git diff --numstat --` and staged `git diff --cached --numstat --` output so the toolbar reflects all tracked current changes.
    - **Include readable untracked files.** Since Git omits untracked files from `diff --numstat`, add Git-style new-file line counts from porcelain status for small readable untracked files.
    - **Reuse status rows.** When a caller already loaded `status(in:)`, pass those rows into `diffStats(in:knownStatuses:)` instead of running another porcelain status scan.
    - **Share synthetic new-file logic.** Keep untracked toolbar stats and `syntheticAddedDiff(for:in:)` using the same helper so the toolbar and lower-pane preview agree. Match Git intent-to-add behavior: a final newline terminates the last line, it does not add another blank line.
    - **Skip binary rows.** Numstat reports binary files as `-\t-`; ignore those rows rather than guessing line counts. Apply the same skip behavior to untracked files that are binary, too large, or unreadable.

## Image Blobs

- **Keep blob reads binary-safe and bounded.** Image preview loading uses `GitService.imageBlob(source:maxBytes:in:)`; preserve raw stdout bytes for git objects and reject oversized source blobs before decode.
- **Open worktree images directly.** Worktree image sources already exist on disk, so opening one must not copy it to a temp file. Commit, parent, HEAD, and index sources still need temp materialization.
