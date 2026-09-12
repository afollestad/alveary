## Project workspace migration

- Keep the bridge model declarations frozen; they retain legacy columns until workspace snapshots and project IDs have been saved. Change the current models outside this scope.
- Preserve persisted paths literally during backfill; migration must not inspect directories or resolve symlinks.
- Upgrade copies before replacing the original store, keeping SQLite companions together and preserving the original on failure.
