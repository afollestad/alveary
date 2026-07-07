import XCTest

@testable import Alveary

final class GitHubCLIAppUpdateReleaseClientTests: XCTestCase {
    func testFetchesLatestReleaseWithGitHubCLI() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "gh version 2.89.0")))
        await shell.enqueue(.success(shellResult(stdout: "Logged in to github.com")))
        await shell.enqueue(.success(shellResult(stdout: "afollestad/alveary")))
        await shell.enqueue(.success(shellResult(stdoutData: try releaseJSON())))
        let client = GitHubCLIAppUpdateReleaseClient(shellRunner: shell)

        let result = await client.latestRelease()

        let release = try XCTUnwrap(result.installableRelease)
        XCTAssertEqual(release.tagName, "v0.1.1")
        XCTAssertEqual(release.version.description, "0.1.1")
        XCTAssertEqual(release.changelogMarkdown, "## Changes")
        XCTAssertEqual(release.repositoryHTMLURL, URL(string: "https://github.com/afollestad/alveary"))
        XCTAssertEqual(release.asset.name, "Alveary.app.zip")
        XCTAssertEqual(release.asset.size, 456)
        XCTAssertEqual(release.asset.apiURL, URL(string: "https://api.github.com/repos/afollestad/alveary/releases/assets/123"))
        XCTAssertEqual(release.asset.downloadURL, URL(string: "https://github.com/afollestad/alveary/releases/download/v0.1.1/Alveary.app.zip"))

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.map(\.executable), Array(repeating: "/usr/bin/env", count: 4))
        XCTAssertEqual(invocations[0].args, ["gh", "--version"])
        XCTAssertEqual(invocations[1].args, ["gh", "auth", "status"])
        XCTAssertEqual(
            invocations[2].args,
            ["gh", "repo", "view", "afollestad/alveary", "--json", "nameWithOwner", "--jq", ".nameWithOwner"]
        )
        XCTAssertEqual(invocations[3].args, ["gh", "api", "repos/afollestad/alveary/releases/latest"])
        XCTAssertEqual(invocations[3].stdoutLimitBytes, 2 * 1024 * 1024)
    }

    func testMissingGitHubCLIReturnsExplicitState() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stderr: "env: gh: No such file or directory", exitCode: 127)))
        let client = GitHubCLIAppUpdateReleaseClient(shellRunner: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.gitHubCLINotInstalled))
    }

    func testUnauthenticatedGitHubCLIReturnsExplicitState() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "gh version 2.89.0")))
        await shell.enqueue(.success(shellResult(stderr: "You are not logged into any GitHub hosts", exitCode: 1)))
        let client = GitHubCLIAppUpdateReleaseClient(shellRunner: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.gitHubCLINotAuthenticated))
    }

    func testInaccessibleRepositoryReturnsExplicitState() async {
        let shell = await authenticatedShell()
        await shell.enqueue(
            .success(shellResult(stderr: "GraphQL: Could not resolve to a Repository with the name 'alveary'. (HTTP 404)", exitCode: 1))
        )
        let client = GitHubCLIAppUpdateReleaseClient(shellRunner: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.privateOrNotFound))
    }

    func testNoReleaseReturnsExplicitState() async {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stderr: "gh: Not Found (HTTP 404)", exitCode: 1)))
        let client = GitHubCLIAppUpdateReleaseClient(shellRunner: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.noRelease))
    }

    func testRateLimitReturnsExplicitState() async {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stderr: "gh: API rate limit exceeded (HTTP 403)", exitCode: 1)))
        let client = GitHubCLIAppUpdateReleaseClient(shellRunner: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.rateLimited(resetDate: nil)))
    }

    func testDraftReleaseIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try releaseJSON(draft: true))))
        let client = GitHubCLIAppUpdateReleaseClient(shellRunner: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.draftRelease))
    }

    func testPrereleaseIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try releaseJSON(prerelease: true))))
        let client = GitHubCLIAppUpdateReleaseClient(shellRunner: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.prerelease))
    }

    func testMalformedTagIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try releaseJSON(tagName: "nightly"))))
        let client = GitHubCLIAppUpdateReleaseClient(shellRunner: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.malformedVersion("nightly")))
    }

    func testMissingAssetIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try releaseJSON(assetName: "Alveary.zip"))))
        let client = GitHubCLIAppUpdateReleaseClient(shellRunner: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.missingAsset(expectedName: "Alveary.app.zip")))
    }

    func testNonHTTPSAssetIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(try shellResult(apiURL: "http://api.github.com/repos/afollestad/alveary/releases/assets/123")))
        let client = GitHubCLIAppUpdateReleaseClient(shellRunner: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.invalidAssetURL("http://api.github.com/repos/afollestad/alveary/releases/assets/123")))
    }

    func testNonHTTPSBrowserDownloadAssetIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(try shellResult(downloadURL: "http://example.com/Alveary.app.zip")))
        let client = GitHubCLIAppUpdateReleaseClient(shellRunner: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.invalidAssetURL("http://example.com/Alveary.app.zip")))
    }

    func testDecodingFailureIsExplicit() async {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdout: "{")))
        let client = GitHubCLIAppUpdateReleaseClient(shellRunner: shell)

        let result = await client.latestRelease()

        guard case .unavailable(.decodingFailed(let message)) = result else {
            XCTFail("Expected decoding failure, got \(result)")
            return
        }
        XCTAssertFalse(message.isEmpty)
    }
}

private extension AppUpdateReleaseLookupResult {
    var installableRelease: AppUpdateRelease? {
        guard case .installable(let release) = self else {
            return nil
        }
        return release
    }
}

private func authenticatedShell() async -> MockShellRunner {
    let shell = MockShellRunner()
    await shell.enqueue(.success(shellResult(stdout: "gh version 2.89.0")))
    await shell.enqueue(.success(shellResult(stdout: "Logged in to github.com")))
    return shell
}

private func repositoryAccessibleShell() async -> MockShellRunner {
    let shell = await authenticatedShell()
    await shell.enqueue(.success(shellResult(stdout: "afollestad/alveary")))
    return shell
}

private func shellResult(
    stdout: String = "",
    stdoutData: Data? = nil,
    stderr: String = "",
    exitCode: Int32 = 0
) -> ShellResult {
    ShellResult(
        stdout: stdout,
        stdoutData: stdoutData,
        stderr: stderr,
        exitCode: exitCode,
        stdoutWasTruncated: false,
        stderrWasTruncated: false
    )
}

private func shellResult(downloadURL: String) throws -> ShellResult {
    shellResult(stdoutData: try releaseJSON(downloadURL: downloadURL))
}

private func shellResult(apiURL: String) throws -> ShellResult {
    shellResult(stdoutData: try releaseJSON(apiURL: apiURL))
}

private func releaseJSON(
    tagName: String = "v0.1.1",
    body: String? = "## Changes",
    htmlURL: String = "https://github.com/afollestad/alveary/releases/tag/v0.1.1",
    draft: Bool = false,
    prerelease: Bool = false,
    assetName: String = "Alveary.app.zip",
    apiURL: String = "https://api.github.com/repos/afollestad/alveary/releases/assets/123",
    downloadURL: String = "https://github.com/afollestad/alveary/releases/download/v0.1.1/Alveary.app.zip"
) throws -> Data {
    let release = StubGitHubReleaseResponse(
        tagName: tagName,
        body: body,
        htmlURL: htmlURL,
        draft: draft,
        prerelease: prerelease,
        assets: [
            StubGitHubReleaseAssetResponse(
                name: assetName,
                url: apiURL,
                browserDownloadURL: downloadURL,
                size: 456
            )
        ]
    )
    return try JSONEncoder().encode(release)
}

private struct StubGitHubReleaseResponse: Encodable {
    let tagName: String
    let body: String?
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [StubGitHubReleaseAssetResponse]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

private struct StubGitHubReleaseAssetResponse: Encodable {
    let name: String
    let url: String
    let browserDownloadURL: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case browserDownloadURL = "browser_download_url"
        case size
    }
}
