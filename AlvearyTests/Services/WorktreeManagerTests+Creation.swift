import Foundation
import XCTest

@testable import Alveary

@MainActor
extension WorktreeManagerTests {
    func testCreateUsesSetupScriptEnvironmentAndCollisionSuffix() async throws {
        let fixture = try await makeSetupScriptCreationFixture()

        let info = try await fixture.manager.create(
            projectPath: fixture.projectURL.path,
            threadName: "Fix auth bug",
            baseRef: "main",
            remoteName: "origin"
        )

        XCTAssertTrue(info.branch.hasPrefix("af-"))
        XCTAssertTrue(info.branch.hasSuffix("-2"))
        XCTAssertEqual(info.headOID, WorktreeTestObjectID.worktree)
        XCTAssertEqual(URL(fileURLWithPath: info.path).lastPathComponent, String(info.branch.dropFirst("af-".count)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: info.path).appendingPathComponent(".env.local").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: info.path).appendingPathComponent("config/dev.json").path))

        let invocations = await fixture.shell.invocations
        assertSetupInvocations(invocations, branch: info.branch, worktreePath: info.path)
        assertLifecycleEnvironment(
            invocations[5].environment,
            threadName: "Fix auth bug",
            branch: info.branch,
            projectPath: fixture.projectURL.path,
            worktreePath: info.path
        )
    }

    func testCreateRollsBackWorktreeAndBranchWhenSetupFails() async throws {
        let fixture = try await makeFailedSetupCreationFixture()

        do {
            _ = try await fixture.manager.create(
                projectPath: fixture.projectURL.path,
                threadName: "Broken setup",
                baseRef: "main",
                remoteName: "origin"
            )
            XCTFail("Expected setup failure")
        } catch let error as GitError {
            XCTAssertEqual(error, .commandFailed("Setup script failed: boom"))
        }

        let invocations = await fixture.shell.invocations
        XCTAssertEqual(Array(invocations[6].args.prefix(3)), ["worktree", "remove", "--force"])
        XCTAssertEqual(
            invocations[7].args,
            ["update-ref", "-d", "--", "refs/heads/\(fixture.expectedBranch)", WorktreeTestObjectID.worktree]
        )
    }
}
