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
            return "Unable to read the GitHub one-time code from the GitHub CLI's output"
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
    /// Adds OAuth scopes to the existing `gh` sign-in through the same device-code flow as
    /// `authenticate()`, finished with `awaitAuthentication()`. Starting either flow cancels the
    /// other, since they share one `gh` process.
    func refreshAuthentication(addingScopes scopes: [String]) async throws -> GitHubDeviceCode
    func awaitAuthentication() async throws -> Bool
    func cancelAuthentication()
}
