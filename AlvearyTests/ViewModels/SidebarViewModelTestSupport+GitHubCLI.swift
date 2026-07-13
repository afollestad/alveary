import Foundation

@testable import Alveary

@MainActor
final class SidebarMockGitHubCLIService: GitHubCLIService, @unchecked Sendable {
    private let installedVersion: String?
    private let authenticated: Bool

    private(set) var checkInstalledCallCount = 0
    private(set) var isAuthenticatedCallCount = 0

    init(installedVersion: String?, authenticated: Bool) {
        self.installedVersion = installedVersion
        self.authenticated = authenticated
    }

    func checkInstalled() async -> String? {
        checkInstalledCallCount += 1
        return installedVersion
    }

    func isAuthenticated() async -> Bool {
        isAuthenticatedCallCount += 1
        return authenticated
    }

    func authenticate() async throws -> GitHubDeviceCode {
        throw GitHubError.authParseFailed
    }

    func awaitAuthentication() async throws -> Bool {
        false
    }

    func cancelAuthentication() {}
}
