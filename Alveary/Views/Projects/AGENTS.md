## Project Settings Views

These instructions cover the project settings UI under `Alveary/Views/Projects/`.

- Project actions are edited from project settings via `.alveary.json`, but they surface in the main toolbar only while a thread for that project is selected. Execution should prefer the thread's `worktreePath` and only fall back to the project root when no worktree exists.
