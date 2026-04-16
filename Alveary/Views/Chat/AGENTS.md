## Chat View Details

These instructions cover chat-specific view code under `Alveary/Views/Chat/`.

- Conversation rename in multi-conversation tabs is inline via `editingConversationID` in `ConversationTabChip`, not a separate modal flow.
- Transcript auto-follow should stay pinned when the user is already at the bottom and new content increases transcript height, including wrapped streaming-bubble growth. Treat content-size growth differently from a user-initiated scroll-away so the `Jump to bottom` affordance only appears after the user actually leaves the bottom.
- In `ChatTranscriptView`, keep the bottom inset inside the `chat-bottom` scroll target instead of as trailing stack padding. Bottom padding after the anchor leaves a small extra scroll range when entering a thread or jumping to the bottom.
- Transcript follow mode should also survive transcript viewport-height changes caused by bottom-area composer banners or strips appearing and disappearing. If the user did not scroll and they were already near bottom, treat container-height changes like other bottom-pinned layout changes and keep the transcript anchored.
- Composer top separators that appear while the transcript is scrolled up should live in the composer panel's background layer, not a parent overlay, so autocomplete popups can cover them without the separator bleeding through.
- `ThreadDetailConversationTabs` should keep the system `.bar` background for the header chrome and add any custom separator as an overlay. Replacing the bar with `windowBackgroundColor` creates an unintended dark strip in the live app.
- Conversation tab chips are not list rows, but they should mirror the same press-feedback principles: let the select action own the full capsule hit area, overlay trailing affordances like the close button on top of that surface, and prefer fill changes over capsule strokes for selected styling because macOS can render stray vertical artifacts from chip outlines in snapshots.
- `EmptyThreadState` checks `isCancellingInitialSetup` before `setupPhase` so cancellation feedback takes precedence even when `setupPhase` is still set mid-rollback. Keep that ordering if you restructure the view; otherwise the empty-thread pane will flicker back to "Creating worktree" during the rollback shell commands.
