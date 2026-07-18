import Foundation

actor GitHubCLIAppUpdateReleaseClient: AppUpdateReleaseClient {
    static let defaultOwner = "afollestad"
    static let defaultRepository = "alveary"
    static let expectedAssetName = "Alveary.app.zip"

    private let owner: String
    private let repository: String
    private let shellRunner: any ShellRunner
    private let executableResolver: any ExecutablePathResolving
    private let decoder: JSONDecoder

    init(
        owner: String = GitHubCLIAppUpdateReleaseClient.defaultOwner,
        repository: String = GitHubCLIAppUpdateReleaseClient.defaultRepository,
        shellRunner: any ShellRunner = DefaultShellRunner(),
        executableResolver: (any ExecutablePathResolving)? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.owner = owner
        self.repository = repository
        self.shellRunner = shellRunner
        self.executableResolver = executableResolver ?? DefaultExecutablePathResolver(shell: shellRunner)
        self.decoder = decoder
    }

    func latestRelease() async -> AppUpdateReleaseLookupResult {
        guard let ghExecutable = await executableResolver.resolveExecutablePath(for: "gh") else {
            return .unavailable(.gitHubCLINotInstalled)
        }

        do {
            let versionResult = try await runGitHubCLI(
                executable: ghExecutable,
                args: ["--version"],
                timeout: .seconds(3)
            )
            guard versionResult.succeeded else {
                return .unavailable(.gitHubCLINotInstalled)
            }

            let authResult = try await runGitHubCLI(
                executable: ghExecutable,
                args: ["auth", "status"],
                timeout: .seconds(5)
            )
            guard authResult.succeeded else {
                return .unavailable(.gitHubCLINotAuthenticated)
            }

            let repositoryResult = try await runGitHubCLI(
                executable: ghExecutable,
                args: ["repo", "view", "\(owner)/\(repository)", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
                timeout: .seconds(10)
            )
            guard repositoryResult.succeeded else {
                return failureResult(for: repositoryResult, notFoundReason: .privateOrNotFound)
            }

            let releaseResult = try await runGitHubCLI(
                executable: ghExecutable,
                args: ["api", "--paginate", "--slurp", "repos/\(owner)/\(repository)/releases?per_page=100"],
                timeout: .seconds(30),
                stdoutLimitBytes: 16 * 1024 * 1024
            )
            guard releaseResult.succeeded else {
                return failureResult(for: releaseResult, notFoundReason: .noRelease)
            }
            guard !releaseResult.stdoutWasTruncated else {
                return .unavailable(.decodingFailed("GitHub releases response exceeded the 16 MB limit."))
            }

            return decodeReleaseResponse(data: releaseResult.stdoutData)
        } catch {
            return .unavailable(.transportFailed(error.localizedDescription))
        }
    }
}

private extension GitHubCLIAppUpdateReleaseClient {
    func runGitHubCLI(
        executable: String,
        args: [String],
        timeout: Duration,
        stdoutLimitBytes: Int? = 64 * 1024
    ) async throws -> ShellResult {
        try await shellRunner.run(
            executable: executable,
            args: args,
            timeout: timeout,
            stdoutLimitBytes: stdoutLimitBytes,
            stderrLimitBytes: 64 * 1024
        )
    }

    func decodeReleaseResponse(data: Data) -> AppUpdateReleaseLookupResult {
        let pages: [[GitHubReleaseResponse]]
        do {
            pages = try decoder.decode([[GitHubReleaseResponse]].self, from: data)
        } catch {
            return .unavailable(.decodingFailed(error.localizedDescription))
        }

        switch stableReleaseHistory(from: pages.flatMap { $0 }) {
        case .success(let releases):
            return makeReleaseFeed(from: releases)
        case .failure(let reason):
            return .unavailable(reason)
        }
    }

    func stableReleaseHistory(from releases: [GitHubReleaseResponse]) -> StableReleaseHistoryResult {
        guard !releases.isEmpty else {
            return .failure(.noRelease)
        }

        let nonDraftReleases = releases.filter { !$0.draft }
        guard !nonDraftReleases.isEmpty else {
            return .failure(.draftRelease)
        }

        let stableReleases = nonDraftReleases.filter { !$0.prerelease }
        guard !stableReleases.isEmpty else {
            return .failure(.prerelease)
        }

        let versionedReleases = stableReleases.compactMap { release -> VersionedGitHubRelease? in
            guard let version = AppUpdateVersion(string: release.tagName) else {
                return nil
            }
            return VersionedGitHubRelease(release: release, version: version)
        }
        guard !versionedReleases.isEmpty else {
            return .failure(.malformedVersion(stableReleases[0].tagName))
        }

        var seenVersions = Set<AppUpdateVersion>()
        let sortedReleases = versionedReleases
            .filter { seenVersions.insert($0.version).inserted }
            .sorted { $0.version > $1.version }
        return .success(sortedReleases)
    }

    func makeReleaseFeed(from sortedReleases: [VersionedGitHubRelease]) -> AppUpdateReleaseLookupResult {
        guard let latest = sortedReleases.first else {
            return .unavailable(.noRelease)
        }
        let release = latest.release
        guard let htmlURL = URL(string: release.htmlURL),
              htmlURL.scheme == "https" else {
            return .unavailable(.invalidReleaseURL(release.htmlURL))
        }
        let repositoryHTMLURLString = "https://github.com/\(owner)/\(repository)"
        guard let repositoryHTMLURL = URL(string: repositoryHTMLURLString),
              repositoryHTMLURL.scheme == "https" else {
            return .unavailable(.invalidReleaseURL(repositoryHTMLURLString))
        }
        guard let asset = release.assets.first(where: { $0.name == Self.expectedAssetName }) else {
            return .unavailable(.missingAsset(expectedName: Self.expectedAssetName))
        }
        let releaseAsset: AppUpdateReleaseAsset
        switch appUpdateReleaseAsset(from: asset) {
        case .success(let asset):
            releaseAsset = asset
        case .failure(let reason):
            return .unavailable(reason)
        }

        return .installable(
            AppUpdateReleaseFeed(
                latestRelease: AppUpdateRelease(
                    tagName: release.tagName,
                    version: latest.version,
                    changelogMarkdown: release.body ?? "",
                    htmlURL: htmlURL,
                    repositoryHTMLURL: repositoryHTMLURL,
                    asset: releaseAsset
                ),
                releaseNotes: sortedReleases.map { release in
                    AppUpdateReleaseNote(
                        tagName: release.release.tagName,
                        version: release.version,
                        changelogMarkdown: release.release.body ?? ""
                    )
                }
            )
        )
    }

    func appUpdateReleaseAsset(from asset: GitHubReleaseAssetResponse) -> AppUpdateReleaseAssetValidationResult {
        guard let assetAPIURL = URL(string: asset.url),
              assetAPIURL.scheme == "https" else {
            return .failure(.invalidAssetURL(asset.url))
        }
        guard let downloadURL = URL(string: asset.browserDownloadURL),
              downloadURL.scheme == "https" else {
            return .failure(.invalidAssetURL(asset.browserDownloadURL))
        }
        guard let assetDigest = asset.digest,
              !assetDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.missingAssetDigest(expectedName: Self.expectedAssetName))
        }
        guard let digest = AppUpdateReleaseAssetDigest(gitHubDigest: assetDigest) else {
            return .failure(.invalidAssetDigest(assetDigest))
        }

        return .success(
            AppUpdateReleaseAsset(
                name: asset.name,
                apiURL: assetAPIURL,
                downloadURL: downloadURL,
                size: asset.size,
                digest: digest
            )
        )
    }

    func failureResult(
        for result: ShellResult,
        notFoundReason: AppUpdateUnavailableReason
    ) -> AppUpdateReleaseLookupResult {
        let message = Self.failureMessage(from: result)
        if message.contains("HTTP 404") || message.localizedCaseInsensitiveContains("not found") {
            return .unavailable(notFoundReason)
        }
        if message.contains("HTTP 401") {
            return .unavailable(.gitHubCLINotAuthenticated)
        }
        if message.contains("HTTP 403"),
           message.localizedCaseInsensitiveContains("rate limit") {
            return .unavailable(.rateLimited(resetDate: nil))
        }
        if let statusCode = Self.httpStatusCode(in: message) {
            return .unavailable(.requestFailed(statusCode: statusCode))
        }
        if result.exitCode == 127 {
            return .unavailable(.gitHubCLINotInstalled)
        }
        return .unavailable(.transportFailed(message.isEmpty ? "GitHub CLI exited with \(result.exitCode)." : message))
    }

    static func failureMessage(from result: ShellResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func httpStatusCode(in message: String) -> Int? {
        message
            .split { !$0.isNumber }
            .compactMap { Int($0) }
            .first { (100...599).contains($0) }
    }
}

private extension String {
    func localizedCaseInsensitiveContains(_ other: String) -> Bool {
        range(of: other, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let body: String?
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAssetResponse]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

private struct GitHubReleaseAssetResponse: Decodable {
    let name: String
    let url: String
    let browserDownloadURL: String
    let size: Int?
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case browserDownloadURL = "browser_download_url"
        case size
        case digest
    }
}

private struct VersionedGitHubRelease {
    let release: GitHubReleaseResponse
    let version: AppUpdateVersion
}

private enum StableReleaseHistoryResult {
    case success([VersionedGitHubRelease])
    case failure(AppUpdateUnavailableReason)
}

private enum AppUpdateReleaseAssetValidationResult {
    case success(AppUpdateReleaseAsset)
    case failure(AppUpdateUnavailableReason)
}
