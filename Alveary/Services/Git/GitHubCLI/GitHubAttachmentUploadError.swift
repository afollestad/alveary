import Foundation

enum GitHubAttachmentUploadError: LocalizedError, Sendable, Equatable {
    case ghNotInstalled
    case unsupportedCLI(String)
    case compatibilityCheckFailed(String)
    case unsupportedFunctionality(String)
    case notAuthenticated
    case permissionDenied
    case repositoryUnavailable
    case unsupportedFile(String)
    case invalidFile(String)
    case fileTooLarge(String)
    case rateLimited(String)
    case invalidResponse(String)
    case uploadFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .ghNotInstalled:
            return "The GitHub CLI (gh) could not be found. Install it from https://cli.github.com/."
        case .unsupportedCLI(let version):
            return "Attachments require GitHub CLI \(Self.minimumVersion) or newer. Found \(version). \(Self.upgradeGuidance)"
        case .compatibilityCheckFailed(let detail):
            return "Could not verify GitHub CLI attachment compatibility. \(detail) \(Self.upgradeGuidance)"
        case .unsupportedFunctionality(let detail):
            return "This GitHub CLI does not support the commands needed for attachments. \(detail) \(Self.upgradeGuidance)"
        case .notAuthenticated:
            return "Sign in to GitHub in Git settings, or run gh auth login --hostname github.com, then retry the attachment."
        case .permissionDenied:
            return "Attaching files requires write access to the repository with your current GitHub CLI credentials."
        case .repositoryUnavailable:
            return "GitHub could not access the repository or attachment endpoint. Check the repository and your token's write access."
        case .unsupportedFile(let name):
            return "\(name) is not supported. Attach PNG, JPG, JPEG, GIF, WebP, SVG, MP4, MOV, or WebM files."
        case .rateLimited(let detail):
            return "GitHub is rate limiting attachment requests. Wait and retry the remaining files. \(detail)"
        case .invalidResponse(let detail):
            return "\(detail) Attachment API compatibility may have changed."
        case .invalidFile(let detail), .fileTooLarge(let detail), .uploadFailed(let detail):
            return detail
        case .cancelled:
            return "Attachment upload cancelled."
        }
    }

    /// Alveary's tested support floor, rather than the first release that happened to support `gh api --input`.
    static let minimumVersion = "2.99.0"

    static func checkVersion(_ output: String, executable: String) throws {
        let pattern = #"^gh version ([0-9]+)\.([0-9]+)\.([0-9]+)(?:[-+][A-Za-z0-9.+-]+)?(?:[ \t(]|$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) else {
            throw compatibilityCheckFailed("\(executable) returned an unrecognized version.")
        }
        let components = (1...3).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: output) else {
                return nil
            }
            return Int(output[range])
        }
        guard components.count == 3 else {
            throw compatibilityCheckFailed("\(executable) returned an unrecognized version.")
        }
        guard !components.lexicographicallyPrecedes([2, 99, 0]) else {
            let version = components.map(String.init).joined(separator: ".")
            throw unsupportedCLI("\(version) at \(executable)")
        }
    }

    static func wrapping(_ error: any Error) -> Self {
        (error as? Self) ?? .uploadFailed(error.localizedDescription)
    }

    /// Classify CLI syntax failures separately from HTTP failures: an endpoint 404 is not an old CLI.
    static func failure(for result: ShellResult) -> Self {
        let response = try? JSONDecoder().decode(APIError.self, from: result.stdoutData)
        let combined = [result.stderr, response?.message ?? "", result.stdout].joined(separator: " ").lowercased()
        let detail = (response?.message ?? result.stderr)
            .split(whereSeparator: \.isNewline).joined(separator: "; ")
        let concise = String(detail.prefix(1_000))
        if result.exitCode == 127 {
            return .ghNotInstalled
        }
        if combined.contains("unknown command") || combined.contains("unknown flag") || combined.contains("unknown shorthand flag") {
            return .unsupportedFunctionality(concise)
        }
        if combined.contains("http 401") || combined.contains("gh auth login") || combined.contains("not logged in") {
            return .notAuthenticated
        }
        if combined.contains("http 429") || combined.contains("rate limit") || combined.contains("abuse detection") {
            return .rateLimited(concise)
        }
        if combined.contains("http 403") {
            return .permissionDenied
        }
        if combined.contains("http 404") {
            return .repositoryUnavailable
        }
        if combined.contains("http 413") || (combined.contains("http 422") && combined.contains("size")) {
            return .fileTooLarge("GitHub rejected an attachment's size. Images allow up to 10 MiB; videos up to 100 MiB, depending on your plan.")
        }
        return .uploadFailed(concise.isEmpty ? "GitHub CLI exited with status \(result.exitCode)." : concise)
    }

    private static let upgradeGuidance = "Update GitHub CLI and retry. For Homebrew, run brew upgrade gh; other installs: https://cli.github.com/."
}

private struct APIError: Decodable {
    let message: String
}
