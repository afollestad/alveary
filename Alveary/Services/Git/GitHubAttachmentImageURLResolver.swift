import Foundation

/// Mints anonymously fetchable signed URLs for `github.com/user-attachments`
/// image sources.
///
/// Attachment assets are served only to a signed-in browser session — always in
/// private repositories, and even in public ones until the embedding content is
/// saved and propagated — so a plain fetch of the markdown URL can 404. GitHub's
/// markdown render API (`gh api /markdown` with a repository `context`) rewrites
/// such URLs to `private-user-images.githubusercontent.com` links carrying a
/// short-lived JWT, which download without any credentials. The rewrite runs
/// under the `gh` token's identity, so it covers every asset the user can see.
@MainActor
final class GitHubAttachmentImageURLResolver {
    private static let mintTimeout: Duration = .seconds(20)
    private static let outputLimitBytes = 256 * 1024
    /// Minted JWTs live five minutes; serve cached ones only well inside that.
    private static let mintedURLLifetime: TimeInterval = 180
    private static let maximumRepositories = 8
    private static let userAttachmentPrefix = "https://github.com/user-attachments/assets/"
    private static let signedHost = "private-user-images.githubusercontent.com"

    private let shellRunner: any ShellRunner
    private let executableResolver: any ExecutablePathResolving
    private let now: () -> Date

    /// Repositories whose content the user recently viewed, most recent first.
    /// The render API only rewrites an asset URL when the context repository can
    /// see the asset, so resolution tries these in order.
    private var repositories: [String] = []
    private var mintedURLs: [String: MintedURL] = [:]
    private var inFlightMints: [String: Task<URL?, Never>] = [:]

    init(
        shellRunner: any ShellRunner,
        executableResolver: any ExecutablePathResolving,
        now: @escaping () -> Date = Date.init
    ) {
        self.shellRunner = shellRunner
        self.executableResolver = executableResolver
        self.now = now
    }

    /// Notes a repository as a candidate render context; call when the user
    /// opens content from it (e.g. a pull-request pane).
    func registerRepository(_ nameWithOwner: String) {
        let trimmed = nameWithOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        repositories.removeAll { $0 == trimmed }
        repositories.insert(trimmed, at: 0)
        if repositories.count > Self.maximumRepositories {
            repositories.removeLast(repositories.count - Self.maximumRepositories)
        }
    }

    /// Returns a signed URL for a user-attachments source, or nil when the
    /// source is not one, no registered context can see it, or minting fails.
    func resolveSignedURL(forSource source: String) async -> URL? {
        guard source.hasPrefix(Self.userAttachmentPrefix) else {
            return nil
        }
        if let minted = mintedURLs[source], now().timeIntervalSince(minted.mintedAt) < Self.mintedURLLifetime {
            return minted.url
        }
        if let inFlight = inFlightMints[source] {
            return await inFlight.value
        }
        let mint = Task {
            await self.mintSignedURL(forSource: source)
        }
        inFlightMints[source] = mint
        let url = await mint.value
        inFlightMints[source] = nil
        if let url {
            mintedURLs[source] = MintedURL(url: url, mintedAt: now())
        }
        return url
    }

    /// Extracts the first signed image URL from render-API HTML output.
    /// Internal for tests.
    static func signedURL(inRenderedHTML html: String) -> URL? {
        let host = NSRegularExpression.escapedPattern(for: signedHost)
        guard let range = html.range(
            of: "src=\"https://\(host)/[^\"]+\"",
            options: .regularExpression
        ) else {
            return nil
        }
        let value = html[range]
            .dropFirst("src=\"".count)
            .dropLast()
            .replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: value)
    }

    private func mintSignedURL(forSource source: String) async -> URL? {
        guard let ghPath = await executableResolver.resolveExecutablePath(for: "gh") else {
            return nil
        }
        for repository in repositories {
            let args = [
                "api", "/markdown",
                "-f", "text=![a](\(source))",
                "-f", "mode=gfm",
                "-f", "context=\(repository)"
            ]
            guard let result = try? await shellRunner.run(
                executable: ghPath,
                args: args,
                timeout: Self.mintTimeout,
                stdoutLimitBytes: Self.outputLimitBytes,
                stderrLimitBytes: Self.outputLimitBytes,
                standardInput: .nullDevice
            ), result.succeeded else {
                continue
            }
            // No rewrite means this context repository cannot see the asset;
            // try the next one.
            if let signed = Self.signedURL(inRenderedHTML: result.stdout) {
                return signed
            }
        }
        return nil
    }
}

private struct MintedURL {
    let url: URL
    let mintedAt: Date
}
