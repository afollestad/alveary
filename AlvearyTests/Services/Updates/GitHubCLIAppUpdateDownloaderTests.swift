import XCTest

@testable import Alveary

final class GitHubCLIAppUpdateDownloaderTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        ServiceURLProtocolStub.reset()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitHubCLIAppUpdateDownloaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        ServiceURLProtocolStub.reset()
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testStreamsReleaseAssetWithAuthenticatedGitHubRequest() async throws {
        let firstChunk = Data((0..<40_000).map { UInt8($0 % 251) })
        let secondChunk = Data((0..<30_000).map { UInt8($0 % 197) })
        let assetData = firstChunk + secondChunk
        let release = try makeRelease(expectedSize: assetData.count)
        ServiceURLProtocolStub.configure(
            responses: [
                release.asset.apiURL.absoluteString: [
                    .init(
                        statusCode: 200,
                        chunks: [firstChunk, secondChunk],
                        headers: ["Content-Length": "\(assetData.count)"],
                        chunkDelayNanoseconds: 5_000_000
                    )
                ]
            ]
        )
        let shell = AppUpdateDownloadShellRunner(mode: .token("github-token\n"))
        let progressRecorder = AppUpdateDownloadProgressRecorder()
        let downloader = GitHubCLIAppUpdateDownloader(
            shellRunner: shell,
            executableResolver: AppUpdateDownloadPathResolverFake(path: "/opt/homebrew/bin/gh"),
            temporaryDirectory: temporaryDirectory,
            sessionConfiguration: makeURLSessionConfiguration()
        )

        let downloadedURL = try await downloader.download(release: release) { progress in
            await progressRecorder.record(progress)
        }

        XCTAssertEqual(try Data(contentsOf: downloadedURL), assetData)
        let invocations = await shell.invocations()
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.executable, "/opt/homebrew/bin/gh")
        XCTAssertEqual(invocation.args, ["auth", "token"])
        XCTAssertEqual(invocation.stdoutLimitBytes, 64 * 1024)
        XCTAssertEqual(invocation.stderrLimitBytes, 64 * 1024)

        let requests = ServiceURLProtocolStub.recordedURLRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url, release.asset.apiURL)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/octet-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer github-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Alveary")

        let progressValues = await progressRecorder.values()
        XCTAssertEqual(progressValues.first, 0)
        XCTAssertEqual(progressValues.last, 1)
        XCTAssertTrue(progressValues.contains { $0 > 0 && $0 < 1 })
    }

    func testRemovesDownloadDirectoryWhenSizeDoesNotMatch() async throws {
        let release = try makeRelease(expectedSize: 10)
        ServiceURLProtocolStub.configure(
            responses: [
                release.asset.apiURL.absoluteString: [
                    .init(statusCode: 200, data: Data("short".utf8), headers: ["Content-Length": "5"])
                ]
            ]
        )
        let shell = AppUpdateDownloadShellRunner(mode: .token("github-token"))
        let downloader = GitHubCLIAppUpdateDownloader(
            shellRunner: shell,
            executableResolver: AppUpdateDownloadPathResolverFake(path: "/opt/homebrew/bin/gh"),
            temporaryDirectory: temporaryDirectory,
            sessionConfiguration: makeURLSessionConfiguration()
        )

        do {
            _ = try await downloader.download(release: release) { _ in }
            XCTFail("Expected size mismatch failure.")
        } catch let failure as AppUpdateFailure {
            XCTAssertTrue(failure.message.contains("GitHub reported 10 bytes"))
        }

        XCTAssertTrue(try remainingDownloadItems().isEmpty)
    }

    func testHTTPFailureRemovesDownloadDirectoryAndSurfacesStatusCode() async throws {
        let release = try makeRelease(expectedSize: 10)
        ServiceURLProtocolStub.configure(
            responses: [
                release.asset.apiURL.absoluteString: [
                    .init(statusCode: 403, data: Data("forbidden".utf8))
                ]
            ]
        )
        let shell = AppUpdateDownloadShellRunner(mode: .token("github-token"))
        let downloader = GitHubCLIAppUpdateDownloader(
            shellRunner: shell,
            executableResolver: AppUpdateDownloadPathResolverFake(path: "/opt/homebrew/bin/gh"),
            temporaryDirectory: temporaryDirectory,
            sessionConfiguration: makeURLSessionConfiguration()
        )

        do {
            _ = try await downloader.download(release: release) { _ in }
            XCTFail("Expected HTTP failure.")
        } catch let failure as AppUpdateFailure {
            XCTAssertEqual(failure.message, "GitHub failed to download the update asset. (HTTP 403)")
        }

        XCTAssertTrue(try remainingDownloadItems().isEmpty)
    }

    func testFailureSurfacesGitHubCLIAuthenticationError() async throws {
        let release = try makeRelease(expectedSize: 10)
        let shell = AppUpdateDownloadShellRunner(mode: .fail(stderr: "gh: not logged into github.com", exitCode: 1))
        let downloader = GitHubCLIAppUpdateDownloader(
            shellRunner: shell,
            executableResolver: AppUpdateDownloadPathResolverFake(path: "/opt/homebrew/bin/gh"),
            temporaryDirectory: temporaryDirectory,
            sessionConfiguration: makeURLSessionConfiguration()
        )

        do {
            _ = try await downloader.download(release: release) { _ in }
            XCTFail("Expected GitHub CLI failure.")
        } catch let failure as AppUpdateFailure {
            XCTAssertEqual(failure.message, "GitHub CLI is not authenticated.")
        }

        XCTAssertTrue(try remainingDownloadItems().isEmpty)
    }

    func testFailureSurfacesMissingGitHubCLI() async throws {
        let release = try makeRelease(expectedSize: 10)
        let shell = AppUpdateDownloadShellRunner(mode: .token("github-token"))
        let downloader = GitHubCLIAppUpdateDownloader(
            shellRunner: shell,
            executableResolver: AppUpdateDownloadPathResolverFake(path: nil),
            temporaryDirectory: temporaryDirectory,
            sessionConfiguration: makeURLSessionConfiguration()
        )

        do {
            _ = try await downloader.download(release: release) { _ in }
            XCTFail("Expected missing GitHub CLI failure.")
        } catch let failure as AppUpdateFailure {
            XCTAssertEqual(failure.message, "GitHub CLI is not installed.")
        }

        let invocations = await shell.invocations()
        XCTAssertTrue(invocations.isEmpty)
        XCTAssertTrue(try remainingDownloadItems().isEmpty)
    }

    private func makeRelease(expectedSize: Int) throws -> AppUpdateRelease {
        let tagName = "v0.1.1"
        return AppUpdateRelease(
            tagName: tagName,
            version: try XCTUnwrap(AppUpdateVersion(string: tagName)),
            changelogMarkdown: "Changes",
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/afollestad/alveary/releases/tag/\(tagName)")),
            repositoryHTMLURL: try XCTUnwrap(URL(string: "https://github.com/afollestad/alveary")),
            asset: AppUpdateReleaseAsset(
                name: "Alveary.app.zip",
                apiURL: try XCTUnwrap(URL(string: "https://api.github.com/repos/afollestad/alveary/releases/assets/123")),
                downloadURL: try XCTUnwrap(URL(string: "https://github.com/afollestad/alveary/releases/download/\(tagName)/Alveary.app.zip")),
                size: expectedSize
            )
        )
    }

    private func makeURLSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServiceURLProtocolStub.self]
        return configuration
    }

    private func remainingDownloadItems() throws -> [URL] {
        let downloadsDirectory = temporaryDirectory
            .appendingPathComponent("AlvearyUpdates", isDirectory: true)
        guard FileManager.default.fileExists(atPath: downloadsDirectory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: downloadsDirectory,
            includingPropertiesForKeys: nil
        )
    }
}

private actor AppUpdateDownloadShellRunner: ShellRunner {
    enum Mode: Sendable {
        case token(String)
        case fail(stderr: String, exitCode: Int32)
    }

    private let mode: Mode
    private var recordedInvocations: [MockShellRunner.Invocation] = []

    init(mode: Mode) {
        self.mode = mode
    }

    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions
    ) async throws -> ShellResult {
        recordedInvocations.append(
            MockShellRunner.Invocation(
                executable: executable,
                args: args,
                directory: directory,
                environment: options.environment,
                timeout: options.timeout,
                stdoutLimitBytes: options.stdoutLimitBytes,
                stderrLimitBytes: options.stderrLimitBytes
            )
        )

        switch mode {
        case .token(let token):
            return ShellResult(stdout: token, stderr: "", exitCode: 0, stdoutWasTruncated: false, stderrWasTruncated: false)
        case .fail(let stderr, let exitCode):
            return ShellResult(stdout: "", stderr: stderr, exitCode: exitCode, stdoutWasTruncated: false, stderrWasTruncated: false)
        }
    }

    func invocations() -> [MockShellRunner.Invocation] {
        recordedInvocations
    }
}

private actor AppUpdateDownloadProgressRecorder {
    private var recordedValues: [Double] = []

    func record(_ value: Double) {
        recordedValues.append(value)
    }

    func values() -> [Double] {
        recordedValues
    }
}

private struct AppUpdateDownloadPathResolverFake: ExecutablePathResolving {
    let path: String?

    func resolveExecutablePath(for candidate: String) async -> String? {
        XCTAssertEqual(candidate, "gh")
        return path
    }
}
