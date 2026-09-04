import Foundation

@MainActor
protocol GitHubAttachmentUploadService: AnyObject, Sendable {
    /// Preflight failures throw before uploading; a later failure returns the successful prefix.
    func upload(files: [URL], repository: String) async throws -> GitHubAttachmentUploadBatch
}

/// Uses the authenticated endpoint behind native `gh --attach`, preserving upload-only drafts.
/// The endpoint contract and repair procedure live in `docs/github-attachments.md` at the repo root.
@MainActor
final class DefaultGitHubAttachmentUploadService: GitHubAttachmentUploadService {
    init(shellRunner: any ShellRunner, executableResolver: any ExecutablePathResolving) {
        self.shellRunner = shellRunner
        self.executableResolver = executableResolver
    }

    func upload(files: [URL], repository: String) async throws -> GitHubAttachmentUploadBatch {
        guard !files.isEmpty else {
            return GitHubAttachmentUploadBatch(uploads: [])
        }
        try Task.checkCancellation()
        let attachments = try files.map(GitHubAttachmentFile.init)
        guard let ghPath = await executableResolver.resolveExecutablePath(for: "gh") else {
            throw GitHubAttachmentUploadError.ghNotInstalled
        }
        try await checkCompatibility(executable: ghPath)
        let repositoryID = try await resolveRepository(repository, executable: ghPath)
        var uploads: [GitHubAttachmentUpload] = []
        for attachment in attachments {
            do {
                try Task.checkCancellation()
                let result = try await run(
                    executable: ghPath,
                    args: Self.uploadArguments(attachment, repositoryID: repositoryID),
                    timeout: .seconds(300)
                )
                let response = try Self.decode(AssetResponse.self, from: result)
                guard let url = URL(string: response.url),
                      url.scheme == "https", url.host == "github.com",
                      url.user == nil, url.password == nil, url.port == nil,
                      url.query == nil, url.fragment == nil,
                      url.path.hasPrefix("/user-attachments/assets/"),
                      UUID(uuidString: url.lastPathComponent) != nil else {
                    throw GitHubAttachmentUploadError.invalidResponse("GitHub returned an invalid attachment URL.")
                }
                // Record a confirmed upload even if cancellation arrived while the response was being read.
                uploads.append(attachment.upload(at: url))
            } catch is CancellationError {
                return GitHubAttachmentUploadBatch(uploads: uploads, failure: .cancelled)
            } catch {
                let failure = Task.isCancelled ? .cancelled : GitHubAttachmentUploadError.wrapping(error)
                return GitHubAttachmentUploadBatch(uploads: uploads, failure: failure)
            }
        }
        return GitHubAttachmentUploadBatch(uploads: uploads)
    }

    private let shellRunner: any ShellRunner
    private let executableResolver: any ExecutablePathResolving

    /// Rechecked per batch so replacing the executable after an upgrade needs no app restart.
    private func checkCompatibility(executable: String) async throws {
        let result: ShellResult
        do {
            result = try await shellRunner.run(
                executable: executable,
                args: ["--version"],
                timeout: .seconds(20),
                stdoutLimitBytes: 64 * 1024,
                stderrLimitBytes: 64 * 1024,
                standardInput: .nullDevice
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw GitHubAttachmentUploadError.compatibilityCheckFailed("\(executable): \(error.localizedDescription)")
        }
        try Task.checkCancellation()
        guard result.succeeded, !result.stdoutWasTruncated else {
            throw GitHubAttachmentUploadError.compatibilityCheckFailed("\(executable): \(Self.detail(from: result))")
        }
        try GitHubAttachmentUploadError.checkVersion(result.stdout, executable: executable)
    }

    private func resolveRepository(_ repository: String, executable: String) async throws -> Int64 {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard parts.count == 2, parts.allSatisfy({ part in
            !part.isEmpty && part != "." && part != ".." && part.unicodeScalars.allSatisfy(allowed.contains)
        }) else {
            throw GitHubAttachmentUploadError.uploadFailed("The attachment repository must be owner/name.")
        }
        try Task.checkCancellation()
        let result = try await run(
            executable: executable,
            args: ["api", "--hostname", "github.com", "repos/\(repository)"],
            timeout: .seconds(20)
        )
        let response = try Self.decode(RepositoryResponse.self, from: result)
        guard response.id > 0 else {
            throw GitHubAttachmentUploadError.invalidResponse("GitHub returned an invalid repository ID.")
        }
        guard response.permissions.push else {
            throw GitHubAttachmentUploadError.permissionDenied
        }
        return response.id
    }

    private func run(executable: String, args: [String], timeout: Duration) async throws -> ShellResult {
        do {
            let result = try await shellRunner.run(
                executable: executable,
                args: args,
                timeout: timeout,
                stdoutLimitBytes: 64 * 1024,
                stderrLimitBytes: 64 * 1024,
                standardInput: .nullDevice
            )
            guard result.succeeded else {
                throw GitHubAttachmentUploadError.failure(for: result)
            }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GitHubAttachmentUploadError.wrapping(error)
        }
    }

    /// With `--input`, fields become query parameters while the file remains the raw request body.
    private static func uploadArguments(_ attachment: GitHubAttachmentFile, repositoryID: Int64) -> [String] {
        [
            "api", "--hostname", "github.com", "--method", "POST",
            "https://uploads.github.com/user-attachments/assets",
            "--input", attachment.fileURL.path,
            "--header", "Content-Type: application/octet-stream",
            "--header", "Accept: application/vnd.github+json",
            "--raw-field", "name=\(attachment.fileURL.lastPathComponent)",
            "--raw-field", "content_type=\(attachment.contentType)",
            "--field", "repository_id=\(repositoryID)"
        ]
    }

    private static func decode<T: Decodable>(_ type: T.Type, from result: ShellResult) throws -> T {
        guard !result.stdoutWasTruncated else {
            throw GitHubAttachmentUploadError.invalidResponse("GitHub's attachment response was truncated.")
        }
        do {
            return try JSONDecoder().decode(type, from: result.stdoutData)
        } catch {
            throw GitHubAttachmentUploadError.invalidResponse("GitHub returned an unreadable attachment response.")
        }
    }

    private static func detail(from result: ShellResult) -> String {
        let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "gh exited with status \(result.exitCode)." : String(detail.prefix(1_000))
    }
}

private struct RepositoryResponse: Decodable {
    let id: Int64
    let permissions: Permissions

    struct Permissions: Decodable {
        let push: Bool
    }
}

private struct AssetResponse: Decodable {
    let url: String
}
