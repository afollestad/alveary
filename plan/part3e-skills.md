# Part 3e: Skills

Skills service, skills catalog, skills.sh integration. Continues from Part 3d.

## Skills

Reference: [Claude Code Skills](https://code.claude.com/docs/en/skills)

Skills are reusable, modular extensions that can be installed and synced across multiple AI agents. They're structured as `SKILL.md` files with YAML frontmatter and markdown content. Selecting "Skills" in the left sidebar opens the skills management screen in the middle pane.

### Storage

- **Central location**: `~/.agentskills/{skill-id}/SKILL.md`
- **Catalog cache**: `~/.agentskills/.skep/catalog-index.json`

Skills are symlinked into each installed agent's skills directory so all agents can use them. Each agent has a different native directory name:

| Agent | Skill symlink path | Notes |
|---|---|---|
| Claude | `~/.claude/skills/{skill-id}` | |
| Codex | `~/.agents/skills/{skill-id}` | OpenAI's current user-level skill directory |
| Cursor | `~/.cursor/skills/{skill-id}` | |
| Gemini | `~/.gemini/skills/{skill-id}` | |
| Amp | `~/.amp/skills/{skill-id}` | |
| OpenCode | `~/.config/opencode/skills/{skill-id}` | XDG config path |
| Hermes | `~/.hermes/skills/{skill-id}` | |
| Roo Code | `~/.roo/skills/{skill-id}` | |
| Mistral Vibe | `~/.vibe/skills/{skill-id}` | |
| Pi | `~/.pi/agent/skills/{skill-id}` | Nested under `agent/` |

The concrete skill paths come from the shared `AgentRegistry` (`AgentDefinition.skillsDirectory`), not from a second hardcoded list inside `SkillsService`. Syncing only targets registry entries whose skill-root parent directories already exist on disk (for example `~/.claude/`, `~/.agents/`, `~/.cursor/`, `~/.gemini/`, `~/.amp/`). The app checks for directory existence before creating symlinks.

Externally-installed skill discovery scans the same `AgentRegistry` skill directories used for sync (`~/.claude/skills/`, `~/.agents/skills/`, `~/.cursor/skills/`, `~/.gemini/skills/`, `~/.amp/skills/`, `~/.config/opencode/skills/`, `~/.hermes/skills/`, `~/.roo/skills/`, `~/.vibe/skills/`, `~/.pi/agent/skills/`) plus the legacy `~/.agent/skills/` path.

The central copy under `~/.agentskills/` is the source of truth for whether a skill is installed at all. Per-agent sync is tracked separately on each `Skill` via `syncedAgentIDs`, so the UI can distinguish "installed locally but not linked anywhere yet" from "installed and synced to Claude/Amp/etc.".

### Skill Sources

1. **Installed** -- skills already on the system in `~/.agentskills/`.
2. **Catalog** -- curated skills from the validated Anthropic GitHub repo, fetched and cached.
3. **skills.sh** -- community skill registry, searched via public API (debounced, query >= 2 chars).

### skills.sh API

Public search API. No authentication required.

**Endpoint**: `GET https://skills.sh/api/search?q=<query>`

**Request**:
- Method: `GET`
- Headers: `User-Agent: Skep` (custom, for identification)
- Query parameter: `q` — URL-encoded search string (minimum 2 characters, enforced both client-side and server-side — server returns 400 for shorter queries)
- Timeout: 15 seconds

**Response** (`200 OK`):
```json
{
  "query": "playwright",
  "searchType": "fuzzy",
  "skills": [
    {
      "id": "microsoft/playwright-cli/playwright-cli",
      "skillId": "playwright-cli",
      "name": "playwright-cli",
      "installs": 12512,
      "source": "microsoft/playwright-cli"
    }
  ],
  "count": 100,
  "duration_ms": 29
}
```

Key fields per skill:
- `skillId` — canonical identifier (used as the skill ID in the app, not `id`)
- `name` — display name
- `source` — GitHub `owner/repo` string (split at first `/` to get owner and repo)
- `installs` — install count (useful for sorting/ranking)

**Client-side debouncing**: 400ms after the last keystroke before sending the request. Use a counter or task cancellation to discard stale responses (if the user types more before the response arrives, discard the old response).

### Resolving skills.sh Results to SKILL.md

A skills.sh result provides `owner/repo` but not the path to `SKILL.md` within the repo. Resolution flow:

1. **Resolve the repo's default branch** once (cache per `owner/repo` for a short TTL), because community repos are not guaranteed to use `main`.

2. **Try common raw paths first** against that default branch (cheap, no Trees API quota):
   - `skills/{skillId}/SKILL.md`
   - `SKILL.md`
   - `{skillId}/SKILL.md`
   - `.claude/skills/{skillId}/SKILL.md`

3. **If the raw-path guesses fail, fetch the repo tree** via GitHub API (unauthenticated):
   ```
   GET https://api.github.com/repos/{owner}/{repo}/git/trees/{default-branch}?recursive=1
   ```

4. **Find all `SKILL.md` files** in the tree response (filter `tree` array for entries where `type == "blob"` and `path` ends with `SKILL.md`).

5. **Match by skill ID** (for multi-skill repos):
   - If exactly 1 `SKILL.md` exists, use it.
   - If multiple exist, check if any parent directory name matches the `skillId`.
   - If no directory match, fetch each `SKILL.md` and compare frontmatter `name` against the `skillId`.
   - If nothing matches, use the first `SKILL.md` as a best-effort fallback.

6. **Fetch the raw content**:
   ```
   GET https://raw.githubusercontent.com/{owner}/{repo}/{default-branch}/{path}
   ```

7. **Last resort** (if all fetches fail): generate a stub `SKILL.md` from the skill's `name` and `description` so the install still succeeds.

**Rate limiting**: the unauthenticated GitHub API has a 60 requests/hour limit. The default-branch lookup and Trees API call (`api.github.com`) count against that budget; raw content fetches (`raw.githubusercontent.com`) are CDN-served and don't. With the current Anthropic-only curated source, a cold catalog refresh uses up to 2 API calls (repo metadata + tree), then hits caches on later refreshes. If later curated sources are added, budget the same 2-call cold path per repo. Mitigations: (1) cache repo metadata and tree responses per `owner/repo` for 10 minutes, (2) try the fallback path list before the Trees API for skills.sh results.

### Catalog Fetching (Anthropic)

Curated skills are fetched from the validated public Anthropic repo:
- **Anthropic**: `anthropics/skills` — the official Agent Skills repo. Skills live under a `skills/` directory organized by category, each with a `SKILL.md`.

The fetch follows the same pattern as skills.sh resolution: Trees API → find `SKILL.md` files → fetch raw content → parse frontmatter. Do not add a second curated source until its public repo and `SKILL.md` layout are validated the same way.

### Catalog Caching

- **Cache location**: `~/.agentskills/.skep/catalog-index.json`
- **Cache format**:
  ```json
  {
    "version": 1,
    "lastUpdated": "2026-04-05T12:00:00Z",
    "skills": [
      {
        "id": "playwright-testing",
        "name": "Playwright Testing",
        "description": "Browser automation for testing",
        "source": "catalog",
        "owner": "vercel-labs",
        "repo": "agent-skills",
        "sourceUrl": "https://github.com/vercel-labs/agent-skills/tree/main/skills/playwright-testing"
      }
    ]
  }
  ```
- **No time-based TTL** — the cache is used indefinitely until explicitly refreshed by the user (via the Refresh button). A `version` field allows cache invalidation on app updates.
- **Refresh triggers**: user clicks "Refresh" in the Skills screen, or after install/uninstall (invalidates in-memory cache, next read reloads from disk).
- **Fallback chain** on cold start: in-memory cache → disk cache (if version matches) → live fetch → bundled fallback (compiled into the app for offline first-run when no cache is available and the live fetch fails).
- **skills.sh results are never cached to disk** — they exist only in the view model's `searchResults` and are ephemeral.

### Source Priority and Deduplication

Skills from multiple sources are merged with these rules:
1. **Catalog skills** (currently Anthropic only) are loaded first. If multiple curated sources are added later, keep the same dedupe rule: first occurrence wins.
2. **Installed state merge**: after loading the catalog, scan local directories (`~/.agentskills/` + agent skill dirs). For each catalog skill, check if it exists locally → set `isInstalled = true`. Any locally-installed skills NOT in the catalog are appended with `source: .local`.
3. **skills.sh search results** are filtered to exclude IDs already visible in Installed or Catalog. This prevents duplicate cards when a result is already installed locally or already present in the curated catalog.

**UI sections** (in order):
1. Installed skills (any source, `isInstalled == true`)
2. Recommended (catalog skills where `isInstalled == false`)
3. skills.sh search results (only when searching, de-duped against installed + catalog)

### Skills Screen UI

Shown in the middle pane when "Skills" is selected in the left sidebar.

```
                                    ↻ Refresh  🔍 Search skills   [+ New skill]
 Skills
 Give your agents superpowers.

   Installed
   ┌───────────────────────────────────┐ ┌───────────────────────────────────┐
   │ 🎨 Analyze IDE Freezes    proj-a │ │ 📱 Android Emulator       proj-b │
   │    Analyze Android Studio   ✓    │ │    Use when starting, stop...  ✓ │
   │    IDE freezes...                │ │                                  │
   ├───────────────────────────────────┤ ├───────────────────────────────────┤
   │ 🔧 Code Review General    proj-c │ │ 🚀 Building Skills       proj-d │
   │    Use when reviewing,      ✓    │ │    Scaffold, create, upd...   ✓ │
   │    evaluating...                 │ │                                  │
   └───────────────────────────────────┘ └───────────────────────────────────┘

   Recommended
   ┌───────────────────────────────────┐ ┌───────────────────────────────────┐
   │ 📦 Fix Flaky Tests               │ │ ⚡ Swift Testing Migration       │
   │    Use when fixing a flaky   [+] │ │    Migrate XCTest tests to  [+] │
   │    test, re-enabling...          │ │    Swift Testing framework...    │
   └───────────────────────────────────┘ └───────────────────────────────────┘
```

**Grid**: 2-column grid of skill cards, each showing:
- Icon (GitHub avatar for repo-backed skills, generic local badge otherwise)
- Display name and source project
- Description (truncated to 2 lines) when available. `skills.sh` search results fall back to source repo + install count because the search API does not return descriptions.
- Checkmark if installed, "+" button if not

**Sections** (in order):
1. Installed skills
2. Recommended (catalog skills not yet installed)
3. skills.sh search results (when searching)

### Actions

- **Install**: downloads `SKILL.md` from GitHub → writes to `~/.agentskills/{skill-id}/SKILL.md` → symlinks to all detected agents.
- **Uninstall**: removes skill directory and symlinks from agents.
- **Create**: opens the new skill form (see **Creating a New Skill** below).
- **View detail**: clicking a skill card opens a detail modal:

```
┌─────────────────────────────────────────────── ✕ ─┐
│                                                    │
│  🔧 Code Review General  Skill                   │
│  Use when reviewing, evaluating, critiquing,       │
│  auditing, inspecting code changes, diffs,         │
│  pull requests, or implementations.                │
│                                                    │
│  ─────────────────────────────────────────────     │
│                                                    │
│  (Full SKILL.md content rendered as markdown:      │
│   instructions, current state checks,              │
│   scripts location, quick commands, etc.)          │
│                                                    │
│  Quick Commands                                    │
│  ┌────────────────────────────────────────────┐    │
│  │ bash                                    📋 │    │
│  │ bash ~/.agentskills/code-review/run.sh     │    │
│  └────────────────────────────────────────────┘    │
│                                                    │
│  [ Uninstall ]                                    │
└────────────────────────────────────────────────────┘
```

**Skill detail modal — installed skill:**
- **Header**: skill icon, display name, and "Skill" badge.
- **Description**: the skill's description from frontmatter.
- **Body**: full SKILL.md content rendered as markdown (headings, lists, inline code, code blocks). Scrollable.
- **Quick commands**: if the skill defines scripts or commands, show them in copyable code blocks.
- **Footer**: "Uninstall" button (red, with confirmation). Show lightweight synced-agent chips derived from `syncedAgentIDs`; if the skill is installed centrally but not linked into any detected agent, show a small "Not synced to any installed agent" warning instead of pretending the install is globally active. Per-agent enable/disable toggles and chat-launch shortcuts are deferred until the plan has explicit routing and persisted enable-state ownership for them.

**Skill detail modal — not installed (catalog or skills.sh result):**

```
┌─────────────────────────────────────────────── ✕ ─┐
│                                                    │
│  📦 playwright-cli          12,512 installs        │
│  microsoft/playwright-cli                          │
│                                                    │
│  ─────────────────────────────────────────────     │
│                                                    │
│  (SKILL.md content rendered as markdown,           │
│   fetched on modal open via fetchSkillMd())        │
│                                                    │
│  # Playwright CLI                                  │
│                                                    │
│  Use Playwright for browser automation,            │
│  testing, and web scraping...                      │
│                                                    │
│  [ View on GitHub ]                  [ Install ]   │
└────────────────────────────────────────────────────┘
```

- **Header**: skill icon (or GitHub avatar fallback), display name, install count badge, source repo (`owner/repo`).
- **Body**: SKILL.md content fetched via `fetchSkillMd(skill:)` on modal open. Shows a loading spinner while fetching. If the repo content cannot be resolved, `fetchSkillMd()` synthesizes a minimal markdown preview from the search metadata so the modal still renders usable install content instead of a blank/error state.
- **Footer**: "View on GitHub" link (opens `https://github.com/{owner}/{repo}` in browser) and "Install" button. After install succeeds, the modal transitions to the installed variant (installed badge persists, footer switches to "Uninstall").

**Refresh catalog**: re-fetches the validated curated catalog source plus any future re-validated curated sources, then updates cache.

### Creating a New Skill

The "+ New Skill" button in the toolbar opens a creation form:

- **Name**: text input, validated as kebab-case (lowercase, hyphens, 1-64 chars). Becomes the skill ID and directory name.
- **Description**: required text input. One-line summary of what the skill does.
- **Instructions**: optional textarea for the markdown body -- the actual instructions the agent will follow.

On submit, the app:
1. Generates YAML frontmatter from the name and description.
2. Writes `~/.agentskills/{name}/SKILL.md` with the frontmatter + instructions body.
3. Symlinks to all detected agents (same as install).

The created skill appears immediately in the "Installed" section of the skills grid.

### SKILL.md Format

```markdown
---
name: my-skill
description: A skill that does something useful
version: 1.0.0
---

# My Skill

Instructions for the agent...
```

### Skill and SkillsService

```swift
struct Skill: Identifiable, Sendable {  // Skep/Services/Skills/Skill.swift
    let id: String               // Kebab-case identifier (skillId from API, or directory name for local)
    let name: String             // Display name from frontmatter or API
    let description: String
    let version: String?
    let source: Source           // Where the skill was discovered
    var isInstalled: Bool
    var syncedAgentIDs: [String] // Installed agent targets whose skill dir currently links this skill
    let owner: String?           // GitHub owner (for catalog and skills.sh skills)
    let repo: String?            // GitHub repo (for catalog and skills.sh skills)
    let sourceUrl: String?       // Direct URL to the skill in its source repo
    let installs: Int?           // Install count from skills.sh (nil for catalog/local)

    enum Source: Sendable { case local, catalog, skillsSh }
}

/// Actor-isolated because the concrete implementation has mutable caches
/// (`catalogCache`, `treeCache`) that would race under concurrent access
/// (e.g. `loadCatalog()` while `refreshCatalog()` is running, or concurrent
/// `fetchSkillMd()` calls updating the tree cache).
protocol SkillsService: Actor {  // Skep/Services/Skills/SkillsService.swift
    func loadInstalled() async throws -> [Skill]
    func loadCatalog() async throws -> [Skill]
    func searchSkillsSh(query: String) async throws -> [Skill]
    func fetchSkillMd(skill: Skill) async throws -> String  // Resolve and fetch SKILL.md content
    func install(_ skill: Skill) async throws
    func uninstall(_ skill: Skill) async throws
    func create(name: String, description: String, instructions: String) async throws
    @discardableResult
    func refreshCatalog() async throws -> [Skill]
}
```

The concrete `DefaultSkillsService` implementation, `SkillsError`, and unit tests are in [Part 3f: Skills Service](part3f-skills-service.md).

### SkillsViewModel

```swift
@MainActor @Observable
class SkillsViewModel {  // Skep/ViewModels/SkillsViewModel.swift
    private let skillsService: SkillsService
    private(set) var installed: [Skill] = []
    private(set) var catalog: [Skill] = []
    private(set) var searchResults: [Skill] = []
    var searchQuery: String = "" {
        didSet { search() }
    }
    private var searchTask: Task<Void, Never>?

    /// Initial screen load: populate Installed first, then Catalog/Recommended.
    func load() async { ... }

    /// Debounced search — cancels any in-flight search and waits 400ms after the
    /// last keystroke before hitting the skills.sh API. Stale responses are discarded
    /// because Task cancellation propagates through the await chain.
    func search() {
        searchTask?.cancel()
        let query = searchQuery
        guard query.count >= 2 else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let results = (try? await skillsService.searchSkillsSh(query: query)) ?? []
            guard !Task.isCancelled else { return }
            let visibleIds = Set(installed.map(\.id)).union(catalog.map(\.id))
            searchResults = results.filter { !visibleIds.contains($0.id) }
        }
    }

    func install(_ skill: Skill) async throws { ... }
    func uninstall(_ skill: Skill) async throws { ... }
    func create(name: String, description: String, instructions: String) async throws { ... }
    func refreshCatalog() async { ... }
}
```

**Used by**: `SkillsScreen` (middle pane when "Skills" selected in sidebar). The VM is created lazily on first visit and retained at the `ContentView` level so that navigating away preserves the loaded catalog and search query. `refreshCatalog()` can be called on subsequent visits to update stale data without resetting the VM-backed state.

Minimal screen signature:

```swift
struct SkillsScreen: View {  // Skep/Views/Skills/SkillsScreen.swift
    let viewModel: SkillsViewModel
}
```

`SkillsScreen` owns the initial `.task` that calls `await viewModel.load()` on first appearance. `MiddlePane` only creates/caches the VM; it does not silently trigger background loads during DI composition.

**Unit tests for SkillsViewModel** (inject `MockSkillsService`): cover all public methods with standard happy-path and error tests. Non-obvious:
- `load()` populates `installed` before the catalog-backed sections so the introductory state does not briefly show an incorrect full-empty fallback
- `search()` debounces 400ms and discards stale responses when the query changes mid-flight
- `search()` filters results against both `installed` and `catalog` IDs to prevent duplicate cards

**Snapshot tests for SkillsScreen:** cover grid (installed + catalog), the no-installed intro-card state with catalog still visible, the true full-screen empty fallback (catalog unavailable), skill detail modal, and create skill form.
