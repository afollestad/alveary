import XCTest

@testable import Alveary

final class GlobalAgentInstructionsServiceTests: XCTestCase {
    private var homeDirectory: URL!
    private var service: DefaultGlobalAgentInstructionsService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("instructions-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        service = DefaultGlobalAgentInstructionsService(
            agentRegistry: ServiceTestAgentRegistry(
                agents: [
                    makeAgent(id: "claude", instructionsPath: "~/.claude/CLAUDE.md"),
                    makeAgent(id: "codex", instructionsPath: "~/.codex/AGENTS.md"),
                    makeAgent(id: "amp", instructionsPath: nil)
                ]
            ),
            homeDirectory: homeDirectory
        )
    }

    override func tearDownWithError() throws {
        if let homeDirectory {
            try? FileManager.default.removeItem(at: homeDirectory)
        }
        homeDirectory = nil
        service = nil
        try super.tearDownWithError()
    }

    // MARK: - Shared file

    func testLoadSharedReturnsEmptyStringWhenFileAbsent() async throws {
        let content = try await service.loadShared()
        XCTAssertEqual(content, "")
    }

    func testSaveSharedCreatesParentDirectoryAndRoundTrips() async throws {
        try await service.saveShared("# Shared\n")
        let loaded = try await service.loadShared()
        XCTAssertEqual(loaded, "# Shared\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedURL.path))
    }

    // MARK: - Link states

    func testLinkStatesOmitsAgentsWithoutInstructionsPath() async {
        let states = await service.linkStates()
        XCTAssertNil(states["amp"])
        XCTAssertEqual(Set(states.keys), ["claude", "codex"])
    }

    func testMissingFileReportsAbsent() async {
        let states = await service.linkStates()
        XCTAssertEqual(states["claude"], .absent(path: claudeURL.path))
    }

    func testEmptyFileReportsAbsent() async throws {
        try writeClaudeFile("   \n")
        let states = await service.linkStates()
        XCTAssertEqual(states["claude"], .absent(path: claudeURL.path))
    }

    func testRealContentReportsHasOwnFile() async throws {
        try writeClaudeFile("# Mine\n")
        let states = await service.linkStates()
        XCTAssertEqual(states["claude"], .hasOwnFile(path: claudeURL.path))
    }

    func testSymlinkToSharedReportsLinked() async throws {
        try await service.saveShared("# Shared\n")
        try FileManager.default.createDirectory(
            at: claudeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: claudeURL, withDestinationURL: sharedURL)

        let states = await service.linkStates()
        XCTAssertEqual(states["claude"], .linked)
    }

    func testSymlinkElsewhereReportsResolvedTarget() async throws {
        let otherURL = homeDirectory.appendingPathComponent("other/AGENTS.md")
        try FileManager.default.createDirectory(
            at: otherURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "other".write(to: otherURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: claudeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: claudeURL, withDestinationURL: otherURL)

        let states = await service.linkStates()
        guard case .linkedElsewhere(let target)? = states["claude"] else {
            XCTFail("Expected linkedElsewhere, got \(String(describing: states["claude"]))")
            return
        }
        XCTAssertTrue(target.hasSuffix("/other/AGENTS.md"))
    }

    // MARK: - Copy into shared

    func testCopyIntoSharedAppendsUnderMarkerAndLeavesOriginalUntouched() async throws {
        try await service.saveShared("# Shared\n")
        try writeClaudeFile("# Mine\n")

        try await service.copyIntoShared(agentID: "claude")

        let shared = try await service.loadShared()
        XCTAssertTrue(shared.hasPrefix("# Shared"))
        XCTAssertTrue(shared.contains("<!-- migrated from ~/.claude/CLAUDE.md -->"))
        XCTAssertTrue(shared.contains("# Mine"))
        XCTAssertEqual(try String(contentsOf: claudeURL, encoding: .utf8), "# Mine\n")
    }

    func testCopyIntoSharedOnLinkedAgentDoesNotDuplicateSharedContent() async throws {
        try writeClaudeFile("# Mine\n")
        try await service.link(agentID: "claude", copyingContents: true)
        let sharedAfterLink = try await service.loadShared()

        try await service.copyIntoShared(agentID: "claude")

        let sharedAfterCopy = try await service.loadShared()
        XCTAssertEqual(sharedAfterLink, sharedAfterCopy)
    }

    func testCopyIntoSharedForUnsupportedAgentThrows() async {
        do {
            try await service.copyIntoShared(agentID: "amp")
            XCTFail("Expected unsupportedAgent error")
        } catch let error as GlobalAgentInstructionsError {
            XCTAssertEqual(error, .unsupportedAgent("amp"))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    // MARK: - Link

    func testLinkCopyingContentsBacksUpMigratesAndSymlinks() async throws {
        try writeClaudeFile("# Mine\n")

        try await service.link(agentID: "claude", copyingContents: true)

        let backupURL = claudeURL.appendingPathExtension("backup")
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), "# Mine\n")

        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: claudeURL.path)
        XCTAssertEqual(
            URL(fileURLWithPath: destination).standardizedFileURL.resolvingSymlinksInPath().path,
            sharedURL.standardizedFileURL.resolvingSymlinksInPath().path
        )

        let shared = try await service.loadShared()
        XCTAssertTrue(shared.contains("# Mine"))
        XCTAssertTrue(shared.contains("<!-- migrated from ~/.claude/CLAUDE.md -->"))

        let states = await service.linkStates()
        XCTAssertEqual(states["claude"], .linked)
    }

    func testLinkWithoutCopyingStillProducesBackup() async throws {
        try writeClaudeFile("# Mine\n")

        try await service.link(agentID: "claude", copyingContents: false)

        let backupURL = claudeURL.appendingPathExtension("backup")
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), "# Mine\n")
        let shared = try await service.loadShared()
        XCTAssertFalse(shared.contains("# Mine"))
    }

    func testRelinkingLinkedAgentIsNoOp() async throws {
        try writeClaudeFile("# Mine\n")
        try await service.link(agentID: "claude", copyingContents: true)
        let sharedAfterFirstLink = try await service.loadShared()

        try await service.link(agentID: "claude", copyingContents: true)

        let sharedAfterSecondLink = try await service.loadShared()
        XCTAssertEqual(sharedAfterFirstLink, sharedAfterSecondLink)
        // The backup still holds the original, not a copy of the symlink.
        let backupURL = claudeURL.appendingPathExtension("backup")
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), "# Mine\n")
    }

    func testLinkReplacesPreExistingBackup() async throws {
        try writeClaudeFile("# New\n")
        let backupURL = claudeURL.appendingPathExtension("backup")
        try "# Old backup\n".write(to: backupURL, atomically: true, encoding: .utf8)

        try await service.link(agentID: "claude", copyingContents: false)

        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), "# New\n")
    }

    func testLinkCreatesMissingSharedFileSoSymlinkResolves() async throws {
        try writeClaudeFile("# Mine\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedURL.path))

        try await service.link(agentID: "claude", copyingContents: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedURL.path))
        // fileExists resolves symlinks, so this fails if the link dangles.
        XCTAssertTrue(FileManager.default.fileExists(atPath: claudeURL.path))
    }

    func testLinkLeavesForeignSymlinkAlone() async throws {
        let otherURL = homeDirectory.appendingPathComponent("other/AGENTS.md")
        try FileManager.default.createDirectory(
            at: otherURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "other".write(to: otherURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: claudeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: claudeURL, withDestinationURL: otherURL)

        try await service.link(agentID: "claude", copyingContents: true)

        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: claudeURL.path)
        XCTAssertEqual(destination, otherURL.path)
        let states = await service.linkStates()
        guard case .linkedElsewhere? = states["claude"] else {
            XCTFail("Expected linkedElsewhere, got \(String(describing: states["claude"]))")
            return
        }
    }

    func testLinkWhenAgentFileAbsentCreatesSymlinkWithoutBackup() async throws {
        try await service.link(agentID: "codex", copyingContents: false)

        let codexURL = homeDirectory.appendingPathComponent(".codex/AGENTS.md")
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: codexURL.path)
        XCTAssertEqual(
            URL(fileURLWithPath: destination).standardizedFileURL.resolvingSymlinksInPath().path,
            sharedURL.standardizedFileURL.resolvingSymlinksInPath().path
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: codexURL.appendingPathExtension("backup").path)
        )
    }
}

private extension GlobalAgentInstructionsServiceTests {
    var sharedURL: URL {
        homeDirectory.appendingPathComponent(".agents/AGENTS.md")
    }

    var claudeURL: URL {
        homeDirectory.appendingPathComponent(".claude/CLAUDE.md")
    }

    func writeClaudeFile(_ content: String) throws {
        try FileManager.default.createDirectory(
            at: claudeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: claudeURL, atomically: true, encoding: .utf8)
    }

    func makeAgent(id: String, instructionsPath: String?) -> AgentDefinition {
        AgentDefinition(
            id: id,
            name: id.capitalized,
            installCommand: nil,
            signInCommand: nil,
            docUrl: nil,
            provider: nil,
            skillsDirectory: nil,
            instructionsPath: instructionsPath,
            mcp: nil
        )
    }
}
