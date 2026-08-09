#if DEBUG
import Foundation

/// Canned Skills and MCP catalogs. Both screens are otherwise backed by services that read and
/// *write* the user's real `~/.agentskills`, `~/.claude.json`, and `~/.codex/config.toml`, so
/// these exist to make the demo swaps possible as much as to fill the screenshots.
enum DemoCatalogs {
    static let installedSkills: [Skill] = [
        Skill(
            id: "demo-release-notes",
            name: "release-notes",
            description: "Draft user-facing release notes from merged pull requests.",
            argumentHint: "[since-tag]",
            version: "1.4.0",
            source: .local,
            isInstalled: true,
            syncedAgentIDs: ["claude", "codex"],
            owner: "demo",
            repo: "skills",
            sourceUrl: nil,
            installs: nil
        ),
        Skill(
            id: "demo-screenshot-pass",
            name: "screenshot-pass",
            description: "Regenerate marketing screenshots after a UI change lands.",
            argumentHint: "[screen]",
            version: "0.9.2",
            source: .catalog,
            isInstalled: true,
            syncedAgentIDs: ["claude"],
            owner: "demo",
            repo: "skills",
            sourceUrl: nil,
            installs: nil
        ),
        Skill(
            id: "demo-migration-audit",
            name: "migration-audit",
            description: "Check a schema migration against the rows already in production.",
            version: "2.0.1",
            source: .skillsSh,
            isInstalled: true,
            syncedAgentIDs: ["codex"],
            owner: "octo",
            repo: "migration-audit",
            sourceUrl: "https://skills.sh/octo/migration-audit",
            installs: nil
        )
    ]

    static let catalogSkills: [Skill] = [
        Skill(
            id: "demo-changelog-roundup",
            name: "changelog-roundup",
            description: "Compile a customer-facing changelog for a date range.",
            version: "1.1.0",
            source: .catalog,
            isInstalled: false,
            syncedAgentIDs: [],
            owner: "demo",
            repo: "skills",
            sourceUrl: nil,
            installs: 1_284
        ),
        Skill(
            id: "demo-dependency-audit",
            name: "dependency-audit",
            description: "Flag outdated and vulnerable packages, newest advisories first.",
            version: "3.2.0",
            source: .catalog,
            isInstalled: false,
            syncedAgentIDs: [],
            owner: "demo",
            repo: "skills",
            sourceUrl: nil,
            installs: 4_907
        )
    ]

    static let skillsShSkills: [Skill] = [
        Skill(
            id: "demo-flaky-hunter",
            name: "flaky-hunter",
            description: "Re-run a failing test under seeds and isolate the flake.",
            argumentHint: "<test-name>",
            version: "0.5.0",
            source: .skillsSh,
            isInstalled: false,
            syncedAgentIDs: [],
            owner: "octo",
            repo: "flaky-hunter",
            sourceUrl: "https://skills.sh/octo/flaky-hunter",
            installs: 812
        ),
        Skill(
            id: "demo-perf-budget",
            name: "perf-budget",
            description: "Compare a build's frame timings against the committed budget.",
            version: "1.0.3",
            source: .skillsSh,
            isInstalled: false,
            syncedAgentIDs: [],
            owner: "octo",
            repo: "perf-budget",
            sourceUrl: "https://skills.sh/octo/perf-budget",
            installs: 356
        )
    ]

    /// The details pane renders this through the real markdown renderer, so it is the visual
    /// payoff of the Skills screen. No `---` frontmatter: `SkillsViewModel` strips it anyway.
    static func skillMarkdown(for skill: Skill) -> String {
        """
        # \(skill.name)

        \(skill.description)

        ## When to use this

        Reach for `/\(skill.name)` when the work is repetitive enough to have a shape but specific
        enough that a template would be wrong. The skill collects the context first, then proposes
        a plan before touching anything.

        ## Steps

        1. Gather the inputs — branch, range, and any pinned configuration.
        2. Summarize what changed, grouped by theme rather than by commit.
        3. Draft the output and show it for review.
        4. Apply only after the draft is confirmed.

        ## Notes

        - Runs read-only until the final step.
        - Skips anything already covered by an earlier run.
        - Reports what it deliberately left out.
        """
    }

    static let mcpServers: [MCPServer] = [
        MCPServer(
            name: "linear",
            transport: .http,
            command: nil,
            args: nil,
            url: "https://mcp.linear.app/sse",
            headers: ["Authorization": "Bearer ***"],
            env: nil,
            providers: ["claude", "codex"]
        ),
        MCPServer(
            name: "postgres",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-postgres", "postgresql://localhost/waypoint"],
            url: nil,
            headers: nil,
            env: ["PGSSLMODE": "disable"],
            providers: ["claude"]
        ),
        MCPServer(
            name: "figma",
            transport: .http,
            command: nil,
            args: nil,
            url: "https://mcp.figma.com/mcp",
            headers: nil,
            env: nil,
            providers: ["codex"]
        )
    ]

    static let recommendedMCPServers: [RecommendedMCPServer] = [
        RecommendedMCPServer(
            template: MCPServer(
                name: "sentry",
                transport: .http,
                command: nil,
                args: nil,
                url: "https://mcp.sentry.dev/mcp",
                headers: nil,
                env: nil,
                providers: []
            ),
            description: "Read issues, releases, and stack traces from Sentry.",
            headerPrompts: ["Authorization"]
        ),
        RecommendedMCPServer(
            template: MCPServer(
                name: "playwright",
                transport: .stdio,
                command: "npx",
                args: ["-y", "@playwright/mcp@latest"],
                url: nil,
                headers: nil,
                env: nil,
                providers: []
            ),
            description: "Drive a real browser to reproduce and verify UI bugs.",
            headerPrompts: []
        )
    ]

    /// Must never be empty: the Add/Edit pane's Save button gates on a non-empty agent selection,
    /// so an empty list would render a permanently disabled form.
    static let mcpAgents: [MCPAgentAvailability] = [
        MCPAgentAvailability(agentId: "claude", name: "Claude Code", supportedTransports: [.stdio, .http]),
        MCPAgentAvailability(agentId: "codex", name: "Codex", supportedTransports: [.stdio, .http])
    ]
}
#endif
