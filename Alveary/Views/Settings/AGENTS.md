## Settings Screen

These instructions cover settings UI files under `Alveary/Views/Settings/`.

- Keep settings sections/tabs sorted alphabetically by their visible title everywhere they are displayed. `AppSettings.SettingsPage.allCases` drives the sidebar and compact picker, so update the enum case order, tab switch cases, presentation switches, and snapshots together when adding or renaming a settings tab.
- Settings has no archived-threads surface. The sidebar `Archived` row and `Alveary/Views/Archived/` own that entirely; do not reintroduce an `Archived Tasks` section to the Threads tab.
