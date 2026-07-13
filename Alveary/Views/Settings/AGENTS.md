## Settings Screen

These instructions cover settings UI files under `Alveary/Views/Settings/`.

- Keep settings sections/tabs sorted alphabetically by their visible title everywhere they are displayed. `AppSettings.SettingsPage.allCases` drives the sidebar and compact picker, so update the enum case order, tab switch cases, presentation switches, and snapshots together when adding or renaming a settings tab.
- Keep `Archived Tasks` as the first Threads section. It remains visible with a subtle empty row, and its restore and permanent-delete actions route through `ArchivedTasksSettingsViewModel`.
