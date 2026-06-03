import AgentCLIKit
import Foundation

actor DefaultProviderSetupService: ProviderSetupService {
    private nonisolated let projectTrustService: any AgentCLIKit.AgentProjectTrustService
    private let projectTrustUpdatesProvider: @Sendable () async -> AsyncStream<Void>

    init(
        projectTrustService: any AgentCLIKit.AgentProjectTrustService,
        projectTrustUpdates: @escaping @Sendable () async -> AsyncStream<Void> = {
            AsyncStream { continuation in
                continuation.finish()
            }
        }
    ) {
        self.projectTrustService = projectTrustService
        self.projectTrustUpdatesProvider = projectTrustUpdates
    }

    nonisolated func cachedProjectTrustStatus(providerId: String, workingDirectory: String) -> Bool? {
        guard let providerID = AgentCLIKit.AgentProviderID(rawValue: providerId) else {
            return true
        }

        return Self.boolStatus(
            projectTrustService.cachedStatus(
                providerId: providerID,
                projectURL: projectURL(for: workingDirectory)
            )
        )
    }

    func projectTrustUpdates() async -> AsyncStream<Void> {
        await projectTrustUpdatesProvider()
    }

    func prepareForSpawn(providerId: String, workingDirectory: String, autoTrust: Bool) async {
        guard autoTrust,
              let providerID = AgentCLIKit.AgentProviderID(rawValue: providerId) else {
            return
        }

        try? await projectTrustService.trustProject(
            providerId: providerID,
            projectURL: projectURL(for: workingDirectory)
        )
    }

    func isTrustedProject(providerId: String, workingDirectory: String) async -> Bool {
        guard let providerID = AgentCLIKit.AgentProviderID(rawValue: providerId) else {
            return true
        }

        let status = await projectTrustService.status(
            providerId: providerID,
            projectURL: projectURL(for: workingDirectory)
        )
        return status.allowsProviderWork
    }

    func trustProject(providerId: String, workingDirectory: String) async {
        guard let providerID = AgentCLIKit.AgentProviderID(rawValue: providerId) else {
            return
        }

        try? await projectTrustService.trustProject(
            providerId: providerID,
            projectURL: projectURL(for: workingDirectory)
        )
    }
}

private extension DefaultProviderSetupService {
    nonisolated func projectURL(for workingDirectory: String) -> URL {
        URL(fileURLWithPath: CanonicalPath.normalize(workingDirectory), isDirectory: true)
    }

    static func boolStatus(_ status: AgentCLIKit.AgentProjectTrustStatus) -> Bool? {
        switch status {
        case .unknown:
            return nil
        case .trusted, .notRequired:
            return true
        case .notTrusted, .failed:
            return false
        }
    }
}
