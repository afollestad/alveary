## Thread Model

These instructions cover `Alveary/Data/Threads/` — the `AgentThread` row, its Project-versus-Task identity and workspace descriptor, the picker state a composer writes back, and what a thread is called. The models it relates to are `Alveary/Data/AGENTS.md`; the naming *implementation* is `Alveary/Utilities/AutoNaming.swift`, which has no scoped guidance of its own; thread creation and archiving are `Alveary/ViewModels/Sidebar/AGENTS.md`.

**Keep a rule here only when the code that would violate it is not the code that documents it.** `AgentThread+ScheduledTarget` and `+HostToolListing`'s deliberately different eligibility, `TaskWorkspaceDescriptor`'s persisted-path rehydration, `ThreadOpenRequest`'s reason for being a notification, and — over in `Alveary/Utilities/AutoNaming.swift` — how a title candidate is picked, why `customTitle` must stay nil until the user diverges it, and the two-clause test in `shouldFollowThreadRename(previousThreadDisplayName:)` each carry theirs.

### Naming

- **`AgentThread.name` is the visible label; `hasCustomName` is manual-rename state.** Every manual rename flow sets `hasCustomName = true`. Seeding it `true` at creation is how a caller opts out of provider auto-titling — which is why a scheduled run's thread keeps its schedule's title.
- **Provider metadata is the only automatic main title source**, and it applies only while `hasCustomName == false`, leaving the flag false so a later manual rename still wins. Do not auto-title locally from the first user message; Alveary keeps no second durable title source for the main flow.
- **Use `AgentSessionPreviewGenerator.preview(fromInitialPrompt:)` for preview-only needs** — secondary conversation auto-titles and pre-launch worktree slugs, the slugs falling back to the current thread name.
- **A thread rename cascades into the main conversation's `title`.** There is deliberately no separate rename affordance for a sole conversation; the cascade covers it.
- **Read the main conversation's default label from `Conversation.defaultDisplayName()`** (`AgentThread.untitledName`, `"New thread"`); never hard-code `"Main"`.

### Identity And Lifecycle

- **`AgentThread.isDraft` marks the one process-local provisional new-thread row.** Its stored default stays `false` so pre-field stores migrate existing threads as real. A draft owns one persisted main conversation but no provider session, runtime, worktree, branch, setup completion, or visible events.
- **`AgentThread.modeRawValue` is the persisted Project-versus-Task identity**, defaulting old stores to Project. Never derive mode from `project != nil`: a Task's `project` is sidebar placement only, and its workspace and source-project paths live in the flat fields plus `taskWorkspaceDescriptor`.
    - Project deletion detaches Task children instead of cascading into their history.
- **`AgentThread.pinnedSortOrder` shares one dense order with `Project`**, whose rules `Alveary/Data/AGENTS.md` owns.

### Picker State

- **`AgentThread.model` is the per-thread model override**, mirroring the `permissionMode` and `effort` picker pattern with a different nil semantic.
    - **`nil` means "provider default".** The dropdown's `"default"` value is a UI sentinel translated to `nil` before persisting — writing the literal makes the adapter pass `--model=default` to the CLI.
    - **Seed from `AppSettings.defaultModel` at thread creation** (`SidebarViewModel.createThread` maps `"default"` and empty to `nil`); preserve any other non-empty string, since live provider model metadata changes independently of app releases.
    - **Build composer reasoning state from the live DB field.** `ConversationView.composerReasoningSelection` reads `conversation.thread?.model` so the dropdown survives view-model re-inits and forks; no parallel `ConversationState.selectedModel` cache.
- **`AgentThread.effort` is model-scoped** — acceptable values *and* the preferred default depend on the thread's model.
    - **`AgentModelOption.supportedEffortOptions` / `defaultEffortOption`** from `AgentProviderDiscoveryService` are the source of truth; no app-owned effort maps in `AppSettings`, which only trims and falls back empty persisted strings.
    - **Coerce in lockstep with model changes.** Reset unsupported values to the model-option default in the same save as the model write, so SwiftUI sees model and effort invalidate on one render tick and only **one** `reconfigureSession()` fork fires (`ConversationViewModel.applyModelChange`, `SettingsViewModel.defaultModel`).
    - **Seed new threads from Settings**, which owns applying model-option defaults when the default model changes.
    - **Filter the composer dropdown before rendering.** `ConversationView` derives effort options from the selected `AgentModelOption` and passes them down; action-row presentation must not rediscover providers.
- **`AgentThread.speedMode` is optional thread-scoped speed state.** Normalize `nil`, empty, and unknown to `AgentSpeedMode.standard`; persist `.fast` only when provider status reports speed support, and coerce a stale Fast back to Standard in the same save as provider and model normalization.
