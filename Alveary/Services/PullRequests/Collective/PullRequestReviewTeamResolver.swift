import AgentCLIKit
import Foundation

enum PullRequestReviewTeamResolutionError: LocalizedError, Equatable, Sendable {
    case invalidTeamSize(Int)
    case duplicateMemberID(String)
    case providerUnavailable(memberID: String, memberName: String, providerID: String)
    case modelUnavailable(memberID: String, memberName: String, providerID: String, model: String)
    case effortUnavailable(memberID: String, memberName: String, effort: String)
    case executableUnavailable(memberID: String, memberName: String, providerID: String)
    case duplicateModel(firstMemberID: String, firstMemberName: String, secondMemberID: String, secondMemberName: String)

    var errorDescription: String? {
        switch self {
        case .invalidTeamSize(let count):
            "Review teams need 2–5 reviewers; this team has \(count)."
        case .duplicateMemberID:
            "The review team contains duplicate saved reviewer identities."
        case .providerUnavailable(_, let memberName, let providerID):
            "\(memberName) uses \(providerID), which is not ready."
        case .modelUnavailable(_, let memberName, _, let model):
            "\(memberName) uses \(model), which is not a concrete available model."
        case .effortUnavailable(_, let memberName, let effort):
            "\(memberName) uses \(effort), which the selected model does not support."
        case .executableUnavailable(_, let memberName, let providerID):
            "\(memberName) cannot find the \(providerID) executable."
        case .duplicateModel(_, let firstMemberName, _, let secondMemberName):
            "\(firstMemberName) and \(secondMemberName) use the same agent and model."
        }
    }
}

/// Resolves every member from one discovery snapshot, rejecting stale pins rather than substituting defaults.
struct PullRequestReviewTeamResolver: Sendable {
    private let providerDiscovery: any AgentProviderDiscoveryService

    init(providerDiscovery: any AgentProviderDiscoveryService) {
        self.providerDiscovery = providerDiscovery
    }

    func resolve(settings: AppSettings) async throws -> [ReviewWorkerConfiguration] {
        async let statuses = providerDiscovery.providerStatuses(projectURL: nil)
        async let ordering = providerDiscovery.stableProviderOrdering()
        let resolvedStatuses = await statuses
        let resolvedOrdering = await ordering
        return try Self.resolve(
            settings: settings,
            providerStatuses: resolvedStatuses,
            providerOrdering: resolvedOrdering.map(\.rawValue)
        )
    }

    static func resolve(
        settings: AppSettings,
        providerStatuses: [AgentProviderID: AgentProviderStatus],
        providerOrdering _: [String] = []
    ) throws -> [ReviewWorkerConfiguration] {
        let peers = settings.pullRequestReviewPeers.enumerated().map { index, peer in
            Member.peer(peer, index: index)
        }
        let members = [lead(from: settings)] + peers
        guard (2...5).contains(members.count) else {
            throw PullRequestReviewTeamResolutionError.invalidTeamSize(members.count)
        }

        var memberIDs = Set<String>()
        var selections: [ModelSelection: Member] = [:]
        var workers: [ReviewWorkerConfiguration] = []
        for member in members {
            guard memberIDs.insert(member.id).inserted else {
                throw PullRequestReviewTeamResolutionError.duplicateMemberID(member.id)
            }
            let worker = try resolve(member: member, settings: settings, statuses: providerStatuses)
            let selection = ModelSelection(providerID: worker.providerID, launchModel: worker.launchModel)
            if let firstMember = selections[selection] {
                throw PullRequestReviewTeamResolutionError.duplicateModel(
                    firstMemberID: firstMember.id,
                    firstMemberName: firstMember.name,
                    secondMemberID: member.id,
                    secondMemberName: member.name
                )
            }
            selections[selection] = member
            workers.append(worker)
        }
        return workers
    }

    static func resolveLead(
        settings: AppSettings,
        providerStatuses: [AgentProviderID: AgentProviderStatus]
    ) throws -> ReviewWorkerConfiguration {
        try resolve(member: lead(from: settings), settings: settings, statuses: providerStatuses)
    }
}

private extension PullRequestReviewTeamResolver {
    struct Member {
        let id: String
        let name: String
        let providerID: String
        let model: String
        let effort: String

        static func peer(_ peer: PullRequestReviewPeer, index: Int) -> Member {
            Member(
                id: peer.id,
                name: "Reviewer \(index + 2)",
                providerID: peer.providerID,
                model: peer.model,
                effort: peer.effort
            )
        }
    }

    struct ModelSelection: Hashable {
        let providerID: String
        let launchModel: String
    }

    struct ResolvedModel {
        let option: AgentModelOption
        let launchModel: String
    }

    static func lead(from settings: AppSettings) -> Member {
        let providerID = settings.pullRequestReviewProvider ?? settings.defaultProvider
        let inheritsDefaults = providerID == settings.defaultProvider
        return Member(
            id: "lead",
            name: "Lead",
            providerID: providerID,
            model: settings.pullRequestReviewModel
                ?? (inheritsDefaults ? settings.defaultModel : nil)
                ?? AppSettings.defaultModelValue,
            effort: settings.pullRequestReviewEffort
                ?? (inheritsDefaults ? settings.effort : AppSettings.defaultEffortLevel)
        )
    }

    static func resolve(
        member: Member,
        settings: AppSettings,
        statuses: [AgentProviderID: AgentProviderStatus]
    ) throws -> ReviewWorkerConfiguration {
        guard let providerID = AgentProviderID(rawValue: member.providerID),
              let status = statuses[providerID],
              settings.isProviderEnabled(member.providerID),
              status.isEnabled,
              status.isInstalled,
              status.isSetupReady else {
            throw PullRequestReviewTeamResolutionError.providerUnavailable(
                memberID: member.id,
                memberName: member.name,
                providerID: member.providerID
            )
        }
        let model = try resolvedModel(member: member, status: status)
        let effort = try resolvedEffort(member: member, model: model)
        guard let executablePath = status.availability?.executablePath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !executablePath.isEmpty else {
            throw PullRequestReviewTeamResolutionError.executableUnavailable(
                memberID: member.id,
                memberName: member.name,
                providerID: member.providerID
            )
        }
        return ReviewWorkerConfiguration(
            id: member.id,
            providerID: member.providerID,
            modelOptionID: model.option.id,
            launchModel: model.launchModel,
            effort: effort,
            executablePath: executablePath
        )
    }

    static func resolvedModel(member: Member, status: AgentProviderStatus) throws -> ResolvedModel {
        let exactOption = status.modelOptions.first {
            ($0.id == member.model || $0.model == member.model) && Self.concreteLaunchModel($0) != nil
        }
        let defaultOption = member.model == AppSettings.defaultModelValue
            ? status.modelOptions.first(where: { $0.isDefault && Self.concreteLaunchModel($0) != nil })
            : nil
        guard let option = exactOption ?? defaultOption,
              let launchModel = concreteLaunchModel(option) else {
            throw PullRequestReviewTeamResolutionError.modelUnavailable(
                memberID: member.id,
                memberName: member.name,
                providerID: member.providerID,
                model: member.model
            )
        }
        return ResolvedModel(option: option, launchModel: launchModel)
    }

    static func resolvedEffort(
        member: Member,
        model: ResolvedModel
    ) throws -> String {
        let requested = member.effort.trimmingCharacters(in: .whitespacesAndNewlines)
        let supported = model.option.supportedEffortOptions
        guard !requested.isEmpty,
              !supported.isEmpty,
              supported.contains(where: { $0.value == requested }) else {
            throw PullRequestReviewTeamResolutionError.effortUnavailable(
                memberID: member.id,
                memberName: member.name,
                effort: member.effort
            )
        }
        return requested
    }

    static func concreteLaunchModel(_ option: AgentModelOption) -> String? {
        guard let model = option.model?.trimmingCharacters(in: .whitespacesAndNewlines),
              !model.isEmpty,
              model.lowercased() != AppSettings.defaultModelValue else {
            return nil
        }
        return model
    }
}
