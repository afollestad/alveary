# Projects and source folders

A project groups zero or more source folders. Folders can be ordinary directories or Git repositories, and a folder can belong to several projects. Create or edit a project to add folders and choose its primary folder. Removing a folder from a project doesn't delete it from disk.

## Thread workspaces

**New thread** opens a draft. Choose a project, Tasks, or a custom section without losing what you've typed, then set up its workspace with the control beside it, where Git folders offer Local or Worktree mode. A thread works in its project's primary folder, with access to the project's other folders, and has at most one worktree. Empty projects and standalone threads get a private workspace.

Once a thread starts, its workspace is saved with it. Later project edits apply only to new threads, not to existing ones or scheduled runs. You can still change which other folders a thread can reach while its only conversation is idle and no schedule owns its workspace.

## Choosing a folder

The toolbar's folder picker chooses the repository for diffs, commits, pushes, pull requests, project actions, and new terminals. A thread's primary folder maps to its worktree, and the other folders use their local checkout. Each source folder keeps its own `.alveary.json`. File completion searches every folder the thread can reach.
