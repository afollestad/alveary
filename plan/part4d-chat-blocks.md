# Part 4d: Chat Blocks and Tool Rendering

Working blocks, tool rendering, sub-agent blocks, prompts, task lists, thinking, and markdown rendering. Composer input and interaction details continue in the [Chat Input and Interactions supplement](supplement-chat-input-and-interactions.md). Continues from Part 4c.

### Chat Component Type Map

Part 4c shows these components in `ChatView`, but the plan should still name their minimal shapes explicitly so Phase 6 does not have to infer them from a switch statement alone:

```swift
struct UserBubble: View {  // Skep/Views/Chat/UserBubble.swift
    let text: String
}

struct AssistantBubble: View {  // Skep/Views/Chat/AssistantBubble.swift
    let markdown: String
}

struct QueuedMessageBubble: View {  // Skep/Views/Chat/QueuedMessageBubble.swift
    let text: String
    let showsStagedContext: Bool
    let showsRetry: Bool
    let isDismissDisabled: Bool
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void
}

struct WorkingBlock: View {  // Skep/Views/Chat/WorkingBlock.swift
    let tools: [ToolEntry]
}

struct SubAgentBlock: View {  // Skep/Views/Chat/SubAgentBlock.swift
    let agents: [SubAgentEntry]
}

struct TaskListBlock: View {  // Skep/Views/Chat/TaskListBlock.swift
    let tasks: [TaskEntry]
}

struct ThinkingBlock: View {  // Skep/Views/Chat/ThinkingBlock.swift
    let text: String
}

struct ErrorBanner: View {  // Skep/Views/Chat/ErrorBanner.swift
    let message: String
}
```

`PromptBlock` has a fuller signature later in this file; `ChatInputField` lives in the [Chat Input and Interactions supplement](supplement-chat-input-and-interactions.md) because its callback/state contract is broader than the passive rendering components above.

### Working Blocks (Completed Tool Use)

After the agent finishes a turn, the live working area becomes a static **working block** in the conversation history.

**Collapsed (default):**
```
┌─ Working ────────────────────────────────────┐
│ ▸ Used 4 tools, 1 file edit                  │
└──────────────────────────────────────────────┘
```

The summary line counts tools and highlights edits (e.g. "4 tools, 2 file edits"). Click or press ▸ to expand.

**Expanded:**
```
┌─ Working ────────────────────────────────────┐
│ ▾ Used 4 tools, 1 file edit                  │
│                                              │
│  ✓  Read `auth.swift`                        │
│  ✓  Read `login.swift`                       │
│  ✓  Bash  `git log --oneline -5`             │
│     └ a1b2c3d Fix auth bug                   │
│  ✓  Edit `auth.swift`                        │
└──────────────────────────────────────────────┘
```

Each tool row shows a ✓ (success) or ✕ (error, red) status icon, the tool name, and the summary derived from `toolSummary()`. If `output` is non-empty, a **`└` result annotation** appears beneath — the last line of output, truncated to ~80 chars, in muted text. This is hidden for tools with very long output (e.g. Read with 200 lines) — only shown when the output is short (≤3 lines). Clicking a tool row expands it further to show full input/output:

**Tool row expanded:**
```
│  ✓  Read `auth.swift`                    ▾   │
│  ┌─ Input ─────────────────────────────────┐ │
│  │ file_path: /Users/you/src/auth.swift    │ │
│  │ limit: 50                               │ │
│  └─────────────────────────────────────────┘ │
│  ┌─ Output (42 lines) ────────────────────┐  │
│  │ 1  import Foundation                    │ │
│  │ 2  import CryptoKit                     │ │
│  │ 3                                       │ │
│  │ ...                              [Copy] │ │
│  └─────────────────────────────────────────┘ │
```

- **Input**: parsed from the tool's JSON input, displayed as key-value pairs. For Bash, shows the command in a code block.
- **Output**: stdout renders as the primary result. If structured stderr is present, render a separate muted/warning section below stdout instead of flattening both streams together. If `isImage` is true, render the result inline as an image (with a text fallback if decoding fails) rather than a code block. Show an "Interrupted" badge when `isInterrupted` is true. **Empty output**: if `output` is nil (tool still in progress) the output section is hidden — only the input and a pulsing indicator are shown. If `output` is an empty string and `isError == false`, show a muted "No output" placeholder unless `noOutputExpected` is true, in which case suppress the placeholder entirely.
- Tool descriptions are derived from the tool name and input JSON via `toolSummary()` (see [Part 2b: Event Grouping](part2b-event-grouping.md)).

**Read tool — syntax-highlighted file content:**

Read tool results get special-case rendering. The output is file content in `cat -n` format (line numbers + tab + content). The rendering pipeline:

0. **Guard**: if `output` is nil, empty, or whitespace-only, skip the Read-specific rendering entirely. Show "File is empty" in a muted label (for empty files) or hide the output section (for in-progress reads). Fall through to the generic tool rendering — don't attempt to strip line numbers or syntax-highlight an empty string.
1. **Parse** the tool input JSON for `file_path` to determine the file extension (e.g. `.swift`, `.ts`, `.py`).
2. **Strip line number prefixes** — the `cat -n` format (`   1\tcode here`) is for the CLI. The UI renders its own line number gutter, so the raw prefixes are stripped via a simple regex (`^\s*\d+\t`).
3. **Syntax highlight** the stripped content using Textual's Prism.js with the language inferred from the file extension. If the extension is unknown, render as plain monospace text.
4. **Collapsed by default** — Read results are often 50-200+ lines. Show the first 10 lines with a "Show N more lines" disclosure. The header shows the line count: `"Output (42 lines)"`.
5. **Line number gutter** — rendered by the UI (not from the raw content) using the `offset` from the tool input (if provided) as the starting line number. If `offset` is absent, start at 1.
6. **Copy button** copies the stripped content (no line numbers) to the clipboard.

```
│  ✓  Read `auth.swift:1-50`                  ▾   │
│  ┌─ auth.swift (50 lines) ───────────────────┐  │
│  │  1  import Foundation                     │  │
│  │  2  import CryptoKit                      │  │
│  │  3                                        │  │
│  │  4  class AuthManager {                   │  │
│  │  5      private let keychain: Keychain    │  │
│  │  ...                                      │  │
│  │  Show 45 more lines                [Copy] │  │
│  └───────────────────────────────────────────┘  │
```

Other tools (Bash, Grep, Glob) continue to use the generic scrollable code block rendering.

**Snapshot tests for Read tool rendering** — cover collapsed, expanded, and edge-case output states. Non-obvious:
- Read result with `offset` parameter (line numbers start at offset)
- Read result with nil output (in-progress — output section hidden, pulsing indicator shown)
- Tool with empty string output and `isError == false` (shows "No output" placeholder)
- Tool result with structured stderr and interrupted badge renders separate warning styling without corrupting stdout rendering
- Tool result with `isImage == true` renders inline media instead of a text code block

**Edit tool — inline diff rendering:**

Edit and Write tool rows get special-case rendering when expanded. Instead of raw JSON key-value pairs, they show a mini inline diff computed from the tool input:

```
│  ✓  Edit `PLAN.md`                       ▾   │
│  ┌─ Update(PLAN.md) ──────────────────────┐  │
│  │  Added 1 line, removed 1 line          │  │
│  │                                        │  │
│  │  78   | 5 | Turn State and Message ... │  │
│  │  79   | 6 | Activity Classification .. │  │
│  │  80   | 7 | Session Storage and Res .. │  │
│  │▐81-  | 8 | Event Grouping | `ChatI ..  │  │  ← red (removed)
│  │▐81+  | 8 | Event Grouping | `ChatI ..  │  │  ← green (added)
│  │  82   | 9 | Agent Process Spawning  .. │  │
│  │  83   | 10 | ClaudeAdapter + Turn L .. │  │
│  └────────────────────────────────────────┘  │
```

**How the diff is computed:**

The `Edit` tool input contains `old_string` and `new_string` — the exact text being replaced. The rendering pipeline:

1. **Parse** the tool input JSON for `file_path`, `old_string`, `new_string`.
2. **Split** both strings into lines. Lines present in `old_string` but not `new_string` are deletions (red). Lines in `new_string` but not `old_string` are additions (green). Shared leading/trailing lines are context (no highlight).
3. **Header**: `"Update({filename})"` with a change summary (`"Added N lines, removed M lines"`).
4. **Line numbers**: since the tool input doesn't include absolute line numbers, use relative numbering starting from 1 for the snippet. If the `tool_result` content includes line info (rare), prefer that.
5. **Render** using the same diff line styling as the right-pane diff viewer: red background for deletions with `−` gutter, green background for additions with `+` gutter, no highlight for context. Monospace font, syntax-highlighted via Textual if the file extension is known.
6. **Context collapsing**: if `old_string`/`new_string` have more than 6 shared leading or trailing lines, collapse the middle into "N unmodified lines" (same pattern as the diff viewer).

**Write tool**: for `Write` (new file creation), show the entire `content` as all-green additions since there's no `old_string`. Header: `"Create({filename})"` with `"Added N lines"`.

**Other tools**: Read, Bash, Grep, Glob, and all other tools continue to use the generic key-value input / scrollable output rendering.

**Snapshot tests for Edit tool inline diff** — cover single-line, multi-line, and Write-tool variants. Non-obvious:
- Edit with context collapsing (long unchanged regions)
- Write tool (all-green, "Create" header instead of "Update")

### Sub-Agent Blocks

When Claude Code spawns sub-agents (via the `Agent` tool), they are grouped into a **sub-agent block** in the chat UI. This mirrors the CLI's display (e.g. "4 agents finished (ctrl+o to expand)").

**Collapsed (default when all complete):**
```
┌─ 3 Explore agents finished ──────────────────┐
│ ▸ Find AuthManager usages · 5 tools · 12.3k tokens │
│   └ Done                                           │
│ ▸ Search for login flow · 8 tools · 18.7k tokens   │
│   └ Done                                           │
│ ▸ Check test coverage · 3 tools · 8.1k tokens      │
│   └ Done                                           │
└──────────────────────────────────────────────┘
```

Each row shows the sub-agent's description (from the Agent tool input), tool use count, and token count (formatted with "k" suffix for thousands). Status appears as an indented line below the summary. The header groups by agent type when all agents share the same type (e.g. "3 Explore agents finished"); mixed types show "3 agents finished". When `task_progress` events arrive, the `statusDescription` replaces the static status and `lastToolName` shows the current tool. Token count and tool use count update live from `task_progress`.

**While running:** running agents show a pulsing ● indicator. Status, tool count, and token count update live from `task_progress` events. Header adapts: "Running 2 agents...", "1 of 3 agents running" (mixed), etc.

**Expanded (while running):** inner tool calls stream in live. Only the **last 3** are shown; older calls collapse into "+N more tool uses" (clickable to expand). Updates in real-time as new `tool_call` events arrive with a matching `parentToolUseId`.

**Expanded sub-agent (completed):** reveals inner tool calls (same ToolEntry rendering as a working block) and the final result text in a "Result" card. Inner tool rows are expandable to show full input/output.

**Implementation**: `SubAgentBlock` is a SwiftUI view that takes `[SubAgentEntry]`. Each entry is a `DisclosureGroup` with the summary as label and the inner tools + result as content. The header dynamically shows "N {type} agents running" / "N {type} agents finished" / "X of N {type} agents running" based on `isComplete` flags. When all agents share the same `agentType`, the type name is included in the header (e.g. "3 Explore agents finished"). When types are mixed, the type is omitted ("3 agents finished"). Token counts are formatted with "k" suffix for thousands (e.g. "82.6k tokens" for 82,600 tokens).

### Prompt Blocks (AskUserQuestion)

When the agent uses the `AskUserQuestion` tool, the CLI auto-denies it in `-p` mode (validated). The app intercepts the `tool_call` event, extracts the structured question/options input, and renders a native SwiftUI selection UI instead of showing the denial error. The user's selection is sent as the next user message.

**Interactive (unanswered):**
```
┌─ Agent is asking ───────────────────────────┐
│                                              │
│  ┌─ Framework ─────────────────────────────┐ │
│  │                                         │ │
│  │  Which framework would you like to use? │ │
│  │                                         │ │
│  │  ◉ Jest                                 │ │
│  │    Popular testing framework by         │ │
│  │    Facebook with built-in mocking       │ │
│  │                                         │ │
│  │  ○ Vitest                               │ │
│  │    Fast Vite-native testing framework   │ │
│  │    with Jest-compatible API             │ │
│  │                                         │ │
│  │  ○ Mocha                                │ │
│  │    Flexible testing framework with      │ │
│  │    extensive plugin ecosystem           │ │
│  │                                         │ │
│  └─────────────────────────────────────────┘ │
│                                              │
│                              [ Submit ]      │
└──────────────────────────────────────────────┘
```

**Layout:**
- **Header**: current provider display name if known (for example, "Claude is asking" in v1), otherwise the generic fallback "Agent is asking".
- **Question card**: rounded card with the `header` as a chip/tag label (e.g. "Framework"), the `question` text as the heading, and radio buttons (single select) or checkboxes (`multiSelect: true`) for each option.
- **Options**: each option shows the `label` in bold and `description` in muted text below. There is **no default selection** — the user must make an explicit choice. Radio buttons for single-select, checkboxes for multi-select.
- **Structured options only**: the UI mirrors the `options` array exactly and does **not** invent a synthetic "Other" field. If the agent wants free-form follow-up, it can ask in normal chat.
- **Submit button**: enabled only after every question has an explicit answer **and** the current agent turn is idle. While the turn is still finishing, keep the user's local selection but disable submit so the answer is not merely queued and prematurely persisted as answered.

**Answered (static — after submission):**
```
┌─ You chose ─────────────────────────────────┐
│  Which framework would you like to use?: Jest│
└──────────────────────────────────────────────┘
```

After submission, the prompt block collapses into a compact summary showing the question text and the selected answer. The optional `header` chip remains part of the interactive card UI only; it is not what gets persisted. That answered summary is also persisted back onto the original `AskUserQuestion` tool_call record (reusing `ConversationEventRecord.content` for this prompt-specific UI state), so successful saves rebuild as read-only prompts instead of resurrecting the unanswered controls. The durable user-facing conversation record still includes the emitted user message bubble. The answer is sent as a new user turn formatted as: `"For the question '<question text>': <selected label>"` (or multiple labels joined by ", " for multi-select).

Because that persistence write mutates an existing event row rather than appending a new one, `ConversationViewModel.answerPrompt()` patches the existing prompt block in place via `state.grouper.markPromptAnswered(promptId:summary:)` after a successful save. This prevents the long-lived `ConversationState.grouper` cache from holding an unanswered prompt snapshot across navigation/rebuild when `events.count` is unchanged, without forcing a full regroup of the chat history.

**Multiple questions**: if the `AskUserQuestion` tool includes multiple questions in the `questions` array, each is rendered as a separate card within the same prompt block. The submit button waits until all questions have a selection and the prompt-submit path is idle (no active turn, no outbound send reservation, no in-flight session reconfigure).

**Implementation**: `PromptBlock` is a SwiftUI view that takes an immutable `PromptEntry` value and an async `onSubmit` callback. Selection state is managed locally via `@State`, but the answered summary also comes from `prompt.submittedSummary` so the compact state survives rebuilds:

```swift
struct PromptBlock: View {  // Skep/Views/Chat/PromptBlock.swift
    let prompt: PromptEntry
    let isBusy: Bool  // true while prompt submission is temporarily blocked by turn activity, outbound reservation, or session reconfigure
    let onSubmit: ([(question: String, answer: String)]) async -> String?

    /// Local selection state (not on PromptEntry). The durable answered-state summary
    /// comes from `prompt.submittedSummary` on the persisted tool_call.
    @State private var selections: [Int: Set<String>] = [:]  // question index → selected labels (single-select uses 0/1 element)
    @State private var submittedSummary: String?

    // If `prompt.submittedSummary ?? submittedSummary` is non-nil, render the static
    // compact summary immediately. Otherwise show the selection UI. Radio buttons
    // (.radioGroup) for single-select, Toggle rows for multi-select. Build the
    // callback payload by walking `prompt.questions.enumerated()` in order and joining each
    // question's selected labels in option order. Submit enabled only when all
    // questions are answered and `isBusy == false`.
}
```

It uses SwiftUI `Picker` with `.radioGroup` style for single-select questions and `Toggle` rows for multi-select. Local selection state is keyed by question index, not question text, so repeated prompts like two identical "Continue?" questions do not collide. The submit callback receives an ordered array matching `prompt.questions`, preserving question order when multiple prompts are answered. For multi-select questions with multiple selections, labels are joined with `", "` (e.g. `"Jest, Vitest"`) in the same order they appear in the original option list. After a successful submit, the returned summary is stored in `submittedSummary` and the view switches to the compact summary rendering immediately; on rebuild, `prompt.submittedSummary` restores the same state when the persistence save succeeds. If the callback returns `nil` (send failed), the selection UI stays visible so the user can retry. While `isBusy` is true, the controls remain selectable but the submit button stays disabled with helper text such as `"Wait for the current send or agent turn to finish before sending your selection."`

`ConversationViewModel.answerPrompt()` reuses the pure `formatPromptAnswers()` and `promptSummary()` helpers documented in Part 2f so the agent-facing follow-up text and the compact persisted prompt summary stay consistent.

**Unit tests for prompt-answer formatting helpers** — cover single-question, multi-question, and multi-select formatting, including preserving input order for multiple questions.

**Snapshot tests for PromptBlock** — cover single-select, multi-select, answered, and multi-question states. Non-obvious:
- Submit button disabled when no selection made
- Submit button disabled while `isBusy == true` even when a valid selection already exists
- Submit button disabled during the outbound-reservation / reconfigure-only busy state even when no turn is actively streaming yet
- Answered prompt re-renders as the compact summary when `PromptEntry.submittedSummary` is populated from persisted history
- Multiple questions with identical `question` text keep independent local selections (index-keyed state, no collision)

---

### Task List Blocks

When the agent creates a task/todo list (via the `TodoWrite` tool), it's rendered as a live-updating checkbox list. Each `TodoWrite` call contains the **full** task list, so the UI replaces the entire block on each update.

```
┌─ Tasks ──────────────────────────────────────┐
│ ■ Step 9: Check missing types           ◐   │  ← in-progress (pulsing)
│ □ Step 10: Check markdown formatting         │  ← pending
│ □ Step 11: Check test coverage               │
│ □ Step 12: Check build order                 │
│ □ Step 13: Check validation section          │
│ ✓ Step 1: Check for stale content            │  ← completed (dimmed, strikethrough)
│ ✓ Step 2: Check for bugs                     │
│ ✓ Step 3: Check performance                  │
│ ✓ Step 4: Check lifecycle issues             │
│   ... +4 completed                           │  ← collapsed overflow
└──────────────────────────────────────────────┘
```

**Layout rules:**
- **In-progress tasks** (■) are shown first with a pulsing indicator and bold text. If `TaskEntry.activeForm` is present, render that present-continuous label in the live row (for example, "Checking if tests pass") instead of repeating the static task title.
- **Pending tasks** (□) are shown next in queue order.
- **Completed tasks** (✓) are shown last, dimmed with strikethrough. If more than 4 completed tasks exist, the overflow is collapsed into a "+N completed" summary that can be clicked to expand.
- The entire block updates in-place when a new `TodoWrite` event arrives — no new block is appended.

**Implementation**: `TaskListBlock` is a SwiftUI view that takes `[TaskEntry]`. It sorts tasks by status (in_progress → pending → completed), renders each with the appropriate icon and style, uses `task.activeForm ?? task.content` for live in-progress labeling, and collapses completed overflow. The view uses `withAnimation` for status transitions (pending → in_progress → completed).

**Snapshot tests for TaskListBlock** — cover mixed-state, all-pending, and all-completed variants. Non-obvious:
- All completed with collapse ("+N completed" overflow summary)
- In-progress task with `activeForm` renders the live spinner label instead of the static task text

### Thinking Blocks

Thinking blocks show the agent's reasoning process. They appear inline in the chat between tool calls or before an assistant message.

**Collapsed (default):**
```
┌─ Thinking ───────────────────────────────────┐
│ ▸ 💭 Let me analyze the auth module...       │
└──────────────────────────────────────────────┘
```

The collapsed state shows a thought bubble icon and the first line of the thinking text, truncated with ellipsis. Click to expand.

**Expanded:**
```
┌─ Thinking ───────────────────────────────────┐
│ ▾ 💭                                         │
│                                              │
│  Let me analyze the auth module to           │
│  understand the token validation flow.       │
│  The issue is likely in validateToken()      │
│  where expired tokens aren't being           │
│  rejected. I should check both the           │
│  expiry check and the refresh logic...       │
│                                              │
└──────────────────────────────────────────────┘
```

The expanded state shows the full thinking text in a muted/italic style with a subtle background to visually distinguish it from assistant messages. Thinking text is rendered as **plain text** (not markdown) since it's internal reasoning, not a formatted response.

**During streaming**: while the agent is still thinking, the thinking block shows a pulsing "Thinking..." indicator. Once the full `assistant` event arrives (thinking is a content block within the assistant message), the thinking text is persisted and the block becomes static, defaulting to collapsed.

**Thinking blocks are never removed** — they persist in the conversation history so the user can review the agent's reasoning at any time. They're just collapsed by default to avoid visual clutter.

### Markdown and Code Rendering

Assistant messages and user messages both support markdown formatting:

**Inline code** -- text surrounded by backticks (`` ` ``) renders with a monospace font and a subtle background, both in assistant messages and in the user's chat input field.

**Code blocks** -- fenced code blocks using triple backticks render with:
- Syntax highlighting based on the language tag (for example, `swift` or `python`)
- A distinct background color (darker than the chat background)
- A language label in the top corner
- A **Copy button** to copy the code block content to clipboard
- Line numbers (optional, toggleable)

Use **Textual** (`StructuredText`) for SwiftUI-native markdown rendering (paragraphs, lists, headings, links, bold/italic, code spans, code blocks) with built-in syntax highlighting via Prism.js (~55 languages). Textual's `StructuredText.HighlighterTheme` API controls colors for code blocks, including `diff` token types (`.inserted`/`.deleted` on `StructuredText.HighlighterTheme.TokenType`).

**Diff rendering** -- when the agent shows a file diff (via tool results or in the diff viewer), render with diff-specific highlighting (green for additions, red for deletions, grey for context lines). Approaches:
- **Textual** supports a `diff` language mode via Prism.js -- render unified diff text as a syntax-highlighted code block with red/green coloring via `.inserted`/`.deleted` token types. Simplest approach for diffs in chat tool results.
- **Custom diff view** -- for the right-pane diff viewer (staging/committing), parse `git diff` output into hunks and render with a custom SwiftUI view (colored line backgrounds, line numbers, file headers). More control but more code.
- **Custom `DiffParser`** (`Skep/DiffParser/DiffParser.swift`) -- parses unified diff format (`git diff` output) into structured models (`DiffFile`, `DiffHunk`, `DiffLine`). No external dependency needed since the format is well-specified.

### Message and Code Copying

- **Code blocks**: the Copy button on each code block copies the code content to `NSPasteboard`. This is the primary copy affordance.
- **Assistant message text**: right-click (context menu) on an assistant message offers "Copy Message" to copy the full markdown text. Text selection within messages should also work natively (SwiftUI `Text` supports selection on macOS).
- **User messages**: same context menu with "Copy Message".

---

Composer input API, autocomplete, queueing interactions, steering, scroll behavior, and chat-surface performance continue in the [Chat Input and Interactions supplement](supplement-chat-input-and-interactions.md).
