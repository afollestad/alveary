import Foundation
import XCTest

@testable import Skep

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

    func testLoadCatalogFallsBackToBundledSnapshotWhenLiveFetchFails() async throws {
        let fixture = try SkillsServiceFixture()
        defer { fixture.cleanup() }

        let catalog = try await fixture.service.loadCatalog()

        XCTAssertEqual(catalog.map(\.id), ["code-review-general", "playwright-testing"])
        XCTAssertTrue(catalog.allSatisfy { $0.source == .catalog })
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

        XCTAssertEqual(first, second)
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

        let markdown = try await fixture.service.fetchSkillMd(skill: skill)

        XCTAssertEqual(markdown, skillMarkdown(id: "android-emulator", description: "Manage Android emulators"))
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
}

private struct SkillsServiceFixture {
    let rootDirectory: URL
    let baseDir: URL
    let claudeSkillsDirectory: URL
    let ampSkillsDirectory: URL
    let service: DefaultSkillsService

    init(createAmpParent: Bool = true) throws {
        rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        baseDir = rootDirectory.appendingPathComponent("agentskills", isDirectory: true)
        claudeSkillsDirectory = rootDirectory.appendingPathComponent(".claude/skills", isDirectory: true)
        ampSkillsDirectory = rootDirectory.appendingPathComponent(".amp/skills", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: nil)
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
