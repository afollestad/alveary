## Settings Screen

These instructions cover settings UI files under `Alveary/Views/Settings/`.

- Keep settings sections/tabs sorted alphabetically by their visible title everywhere they are displayed. `AppSettings.SettingsPage.allCases` drives the sidebar and compact picker, so update the enum case order, tab switch cases, presentation switches, and snapshots together when adding or renaming a settings tab. Adding a case shifts *every* `SettingsScreen` snapshot, not only the new tab's: wide baselines show the sidebar list and narrow ones show the segmented picker, and both enumerate `allCases`.
- Session-handoff settings live in the Handoff tab (`SettingsScreen+HandoffTabView.swift`), not Threads; do not reintroduce a `Context management` section to the Threads tab.
- Settings has no archived-threads surface. The sidebar `Archived` row and `Alveary/Views/Archived/` own that entirely; do not reintroduce an `Archived Tasks` section to the Threads tab.
