# OpenCode harness integration

## Scope

Alveary integrates OpenCode through AgentCLIKit's native adapter. It supports ordinary coding and review conversations with native session persistence, tool approvals, steering, subagents, and compaction. Its supported features and limitations are listed below.

The compatibility target is [OpenCode v1.18.31](https://github.com/anomalyco/opencode/releases/tag/v1.18.31), using its stable V1 HTTP/SSE protocol. AgentCLIKit accepts stable versions `>=1.18.31` and `<2.0.0`; the compatibility fixtures target `1.18.31`. Prereleases, older binaries, unknown versions, and V2 are rejected.

OpenCode's rolling documentation and default development branch can describe newer or experimental APIs. The adapter is based on the [tagged OpenAPI contract](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/sdk/openapi.json), rather than assuming that a documented V2 endpoint is available through the selected V1 runtime.

## Capability matrix

The matrix describes the adapter contract, including explicitly gated limitations.

| Capability | Implementation and boundary |
| --- | --- |
| Coding and ordinary review conversations | Native model/tool loop through the OpenCode server. Ordinary review tasks can use OpenCode. |
| Streaming output, reasoning, tools | Stable tool/message IDs, native text deltas and completed snapshots, existing Alveary transcript presentations. |
| Resume | Native session ID and history; restored history seeds deduplication rather than appearing again as new output. |
| Fork and workspace move | Native fork, followed by V1 `move-session` for a different destination directory. The newly forked session moves; its source remains intact. Alveary still owns Git worktree creation. |
| Steering and cancellation | Submit a prompt to the active native loop; observe acceptance before clearing the host's steering state. Abort through the native session endpoint. Steering takes effect at a native loop boundary, not by rewriting an in-flight model request. |
| Manual and automatic compaction | Native summarize and automatic overflow recovery. Manual compaction resolves the session's actual model when OpenCode default is selected. Started/completed/failed events update one transcript note; summaries do not become ordinary assistant replies. |
| Permissions | Configured, Ask, and Full access. These are native **tool permission policies**, not OS sandbox modes. Request IDs remain distinct from tool-call IDs. |
| Claude Automatic approvals and custom hooks | Unsupported. OpenCode uses its own permission policies and explicit approval reuse; Claude's automatic approval semantics and custom hook contracts are not translated. |
| Questions | Native question replies/rejections, multiple questions and selections, and closed choices (`custom: false`) without a fabricated freeform answer. |
| Subagents | Ordinary native `task` children, attributed child output, and completion. Experimental background agents and advanced per-agent control remain disabled. |
| Tasks and plan mode | Native todo snapshots and build/plan agent selection reuse existing app presentation. |
| Models and reasoning | Provider-qualified model IDs and discovered model variants. Available reasoning options come from the selected model. |
| Images and app shots | Native image attachments only for an explicitly selected model advertising image input. App shots include hidden AX context and a native image; no Codex-specific app-shot marker is sent. |
| Usage and context | Input plus cache-read plus cache-write tokens form context usage. Cached tokens are additive, unlike Codex cached-input accounting. Reasoning is included in output usage. Child context does not replace the root context or trigger its handoff. |
| MCP, instructions, skills | SDK-owned discovery/configuration and a process-scoped Alveary host MCP endpoint. Existing instruction/skill surfaces use the OpenCode definitions. |
| Extra launch arguments | Unsupported. Use native OpenCode configuration; saved extra arguments must be cleared explicitly before launch. |
| Archive and delete | Native archive/delete accompany app-local lifecycle actions. V1.18.31 cannot clear native archive state; app-local restore remains available and does not promise native unarchive. |
| Scheduled work and session handoff | Alveary owns scheduling, persistence, recovery, and between-turn handoff. These reuse supported ordinary conversation operations; they are not native OpenCode goal execution. |
| Native goals and token budgets | Unsupported; controls and execution paths are gated. No prompt-based imitation of native goal state or budgeting. |
| Fast mode | Unsupported and gated. Model reasoning variants do not imply fast mode. |
| Sandbox equivalence | Unsupported. Local tools run with the process's filesystem/network access. Workspace permissions and Git worktrees do not provide a Codex-style OS sandbox. |
| Isolated utility prompts and collective-review workers | Native read-only one-shot runs in disposable profiles. Select a concrete provider-qualified model; reasoning variants are optional. Unsupported connection methods fail preflight without substituting another model or harness. |
| Raw native transcript viewer | Gated until an OpenCode transcript-reader integration exists. Normal persisted Alveary transcripts remain available. |

Child usage currently remains available in SDK events but is excluded from Alveary's root token rows. This prevents incorrect context percentages and premature handoff; it also means those rows are not a complete aggregate of separately billed child work.

## Architecture

### AgentCLIKit

`OpenCodeHarnessAdapter` owns one server generation per runtime process token. `OpenCodeHTTPServerTransport` launches the selected executable on an ephemeral loopback port with a generated password. HTTP requests carry the generation's working directory. Stream parsing respects SSE byte framing, bounds buffered data, and declines redirects. Cancelled startup and shutdown terminate and observe the child process; a process registry also closes owned discovery servers during normal host exit. Turn cancellation aborts native work while retaining persistent sessions.

`OpenCodeClient` owns bootstrap, native session identity, pending prompts, permission/question resolution, and root turn completion. A terminal root event requires authoritative completion, not just a finished tool or assistant step. Recoverable context overflow proceeds into native compaction. Failed server recovery retires the runtime generation and its unfinished children/compactions; an explicit continuation can resume the persisted session without replaying interrupted work. Side-effecting requests are not blindly retried after ambiguous network failures.

`OpenCodeEventTranslator` filters unrelated directory-wide events, discovers child-session ancestry, and reconciles SSE with message snapshots. It emits stable IDs and avoids duplicating text, tools, usage, and compaction lifecycles after reconnect. V1 deltas have no offset: when a snapshot overlaps an existing part, authoritative part snapshots are used rather than guessing which buffered deltas already appear in its text.

Discovery, model metadata, compatibility checks, and OpenCode configuration live in the SDK. The Alveary host MCP endpoint is injected into ordinary conversation configuration, preserving user configuration and permission rule order.

Isolated workers use a separate prepared one-shot contract. Each invocation has private configuration, authentication, temporary storage, and a session database, removed after its process terminates. The environment is replaced, and only the selected provider connection is copied. Native read, glob, and grep are allowed; write tools, shell execution, MCP, project configuration, custom tools, plugins, and subagents are disabled. External provider SDK packages and managed configuration are rejected. These are native tool restrictions, not an OS sandbox.

Worker connections support configured API keys and selected provider environment credentials. OAuth is limited to OpenAI with an access token valid beyond the bounded run, and GitHub Copilot's native bearer credential. Other OAuth methods, executable extensions, and automatic credential lookup in the original home directory are unavailable in isolated runs. Expiring OpenAI authentication requires refreshing it in a normal OpenCode session before retrying; isolated workers never refresh the user's rotating credentials. Normal conversations retain native authentication behavior.

### Alveary

The app enrolls OpenCode in onboarding, discovery, settings, dependency injection, authentication/setup, and MCP/instruction/skill configuration. `HarnessFeaturePolicy` keeps UI controls and execution admission aligned; model-dependent image support requires discovered model metadata.

Harnesses settings reports the last completed check. Use **Refresh** at the top to recheck the installed CLI and provider setup after an external upgrade or configuration change. Returning to the app with this page visible also rechecks enabled harnesses that are unavailable or need setup; ready harnesses do not trigger repeated probes on app switches. Failed checks remain gated until a fresh check succeeds, and an older result cannot replace a newer successful retry.

Independent harness checks run concurrently. Project discovery reuses fresh global installation and model metadata, refreshes project trust, and overlays OpenCode's directory-specific catalog. Concurrent requests share probes, and explicit refresh invalidates both caches before publishing replacement results; superseded probes cannot overwrite newer results.

Task discovery uses the actual working directory for OpenCode provider/model options, setup readiness, and diagnostics. `ProjectScopedOpenCodeDiscoveryService` uses the SDK's native discovery probe and keeps a bounded, coalesced project cache; settings/wake invalidation clears it. Native project trust is not required and does not impose global provider readiness. Host-created project tasks and feedback tasks validate their selections against the known source directory before creation; task composers and execution admission use the resulting workspace. Global settings, isolated workers, utility selection, and task seeds without a known workspace use the global catalog.

Review-team and utility selectors share the one-shot capability policy. Models without reasoning variants remain selectable. Inherited or saved selections stay visible when invalid, with a repair message; they never silently switch harnesses. Review workers revalidate their read-only packet after native preparation before launching model work.

Scheduled editors also discover models and reasoning variants in the selected execution directory, using the source directory before a new workspace exists. Reused schedules retain their existing workspace's catalog. Pending or stale discovery responses never rewrite saved model choices.

The event bridge reuses existing transcript rows for native tools, questions, task lists, subagents, and compaction. OpenCode's timestamp-based placeholder session titles do not replace task names; meaningful native titles still update normally. Native permissions use their real interaction IDs. Both approval batching and transcript grouping avoid inventing permission requests from OpenCode tool IDs. Host tools match the exact `alveary_host_<tool>` spelling as well as existing Codex and Claude forms.

Context percentages and automatic handoff share `ContextTokenAccounting`. Count-free OpenCode completion records preserve turn boundaries without replacing the last measured context. Automatic handoff evaluates the latest root measurement at successful turn completion; successful native compaction requires a new measurement before handoff can trigger. The displayed context remains the last measured request until OpenCode reports fresh usage. App-shot transport stays separate from visible user text and queued/transcript attachments remain in the existing attachment store.

## Compatibility testing

The live fixture uses disposable HOME/XDG/config directories, Git worktrees, and a local fake model. It does not authenticate with a user's provider, modify their OpenCode configuration, or install/upgrade their CLI. It proves adapter/protocol behavior, not every provider's model behavior.

To run the live adapter checks from the AgentCLIKit checkout, set only the executable path. The test support starts the bundled Python provider fixture automatically; a provider URL or provider credentials are not required:

```sh
AGENTCLIKIT_OPENCODE_BINARY=/absolute/path/to/opencode-1.18.31 \
  swift test --filter OpenCodeLiveAdapterTests
```

App tests cover capability gating, restored and inherited unsupported settings, global OpenCode defaults, project-scoped discovery, cached-token handoff accounting, native question selections, approval identities, app-shot capture and delivery admission, host-created tasks, scheduling, fork settings, ambiguous submission errors, and isolated-worker selection and cleanup. The separate real-executable SDK tests establish the native protocol behavior; the app tests establish its integration and admission policy. Neither claims compatibility with every external model provider.

## Alternatives assessed

These are integration assessments as of **September 15, 2026**, not additional harness implementations. None was verified to satisfy the strict union of the existing Codex and Claude runtime contracts.

| Candidate | Source baseline | Assessment |
| --- | --- | --- |
| Pi coding agent | [Pi v0.85.1 README](https://github.com/earendil-works/pi/blob/v0.85.1/packages/coding-agent/README.md) | Small RPC/SDK integration surface with persisted sessions, branching, and compaction. It explicitly distinguishes steering queued for the next interruption point from follow-up messages queued until current work finishes. Its core intentionally omits native MCP, subagents, permission prompts, and plan mode. Extensions could supply those, but Alveary would own substantially more runtime behavior. Native persistent goal/token-budget parity was not established. |
| Gemini CLI | [ACP session](https://github.com/google-gemini/gemini-cli/blob/v0.60.0/packages/cli/src/acp/acpSession.ts), [ACP dispatcher](https://github.com/google-gemini/gemini-cli/blob/v0.60.0/packages/cli/src/acp/acpRpcDispatcher.ts), v0.60.0 | The reviewed ACP implementation aborts the previous pending prompt when a new prompt arrives. That differs from preserving an active turn and queuing steering within it. The exposed ACP surface supports creation/loading, prompt/cancel, modes, permissions, and media, but lacks the required native fork, persistent-goal, and rich-question contracts. Broader CLI features do not remove those integration gaps. |
| GitHub Copilot SDK/CLI | [SDK compatibility](https://docs.github.com/en/copilot/how-tos/copilot-sdk/troubleshooting/compatibility), [CLI reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference), rolling docs checked September 15 | Our strongest candidate for a future prototype: broad SDK session/tool/MCP integration, including immediate message steering. Autopilot objectives can use an AI-credit cap, which is a different budget unit from tokens; no Codex Fast-mode equivalent was verified in the reviewed surface. CLI goal and experimental sandbox features still need executable SDK-contract checks before claiming parity. These documentation links are dated baselines, not pinned executable revisions. |
| OpenHands Software Agent SDK | [v1.48.0 architecture](https://github.com/OpenHands/software-agent-sdk/blob/v1.48.0/README.md), [goal controller](https://github.com/OpenHands/software-agent-sdk/blob/v1.48.0/openhands-sdk/openhands/sdk/conversation/goal/controller.py), [goal-loop tests](https://github.com/OpenHands/software-agent-sdk/blob/v1.48.0/tests/agent_server/test_goal_loop.py) | A richer agent platform: Python runtime/Agent Server plus TypeScript/REST clients, local or container workspaces, MCP, and confirmation policies. Its native goals use a judge and an iteration cap; a normal user message stops a running goal loop. These semantics differ from persistent token-budget goals. Integration also adds server/workspace packaging and a separate lifecycle bridge, making it a larger project than the selected OpenCode adapter. |

OpenCode was selected for the verified native V1 conversation feature set and the amount of existing Alveary behavior it can reuse. Closing any remaining gap requires a concrete runtime contract and acceptance tests before enabling its capability.
