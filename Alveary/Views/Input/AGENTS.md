## Composer Input

These instructions cover `Alveary/Views/Input/` — composer view code shared across its parts: the focus handle, the mode and presentation types, attachments, local-command parsing, and the queued-message rows. Narrower scopes:

- `Alveary/Views/Input/Editor/AGENTS.md`: the BlockInputKit bridge and draft plumbing.
- `Alveary/Views/Input/ActionRow/AGENTS.md`: the action row, its buttons, and the popovers they open.
- `Alveary/Views/Input/Reasoning/AGENTS.md`: the model, effort, and speed popover.

The AppKit panel all of this sits in is `Alveary/Views/Chat/Composer/AGENTS.md`, and `Alveary/Views/Chat/AGENTS.md` owns what a local command *does* once parsed.

> **READ FIRST — Focus and keyboard rules are centralized.** Before touching `@FocusState`, `.focusedSceneValue`, `.onKeyPress`, or `.keyboardShortcut` in this folder, consult the **Focus And Keyboard Coordination** section in `Alveary/Views/AGENTS.md`.

- **Preserve `stagedContext` through queued-message edit, rollback, send, steer, and session-handoff draft flows** unless the user explicitly dismisses it.
- **Scope `/effort` and `/model` to what the current selection actually offers.** Enable, reserve, suggest, and intercept `/effort` only while the selected model advertises effort options, and `/model` only with two or more candidates. `/model`'s candidates mirror `reasoningConfiguration.modelGroups` exactly — every ready provider before initial setup, the active provider afterward — so a pre-startup `/model` can switch provider through the same callback the picker uses.
- **Typed model names come from `AgentCLIKit.AgentModelOption.shortName`.** Do not derive, slugify, or hardcode short names app-side.
