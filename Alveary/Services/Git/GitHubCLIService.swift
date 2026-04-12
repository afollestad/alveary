import Foundation

struct GitHubDeviceCode: Sendable, Equatable {
    let code: String
    let verificationURL: URL
}

enum GitHubError: Error, Sendable, Equatable {
    case authParseFailed
    case authLaunchFailed(String)
}

extension GitHubError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authParseFailed:
            return "Unable to read the GitHub device login code from `gh auth login` output"
        case .authLaunchFailed(let message):
            return message
        }
    }
}

@MainActor
protocol GitHubCLIService: AnyObject, Sendable {
    func checkInstalled() async -> String?
    func isAuthenticated() async -> Bool
    func authenticate() async throws -> GitHubDeviceCode
    func awaitAuthentication() async throws -> Bool
    func cancelAuthentication()
    func run(args: [String], in directory: String?) async throws -> ShellResult
}
