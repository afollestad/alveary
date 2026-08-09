#if DEBUG
import Foundation

/// Serves `DemoCatalogs` instead of the user's real skill directories.
///
/// This is a safety requirement, not decoration: `DefaultSkillsService` hardcodes `~/.agentskills`
/// and syncs installs into `~/.claude/skills` and `~/.codex/skills` through `AgentRegistry`, none
/// of which consult `AppStorageProfile` — so an isolated demo profile running the real service
/// would still write to the user's actual agent configuration.
///
/// State is mutable so Install and Uninstall visibly do something; a button that no-ops reads as
/// a bug in a live demo build.
actor DemoSkillsService: SkillsService {
    private var installed = DemoCatalogs.installedSkills
    private var catalog = DemoCatalogs.catalogSkills
    private var skillsSh = DemoCatalogs.skillsShSkills

    func loadInstalled() async throws -> [Skill] {
        installed
    }

    func loadCatalog() async throws -> [Skill] {
        catalog
    }

    @discardableResult
    func refreshCatalog() async throws -> [Skill] {
        catalog
    }

    func searchSkillsSh(query: String) async throws -> [Skill] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return skillsSh
        }
        return skillsSh.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.description.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func fetchSkillMd(skill: Skill) async throws -> SkillMarkdownDocument {
        SkillMarkdownDocument(
            markdown: DemoCatalogs.skillMarkdown(for: skill),
            baseURL: nil,
            browserURL: skill.githubURL
        )
    }

    // Deliberately non-throwing: a thrown error surfaces as an inline banner on the screen.

    func install(_ skill: Skill) async throws {
        guard !installed.contains(where: { $0.id == skill.id }) else {
            return
        }
        var copy = skill
        copy.isInstalled = true
        copy.syncedAgentIDs = ["claude", "codex"]
        installed.append(copy)
        markInstalled(true, id: skill.id)
    }

    func uninstall(_ skill: Skill) async throws {
        installed.removeAll { $0.id == skill.id }
        markInstalled(false, id: skill.id)
    }

    func create(name: String, description: String, instructions: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }
        installed.append(
            Skill(
                id: "demo-created-\(trimmedName)",
                name: trimmedName,
                description: description,
                version: "1.0.0",
                source: .local,
                isInstalled: true,
                syncedAgentIDs: ["claude", "codex"],
                owner: nil,
                repo: nil,
                sourceUrl: nil,
                installs: nil
            )
        )
    }

    private func markInstalled(_ isInstalled: Bool, id: String) {
        for index in catalog.indices where catalog[index].id == id {
            catalog[index].isInstalled = isInstalled
        }
        for index in skillsSh.indices where skillsSh[index].id == id {
            skillsSh[index].isInstalled = isInstalled
        }
    }
}
#endif
