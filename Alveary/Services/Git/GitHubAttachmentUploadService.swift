import Foundation

/// One uploaded attachment: the local file it came from plus the markdown
/// reference GitHub serves it under (`![name](url)` for images, a link for
/// other types, a bare URL for video).
struct GitHubAttachmentUpload: Sendable, Equatable {
    let fileURL: URL
    let markdownReference: String

    /// The uploaded asset's URL, extracted from whichever reference form the
    /// extension printed: `![name](url)`, `[name](url)`, or a bare URL.
    var referenceURL: URL? {
        if let range = markdownReference.range(of: #"\]\(([^)]+)\)$"#, options: .regularExpression) {
            let inner = markdownReference[range].dropFirst("](".count).dropLast()
            return URL(string: String(inner))
        }
        let trimmed = markdownReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("https://") else {
            return nil
        }
        return URL(string: trimmed)
    }
}

enum GitHubAttachmentUploadError: LocalizedError, Sendable, Equatable {
    /// The `gh-image` extension is not installed. GitHub publishes no API for
    /// comment attachments, so the extension is the only upload path.
    case extensionMissing
    /// The extension ran but could not read a GitHub web session from the browser.
    /// Usually a privacy grant, not a sign-in problem: Safari keeps its cookies in
    /// a TCC-protected container, and the child process inherits *Alveary's*
    /// grants, so a read that works from Terminal fails when the app spawns it.
    case sessionUnavailable(String)
    case ghNotInstalled
    /// A file exceeds GitHub's attachment size limit for its kind; caught
    /// before invoking the extension. The message names the file and limit.
    case fileTooLarge(String)
    case uploadFailed(String)
    /// The extension exited successfully but printed fewer references than files.
    case incompleteOutput

    var errorDescription: String? {
        switch self {
        case .extensionMissing:
            return "Attaching files needs the gh-image extension. Install it with: gh extension install drogers0/gh-image"
        case .sessionUnavailable(let detail):
            return """
                Alveary could not read your GitHub browser session. Safari keeps cookies where Alveary needs \
                Full Disk Access to read them; signing in with Chrome instead needs only a one-time Keychain \
                approval. \(detail)
                """
        case .ghNotInstalled:
            return "The GitHub CLI (gh) could not be found."
        case .fileTooLarge(let detail):
            return detail
        case .uploadFailed(let detail):
            return detail
        case .incompleteOutput:
            return "The upload finished without returning a link for every file."
        }
    }
}

/// GitHub's published attachment size limits by file kind. Enforced before the
/// upload runs so an oversized file fails instantly with a clear message
/// instead of the policy endpoint's HTML-laden 422 ("Yowza that's a big file").
/// Limits use binary megabytes — the generous reading of GitHub's "10 MB" — and
/// the 422 classification in `failure(for:)` backstops anything that slips by.
enum GitHubAttachmentSizeLimit {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "heic", "heif"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "webm"]

    /// The limit and human-readable kind for a file, by path extension.
    static func limit(forPathExtension pathExtension: String) -> (bytes: Int, label: String) {
        let normalized = pathExtension.lowercased()
        if imageExtensions.contains(normalized) {
            return (10 * 1024 * 1024, "images up to 10 MB")
        }
        if videoExtensions.contains(normalized) {
            return (100 * 1024 * 1024, "videos up to 100 MB")
        }
        return (25 * 1024 * 1024, "files up to 25 MB")
    }

    /// Returns a thrown-ready error when `file` exceeds its kind's limit; nil
    /// when it fits or its size cannot be read (the upload then surfaces the
    /// real filesystem error).
    static func oversizeError(for file: URL) -> GitHubAttachmentUploadError? {
        guard let bytes = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        let limit = limit(forPathExtension: file.pathExtension)
        guard bytes > limit.bytes else {
            return nil
        }
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return .fileTooLarge("\(file.lastPathComponent) is \(size) — GitHub allows \(limit.label).")
    }
}

@MainActor
protocol GitHubAttachmentUploadService: AnyObject, Sendable {
    /// Whether the `gh-image` extension is installed and runnable.
    func isAvailable() async -> Bool
    /// Uploads `files` to `repository` ("owner/name") and returns one reference
    /// per file, in the order given.
    func upload(files: [URL], repository: String) async throws -> [GitHubAttachmentUpload]
}

/// Uploads comment attachments by shelling out to the `gh-image` extension.
///
/// GitHub's own drag-and-drop flow (`/upload/policies/assets` → S3 → finalize)
/// authenticates only with the `user_session` browser cookie; an API token is
/// ignored outright. Delegating to the extension keeps that full-account
/// credential out of Alveary — the extension reads it from the browser's
/// encrypted cookie store under the user's own Keychain grant.
@MainActor
final class DefaultGitHubAttachmentUploadService: GitHubAttachmentUploadService {
    /// Uploads are network-bound and can be several megabytes per file, so this
    /// is far longer than a metadata call's budget.
    private static let uploadTimeout: Duration = .seconds(300)
    private static let availabilityTimeout: Duration = .seconds(20)
    private static let outputLimitBytes = 64 * 1024

    private let shellRunner: any ShellRunner
    private let executableResolver: any ExecutablePathResolving

    init(shellRunner: any ShellRunner, executableResolver: any ExecutablePathResolving) {
        self.shellRunner = shellRunner
        self.executableResolver = executableResolver
    }

    func isAvailable() async -> Bool {
        guard let ghPath = await executableResolver.resolveExecutablePath(for: "gh") else {
            return false
        }
        do {
            let result = try await shellRunner.run(
                executable: ghPath,
                args: ["image", "--version"],
                timeout: Self.availabilityTimeout,
                stdoutLimitBytes: Self.outputLimitBytes,
                stderrLimitBytes: Self.outputLimitBytes,
                standardInput: .nullDevice
            )
            return result.succeeded
        } catch {
            return false
        }
    }

    func upload(files: [URL], repository: String) async throws -> [GitHubAttachmentUpload] {
        guard !files.isEmpty else {
            return []
        }
        for file in files {
            if let oversized = GitHubAttachmentSizeLimit.oversizeError(for: file) {
                throw oversized
            }
        }
        guard let ghPath = await executableResolver.resolveExecutablePath(for: "gh") else {
            throw GitHubAttachmentUploadError.ghNotInstalled
        }

        // `--` guards filenames that begin with a dash from being read as flags.
        let args = ["image", "--repo", repository, "--"] + files.map(\.path)
        let result: ShellResult
        do {
            result = try await shellRunner.run(
                executable: ghPath,
                args: args,
                timeout: Self.uploadTimeout,
                stdoutLimitBytes: Self.outputLimitBytes,
                stderrLimitBytes: Self.outputLimitBytes,
                // Never inherit stdin: a credential or confirmation prompt would
                // otherwise hang the upload with no visible cause.
                standardInput: .nullDevice
            )
        } catch let error as GitHubAttachmentUploadError {
            throw error
        } catch {
            throw GitHubAttachmentUploadError.uploadFailed(error.localizedDescription)
        }

        guard result.succeeded else {
            throw Self.failure(for: result)
        }

        let references = result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard references.count == files.count else {
            throw GitHubAttachmentUploadError.incompleteOutput
        }
        return zip(files, references).map { file, reference in
            GitHubAttachmentUpload(fileURL: file, markdownReference: reference)
        }
    }

    /// Classifies a failed run so hosts can offer the right remedy: installing
    /// the extension, signing in again, or just reporting the message.
    private static func failure(for result: ShellResult) -> GitHubAttachmentUploadError {
        let combined = [result.stderr, result.stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let lowercased = combined.lowercased()

        if lowercased.contains("unknown command") || lowercased.contains("extension not found") {
            return .extensionMissing
        }
        // The policy endpoint's size rejection carries an HTML-laden message;
        // replace it with the limits. Backstops the pre-flight check when
        // GitHub's enforced threshold is stricter than the advertised one.
        if lowercased.contains("\"resource\":\"userasset\""), lowercased.contains("\"field\":\"size\"") {
            return .fileTooLarge(
                "GitHub rejected an attachment as too large: images can be up to 10 MB, videos 100 MB, and other files 25 MB."
            )
        }
        if lowercased.contains("session") || lowercased.contains("cookie") || lowercased.contains("sign in") {
            return .sessionUnavailable(combined)
        }
        guard !combined.isEmpty else {
            return .uploadFailed("Uploading attachments failed with exit code \(result.exitCode).")
        }
        return .uploadFailed(combined)
    }
}
