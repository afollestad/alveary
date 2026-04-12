import XCTest

@testable import Alveary

@MainActor
final class GitHubServiceTests: XCTestCase {
    func testListPRsMapsCIStatusesFromCheckRollup() async throws {
        let cli = MockGitHubCLIService()
        cli.result = ShellResult(
            stdout: """
            [
              {
                "number": 12,
                "title": "Fix auth",
                "url": "https://example.com/12",
                "state": "OPEN",
                "headRefName": "af/fix-auth",
                "statusCheckRollup": [
                  {"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SUCCESS"}
                ]
              },
              {
                "number": 13,
                "title": "Broken CI",
                "url": "https://example.com/13",
                "state": "OPEN",
                "headRefName": "af/broken",
                "statusCheckRollup": [
                  {"__typename": "StatusContext", "state": "FAILURE"}
                ]
              }
            ]
            """,
            stderr: "",
            exitCode: 0,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )
        let service = CLIGitHubService(ghCLI: cli)

        let pullRequests = try await service.listPRs(in: "/tmp/project")

        XCTAssertEqual(pullRequests.map(\.ciStatus), [.pass, .fail])
    }

    func testCheckRunStatusTreatsMissingConclusionAsPending() async throws {
        let cli = MockGitHubCLIService()
        cli.result = ShellResult(
            stdout: """
            {
              "statusCheckRollup": [
                {"__typename": "CheckRun", "status": "IN_PROGRESS", "conclusion": ""}
              ]
            }
            """,
            stderr: "",
            exitCode: 0,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )
        let service = CLIGitHubService(ghCLI: cli)

        let status = try await service.checkRunStatus(prNumber: 12, in: "/tmp/project")

        XCTAssertEqual(status, .pending)
    }
}

@MainActor
private final class MockGitHubCLIService: GitHubCLIService, @unchecked Sendable {
    var result = ShellResult(stdout: "", stderr: "", exitCode: 0, stdoutWasTruncated: false, stderrWasTruncated: false)

    func checkInstalled() async -> String? { nil }
    func isAuthenticated() async -> Bool { false }
    func authenticate() async throws -> GitHubDeviceCode { GitHubDeviceCode(code: "", verificationURL: URL(fileURLWithPath: "/")) }
    func awaitAuthentication() async throws -> Bool { false }
    func cancelAuthentication() {}
    func run(args: [String], in directory: String?) async throws -> ShellResult { result }
}
