import AgentCLIKit
import Foundation

actor DefaultHarnessSetupService: HarnessSetupService {
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

    nonisolated func cachedProjectTrustStatus(harnessId: String, workingDirectory: String) -> Bool? {
        guard let harnessID = AgentCLIKit.AgentHarnessID(rawValue: harnessId) else {
            return true
        }

        return Self.boolStatus(
            projectTrustService.cachedStatus(
                harnessId: harnessID,
                projectURL: projectURL(for: workingDirectory)
            )
        )
    }

    func projectTrustUpdates() async -> AsyncStream<Void> {
        await projectTrustUpdatesProvider()
    }

    func prepareForSpawn(harnessId: String, workingDirectory: String, autoTrust: Bool) async {
        guard autoTrust,
              let harnessID = AgentCLIKit.AgentHarnessID(rawValue: harnessId) else {
            return
        }

        try? await projectTrustService.trustProject(
            harnessId: harnessID,
            projectURL: projectURL(for: workingDirectory)
        )
    }

    func isTrustedProject(harnessId: String, workingDirectory: String) async -> Bool {
        guard let harnessID = AgentCLIKit.AgentHarnessID(rawValue: harnessId) else {
            return true
        }

        let status = await projectTrustService.status(
            harnessId: harnessID,
            projectURL: projectURL(for: workingDirectory)
        )
        return status.allowsHarnessWork
    }

    func trustProject(harnessId: String, workingDirectory: String) async {
        guard let harnessID = AgentCLIKit.AgentHarnessID(rawValue: harnessId) else {
            return
        }

        try? await projectTrustService.trustProject(
            harnessId: harnessID,
            projectURL: projectURL(for: workingDirectory)
        )
    }
}

private extension DefaultHarnessSetupService {
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
