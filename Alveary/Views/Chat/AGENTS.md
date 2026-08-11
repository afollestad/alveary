## Chat View Details

These instructions cover the chat shell at `Alveary/Views/Chat/` — `AppKitChatSurfaceView`, `ChatView`, and the presentation types they share. Narrower scopes:

- `Alveary/Views/Chat/Conversation/AGENTS.md`: `ConversationView`, its lifecycle, session settings, and transcript data flow.
- `Alveary/Views/Chat/ThreadDetail/AGENTS.md`: conversation resolution, the tab strip gate, and project trust.
- `Alveary/Views/Chat/Composer/AGENTS.md`: composer panel shell, top content, interaction overlays.
- `Alveary/Views/Chat/VoiceInput/AGENTS.md`: dictation and its model modal.
- `Alveary/Views/Chat/Transcript/AGENTS.md`: transcript shell and approvals, plus `Alveary/Views/Chat/Transcript/Scrolling/` and `Alveary/Views/Chat/Transcript/Links/`.
- `Alveary/Views/Chat/ConversationTabs/AGENTS.md`: the conversation tab row.
- `Alveary/Views/Chat/Blocks/AGENTS.md`: block primitives, plus `Alveary/Views/Chat/Blocks/AppKit/`, `Alveary/Views/Chat/Blocks/Prompts/`, `Alveary/Views/Chat/Blocks/Tasks/`, and `Alveary/Views/Chat/Blocks/Tools/`.

`Alveary/Views/Input/AGENTS.md` owns the composer controls a local command reaches through, and `Alveary/ViewModels/Conversation/AGENTS.md` owns what `ConversationViewModel` does with the intent these views route to it.

> **READ FIRST — Focus and keyboard rules are centralized.** Before touching `@FocusState`, `.onKeyPress`, or `.keyboardShortcut` on any chat surface, consult the **Focus And Keyboard Coordination** section in `Alveary/Views/AGENTS.md`.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `ChatPresentation`'s purity, `ChatView.usageSummary`'s render-path restriction, and the surface's mostly-vertical wheel routing each carry theirs.

### The Chat Surface

- **`AppKitChatSurfaceView` owns the active surface's parent layout.** `ChatView` may still build SwiftUI content-mode children, but the vertical transcript/empty-state/composer frame split belongs to the AppKit surface.
- **Clear the draft, then call `appState.requestComposerFocus()`.** Every user-triggered outbound clear takes that one path; do not add another.
- **`EmptyThreadState` checks `isCancellingInitialSetup` before `setupPhase`.** Keep that order, or the pane flickers back to `Creating worktree` while the rollback shell commands run.

### Transcript Bubbles

- **Transcript rendering is AppKit-owned.** Keep live row work under `Blocks/AppKit/`, route it through `Transcript/Scrolling/AppKitTranscriptRowFactory.swift`, and do not reintroduce SwiftUI transcript row views.
- **User bubbles still render as markdown**, slash-command and `@`-mention chips included, by handing `ChatComposerTextSupport.composerTextChips(in:)` to the shared parser as its `composerChipProvider` (`Alveary/Views/Components/Markdown/AGENTS.md`). Chip labels are always `lastPathComponent`, so a bubble needs no working directory.
- **Keep exact AppKit markdown measurement for long static bubbles**, driving frame, clipping, and fade. Show more/less stays on the AppKit header toggle — no bubble-wide gestures, no nested vertical scroll views.

## Interaction Contracts

These capture conversation-view interaction patterns. Keep new UI aligned with them unless intentionally redesigning.

### Presentation Contracts

- **Route content-mode, composer-mode, and thread-setting display decisions through `ChatPresentation` / `ChatThreadPresentation`**, and have SwiftUI hosts and native AppKit views consume the same contracts rather than duplicate the branching.
- **Preserve visuals during native migration.** An AppKit replacement matches the SwiftUI surface it replaces for sizing, spacing, typography, colors, disabled treatment, hover, and pressed states unless a redesign is approved.

### Local Commands

`ChatView+LocalCommands.swift` runs an Alveary local command once `ComposerLocalCommand` has parsed it; `Alveary/Views/Input/AGENTS.md` owns when each one is offered at all.

- **Bare `/effort` and `/model` open the reasoning popover instead of sending.** Both clear only the command text, preserve attachments, send nothing, and do not request editor focus — `/effort` lands on the effort slider, `/model` opens with the Models disclosure expanded and keyboard focus on the selected model row.
- **An argument that is not accepted leaves the composer as it was.** Clear and refocus only on accepted, applied, or unchanged; otherwise retain the draft and attachments and surface either the current dynamic options or the underlying setting error. `/effort <value>` takes exactly one case-insensitive canonical option; `/model <name>` matching order and the `provider:name` qualifier are documented in `ComposerLocalCommand+ModelOptions.swift`.
- **`/fast` toggles first, then sends.** Bare `/fast` only toggles; `/fast <prompt>` toggles and then sends or queues that prompt with the resulting speed as its next-turn requirement. It takes no inline argument hint.
- **`/handoff` passes its argument as the steering prompt, or `nil` for none**, and clears and refocuses once the flow starts. Bare `/handoff` prompts for steering without a countdown.

### Conversation Behavior

#### Queues, Prompts, And Cancellation

- **A queued message belongs to the queue until it is attempted, then to the transcript.** Do not render pending entries as history; once an attempt fails, retry affordances go on the transcript user row rather than moving it back into the queue.
- **An unanswered `AskUserQuestion` owns the conversation's interaction lane.** Keep its submit path available, reject tool approval actions and freeform sends until it is answered, and answer it on the live config even while other settings stage.
- **Answer selection advances to the next unanswered question**, wrapping to earlier gaps; required overlays may still be inspected out of order. Once none remain, show `Submit` and let `Return` submit.
- **Mark a same-turn deferred approval `superseded` once the answer sends**, rather than resuming Claude through the old approval path.
- **A user-requested cancellation is an interruption, not a failure.** A stopped turn clears composer error banners, renders a trailing-aligned `Interrupted` note at the user bubble's right edge, and persists a `stop` session note so restore and archive context do not summarize the turn as an error.

#### Session Handoff

Session handoff is a between-turn hidden flow. Its steering, countdowns, and prompt building live in `Alveary/ViewModels/Conversation/SessionHandoff/` and `Alveary/Services/Settings/`; below are the parts a chat surface can break.

- **Hide the exchange.** The handoff prompt and response never render as transcript rows; one centered `Handing off session...` note appears at start and becomes `Session handed off` once the fresh provider session starts.
- **Seed the fresh session before queues resume.** Staged, edited, and immediate handoff output all take the handoff send path.
- **Keep failures blocking.** A failed hidden handoff holds a blocking retry state so a later visible send cannot continue from provider-only context, and a retry goes straight to the hidden flow reusing already-submitted steering.
- **Restore an interrupted draft** after the handoff seed sends successfully, and also on hidden handoff failure.
- **Keep the two countdowns independent.** `handoffSteeringCountdownSeconds` governs only the user's steering prompt; `handoffPromptSendCountdownSeconds` governs only generated output, where `0s` sends immediately without staging it in the composer.
- **Runtime lifecycle cues are transcript notes, not new bubble styles.** Provider plan-mode transitions take that text-only path — `Entered plan mode`, `Exited plan mode`, and a denied exit as `Staying in plan mode` — never a standalone tool pill.

#### First Sends And Setup

- **A first send is a durable transcript attempt once accepted.**
    - **Materialize a draft atomically.** Insert the first user row and attachment metadata, set `isDraft = false`, and save them together before setup. Publish materialization only after that save succeeds; on failure, roll back to the draft and restore composer state without revealing a sidebar row.
    - **Persist real threads before setup** — `deliverMessageReserved` inserts the user row before initial setup starts.
    - **Keep failures on the transcript.** A setup, spawn, or send failure marks that row retryable instead of returning to a centered empty retry state.
    - **Treat cancellation as reset.** `ConversationViewModel.cancel()` restores draft and staged context, deletes the attempted row, and clears `hasCompletedInitialSetup`; `sendDraft` swallows `CancellationError`.
- **The empty-thread hero's project menu is interactive only for a provisional draft.** Preserve the label's intrinsic width, draw its underline explicitly, and middle-truncate only unusually long names; a materialized transcript-empty thread renders the same larger copy with a static project name.
