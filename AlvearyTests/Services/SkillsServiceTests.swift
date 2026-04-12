import Foundation
import XCTest

@testable import Alveary

final class SkillsServiceTests: XCTestCase {
    override func tearDown() {
        ServiceURLProtocolStub.reset()
        super.tearDown()
    }

    func testLoadInstalledDeduplicatesAcrossCentralAndAgentDirectories() async throws {
        let fixture = try SkillsServiceFixture()
        defer { fixture.cleanup() }
        try fixture.createSkill(id: "code-review", description: "Review code")
        try fixture.linkSkill(id: "code-review", toAgent: "claude")

        let installed = try await fixture.service.loadInstalled()

        XCTAssertEqual(installed.count, 1)
        XCTAssertEqual(installed.first?.id, "code-review")
        XCTAssertEqual(installed.first?.syncedAgentIDs, ["claude"])
        XCTAssertTrue(installed.first?.isInstalled == true)
    }

    func testLoadInstalledFindsSharedAgentSkillsWithoutClaudeSymlink() async throws {
        let fixture = try SkillsServiceFixture()
        defer { fixture.cleanup() }
        try fixture.createSharedSkill(id: "go-link", description: "Resolve internal go links")

        let installed = try await fixture.service.loadInstalled()

        XCTAssertEqual(installed.map(\.id), ["go-link"])
        XCTAssertTrue(installed.first?.isInstalled == true)
    }

    func testLoadCatalogFallsBackToBundledSnapshotWhenLiveFetchFails() async throws {
        let fixture = try SkillsServiceFixture()
        defer { fixture.cleanup() }

        let catalog = try await fixture.service.loadCatalog()

        XCTAssertEqual(catalog.map(\.id), ["code-review-general", "playwright-testing"])
        XCTAssertTrue(catalog.allSatisfy { $0.source == .catalog })
        XCTAssertEqual(
            catalog.first?.githubURL,
            URL(string: "https://github.com/anthropics/skills/blob/main/skills/code-review-general/SKILL.md")
        )
    }

    func testSkillGitHubURLPrefersSourceURLOverRepoRoot() {
        let skill = Skill(
            id: "code-review-general",
            name: "code-review-general",
            description: "Review code",
            version: nil,
            source: .catalog,
            isInstalled: false,
            syncedAgentIDs: [],
            owner: "anthropics",
            repo: "skills",
            sourceUrl: "https://github.com/anthropics/skills/tree/main/skills/code-review-general",
            installs: nil
        )

        XCTAssertEqual(
            skill.githubURL,
            URL(string: "https://github.com/anthropics/skills/tree/main/skills/code-review-general")
        )
    }

    func testSkillGitHubURLFallsBackToRepoRootWithoutSourceURL() {
        let skill = Skill(
            id: "playwright-cli",
            name: "playwright-cli",
            description: "Browser automation",
            version: nil,
            source: .skillsSh,
            isInstalled: false,
            syncedAgentIDs: [],
            owner: "example",
            repo: "community-skills",
            sourceUrl: nil,
            installs: nil
        )

        XCTAssertEqual(skill.githubURL, URL(string: "https://github.com/example/community-skills"))
    }

    func testFetchSkillMdUsesDefaultBranchAndCachesTreeLookup() async throws {
        let fixture = try SkillsServiceFixture()
        defer { fixture.cleanup() }

        let repoURL = "https://api.github.com/repos/example/community-skills"
        let treeURL = "https://api.github.com/repos/example/community-skills/git/trees/release%2Fv1?recursive=1"
        let guessedRawURL = "https://raw.githubusercontent.com/example/community-skills/release%2Fv1/skills/playwright-cli/SKILL.md"
        let treeRawURL = "https://raw.githubusercontent.com/example/community-skills/release%2Fv1/tools/browser/SKILL.md"

        ServiceURLProtocolStub.configure(
            responses: [
                repoURL: [
                    .init(statusCode: 200, data: Data("{\"default_branch\":\"release/v1\"}".utf8))
                ],
                treeURL: [
                    .init(statusCode: 200, data: Data("{\"tree\":[{\"path\":\"tools/browser/SKILL.md\",\"type\":\"blob\"}]}".utf8))
                ],
                guessedRawURL: [
                    .init(statusCode: 404, data: Data()),
                    .init(statusCode: 404, data: Data())
                ],
                treeRawURL: [
                    .init(statusCode: 200, data: Data(skillMarkdown(id: "playwright-cli", description: "Browser automation").utf8)),
                    .init(statusCode: 200, data: Data(skillMarkdown(id: "playwright-cli", description: "Browser automation").utf8))
                ]
            ]
        )

        let skill = Skill(
            id: "playwright-cli",
            name: "playwright-cli",
            description: "Browser automation",
            version: nil,
            source: .skillsSh,
            isInstalled: false,
            syncedAgentIDs: [],
            owner: "example",
            repo: "community-skills",
            sourceUrl: nil,
            installs: 12
        )

        let first = try await fixture.service.fetchSkillMd(skill: skill)
        let second = try await fixture.service.fetchSkillMd(skill: skill)
        let requests = ServiceURLProtocolStub.recordedRequests()

        XCTAssertEqual(first.markdown, second.markdown)
        XCTAssertEqual(first.baseURL, second.baseURL)
        XCTAssertEqual(
            first.browserURL,
            URL(string: "https://github.com/example/community-skills/blob/release%2Fv1/tools/browser/SKILL.md")
        )
        XCTAssertEqual(requests.filter { $0 == repoURL }.count, 1)
        XCTAssertEqual(requests.filter { $0 == treeURL }.count, 1)
        XCTAssertEqual(requests.filter { $0 == treeRawURL }.count, 2)
    }

    func testFetchSkillMdReadsInstalledLocalSkillWithoutRemoteSource() async throws {
        let fixture = try SkillsServiceFixture()
        defer { fixture.cleanup() }
        try fixture.createSkill(id: "android-emulator", description: "Manage Android emulators")

        let skill = Skill(
            id: "android-emulator",
            name: "android-emulator",
            description: "Manage Android emulators",
            version: "1.0.0",
            source: .local,
            isInstalled: true,
            syncedAgentIDs: ["claude"],
            owner: nil,
            repo: nil,
            sourceUrl: nil,
            installs: nil
        )

        let document = try await fixture.service.fetchSkillMd(skill: skill)

        XCTAssertEqual(document.markdown, skillMarkdown(id: "android-emulator", description: "Manage Android emulators"))
        XCTAssertEqual(document.baseURL, fixture.baseDir.appendingPathComponent("android-emulator", isDirectory: true))
        XCTAssertNil(document.browserURL)
        XCTAssertTrue(ServiceURLProtocolStub.recordedRequests().isEmpty)
    }

    func testCreateRejectsInvalidNames() async throws {
        let fixture = try SkillsServiceFixture()
        defer { fixture.cleanup() }

        do {
            try await fixture.service.create(name: "Invalid Name", description: "desc", instructions: "body")
            XCTFail("Expected create to throw")
        } catch let error as SkillsError {
            XCTAssertEqual(error, .invalidName("Invalid Name"))
        }
    }

    func testCreateEscapesQuotesAndSyncsOnlyDetectedAgents() async throws {
        let fixture = try SkillsServiceFixture(createAmpParent: false)
        defer { fixture.cleanup() }

        try await fixture.service.create(
            name: "quoted-skill",
            description: "A \"quoted\" skill",
            instructions: "Run \"quoted\" instructions"
        )

        let skillFile = fixture.baseDir.appendingPathComponent("quoted-skill/SKILL.md")
        let content = try String(contentsOf: skillFile, encoding: .utf8)
        let claudeLink = fixture.claudeSkillsDirectory.appendingPathComponent("quoted-skill")
        let ampLink = fixture.ampSkillsDirectory.appendingPathComponent("quoted-skill")

        XCTAssertTrue(content.contains("description: \"A \\\"quoted\\\" skill\""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: claudeLink.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ampLink.path))
    }

    func testParseFrontmatterStripsQuotesAndPreservesBareVersion() {
        let markdown = "---\nname: \"my-skill\"\ndescription: 'Testing'\nversion: 1.0.0\n---\n# Body\n"

        let result = DefaultSkillsService.parseFrontmatter(markdown)

        XCTAssertEqual(result.name, "my-skill")
        XCTAssertEqual(result.description, "Testing")
        XCTAssertEqual(result.version, "1.0.0")
    }

    func testParseFrontmatterReadsLiteralBlockDescriptions() {
        let markdown = """
        ---
        name: cash
        description: |
          Use the Cash CLI for common Cash App iOS & Android developer tasks. Use when building,
          testing, linting, running, or managing modules in cash-ios or cash-android repositories.
          Auto-detects platform and shows relevant commands.
        version: 0.4.0
        ---
        # Cash CLI
        """

        let result = DefaultSkillsService.parseFrontmatter(markdown)

        XCTAssertEqual(result.name, "cash")
        XCTAssertEqual(
            result.description,
            "Use the Cash CLI for common Cash App iOS & Android developer tasks. Use when building,\n" +
                "testing, linting, running, or managing modules in cash-ios or cash-android repositories.\n" +
                "Auto-detects platform and shows relevant commands."
        )
        XCTAssertEqual(result.version, "0.4.0")
    }

    func testMarkdownBodyStripsFrontmatterAndLeadingBlankLines() {
        let markdown = """
        ---
        name: "my-skill"
        description: "Testing"
        version: 1.0.0
        ---

        # Body

        Use this skill.
        """

        let result = DefaultSkillsService.markdownBody(from: markdown)

        XCTAssertEqual(result, "# Body\n\nUse this skill.")
    }
}

private struct SkillsServiceFixture {
    let rootDirectory: URL
    let baseDir: URL
    let sharedSkillsDirectory: URL
    let claudeSkillsDirectory: URL
    let ampSkillsDirectory: URL
    let service: DefaultSkillsService

    init(createAmpParent: Bool = true) throws {
        rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        baseDir = rootDirectory.appendingPathComponent("agentskills", isDirectory: true)
        sharedSkillsDirectory = rootDirectory.appendingPathComponent(".agents/skills", isDirectory: true)
        claudeSkillsDirectory = rootDirectory.appendingPathComponent(".claude/skills", isDirectory: true)
        ampSkillsDirectory = rootDirectory.appendingPathComponent(".amp/skills", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: sharedSkillsDirectory, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(
            at: claudeSkillsDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        if createAmpParent {
            try FileManager.default.createDirectory(
                at: ampSkillsDirectory.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let agentRegistry = ServiceTestAgentRegistry(
            agents: [
                AgentDefinition(
                    id: "claude",
                    name: "Claude Code",
                    installCommand: nil,
                    docUrl: nil,
                    provider: nil,
                    skillsDirectory: claudeSkillsDirectory.path,
                    mcp: nil
                ),
                AgentDefinition(
                    id: "amp",
                    name: "Amp",
                    installCommand: nil,
                    docUrl: nil,
                    provider: nil,
                    skillsDirectory: ampSkillsDirectory.path,
                    mcp: nil
                )
            ]
        )

        service = DefaultSkillsService(
            baseDir: baseDir,
            session: ServiceURLProtocolStub.makeSession(),
            bundle: Bundle(for: SkillsServiceTests.self),
            sharedSkillsDirectories: [sharedSkillsDirectory.path],
            agentRegistry: agentRegistry
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    func createSkill(id: String, description: String) throws {
        let directory = baseDir.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        try skillMarkdown(id: id, description: description).write(
            to: directory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    func createSharedSkill(id: String, description: String) throws {
        let directory = sharedSkillsDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        try skillMarkdown(id: id, description: description).write(
            to: directory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    func linkSkill(id: String, toAgent agentID: String) throws {
        let skillsDirectory: URL = switch agentID {
        case "claude":
            claudeSkillsDirectory
        case "amp":
            ampSkillsDirectory
        default:
            claudeSkillsDirectory
        }

        try FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createSymbolicLink(
            at: skillsDirectory.appendingPathComponent(id),
            withDestinationURL: baseDir.appendingPathComponent(id)
        )
    }
}

private func skillMarkdown(id: String, description: String) -> String {
    [
        "---",
        "name: \"\(id)\"",
        "description: \"\(description)\"",
        "version: 1.0.0",
        "---",
        "",
        "# \(id)"
    ].joined(separator: "\n")
}
