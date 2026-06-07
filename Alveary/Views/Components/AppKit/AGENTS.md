## Shared AppKit Components

Shared AppKit-only primitives live here.

- **Keep ownership broad.** Put AppKit helpers here when more than one surface uses them; do not hide cross-cutting primitives under Markdown, Input, or Transcript scopes.
- **Centralize dynamic colors.** Views that cache dynamic `NSColor` values into layer `CGColor`s or `contentTintColor` should use the shared dynamic-color/tint helpers so theme changes do not require one-off appearance observers.
- **Share popover chrome.** `AppKitComposerPopoverChrome.swift` owns shared AppKit popover surfaces and dividers; do not duplicate composer popover surface or divider styling in `Input/`.
