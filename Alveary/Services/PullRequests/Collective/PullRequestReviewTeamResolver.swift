import AgentCLIKit
import Foundation

enum PullRequestReviewTeamResolutionError: LocalizedError, Equatable, Sendable {
    case invalidTeamSize(Int)
    case duplicateMemberID(String)
    case harnessUnsupported(memberID: String, memberName: String, harnessID: String)
    case harnessUnavailable(memberID: String, memberName: String, harnessID: String)
    case modelUnavailable(memberID: String, memberName: String, harnessID: String, model: String)
    case effortUnavailable(memberID: String, memberName: String, effort: String)
    case executableUnavailable(memberID: String, memberName: String, harnessID: String)
    case duplicateModel(firstMemberID: String, firstMemberName: String, secondMemberID: String, secondMemberName: String)

    var errorDescription: String? {
        switch self {
        case .invalidTeamSize(let count):
            "Review teams need 2–5 reviewers; this team has \(count)."
        case .duplicateMemberID:
            "The review team contains duplicate saved reviewer identities."
        case .harnessUnsupported(_, let memberName, let harnessID):
            "\(memberName): \(HarnessFeaturePolicy.unavailableReviewMessage(harnessID: harnessID))"
        case .harnessUnavailable(_, let memberName, let harnessID):
            "\(memberName) uses \(harnessID), which is not ready."
        case .modelUnavailable(_, let memberName, _, let model):
            "\(memberName) uses \(model), which is not a concrete available model."
        case .effortUnavailable(_, let memberName, let effort):
            "\(memberName) uses \(effort), which the selected model does not support."
        case .executableUnavailable(_, let memberName, let harnessID):
            "\(memberName) cannot find the \(harnessID) executable."
        case .duplicateModel(_, let firstMemberName, _, let secondMemberName):
            "\(firstMemberName) and \(secondMemberName) use the same harness and model."
        }
    }
}

/// Resolves every member from one discovery snapshot, rejecting stale pins rather than substituting defaults.
struct PullRequestReviewTeamResolver: Sendable {
    private let harnessDiscovery: any AgentHarnessDiscoveryService

    init(harnessDiscovery: any AgentHarnessDiscoveryService) {
        self.harnessDiscovery = harnessDiscovery
    }

    func resolve(settings: AppSettings) async throws -> [ReviewWorkerConfiguration] {
        async let statuses = harnessDiscovery.harnessStatuses(projectURL: nil)
        async let ordering = harnessDiscovery.stableHarnessOrdering()
        let resolvedStatuses = await statuses
        let resolvedOrdering = await ordering
        return try Self.resolve(
            settings: settings,
            harnessStatuses: resolvedStatuses,
            harnessOrdering: resolvedOrdering.map(\.rawValue)
        )
    }

    static func resolve(
        settings: AppSettings,
        harnessStatuses: [AgentHarnessID: AgentHarnessStatus],
        harnessOrdering _: [String] = []
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
            let worker = try resolve(member: member, settings: settings, statuses: harnessStatuses)
            let selection = ModelSelection(harnessID: worker.harnessID, launchModel: worker.launchModel)
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
        harnessStatuses: [AgentHarnessID: AgentHarnessStatus]
    ) throws -> ReviewWorkerConfiguration {
        try resolve(member: lead(from: settings), settings: settings, statuses: harnessStatuses)
    }
}

private extension PullRequestReviewTeamResolver {
    struct Member {
        let id: String
        let name: String
        let harnessID: String
        let model: String
        let effort: String

        static func peer(_ peer: PullRequestReviewPeer, index: Int) -> Member {
            Member(
                id: peer.id,
                name: "Reviewer \(index + 2)",
                harnessID: peer.harnessID,
                model: peer.model,
                effort: peer.effort
            )
        }
    }

    struct ModelSelection: Hashable {
        let harnessID: String
        let launchModel: String
    }

    struct ResolvedModel {
        let option: AgentModelOption
        let launchModel: String
    }

    static func lead(from settings: AppSettings) -> Member {
        let harnessID = settings.pullRequestReviewHarness ?? settings.defaultHarness
        let inheritsDefaults = harnessID == settings.defaultHarness
        return Member(
            id: "lead",
            name: "Lead",
            harnessID: harnessID,
            model: settings.pullRequestReviewModel
                ?? (inheritsDefaults ? settings.defaultModel : nil)
                ?? AppSettings.defaultModelValue,
            effort: settings.pullRequestReviewEffort
                ?? (inheritsDefaults ? settings.effort : harnessID == "opencode"
                    ? AppSettings.openCodeDefaultEffort : AppSettings.defaultEffortLevel)
        )
    }

    static func resolve(
        member: Member,
        settings: AppSettings,
        statuses: [AgentHarnessID: AgentHarnessStatus]
    ) throws -> ReviewWorkerConfiguration {
        guard HarnessFeaturePolicy.supportsIsolatedReviewWorkers(harnessID: member.harnessID) else {
            throw PullRequestReviewTeamResolutionError.harnessUnsupported(
                memberID: member.id, memberName: member.name, harnessID: member.harnessID
            )
        }
        guard let harnessID = AgentHarnessID(rawValue: member.harnessID),
              let status = statuses[harnessID],
              settings.isHarnessEnabled(member.harnessID),
              status.isEnabled,
              status.isInstalled,
              status.isSetupReady else {
            throw PullRequestReviewTeamResolutionError.harnessUnavailable(
                memberID: member.id,
                memberName: member.name,
                harnessID: member.harnessID
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
                harnessID: member.harnessID
            )
        }
        return ReviewWorkerConfiguration(
            id: member.id,
            harnessID: member.harnessID,
            modelOptionID: model.option.id,
            launchModel: model.launchModel,
            effort: effort,
            executablePath: executablePath
        )
    }

    static func resolvedModel(member: Member, status: AgentHarnessStatus) throws -> ResolvedModel {
        let exactOption = status.modelOptions.first {
            ($0.id == member.model || $0.model == member.model) && Self.concreteLaunchModel($0) != nil
        }
        let defaultOption = member.harnessID != "opencode" && member.model == AppSettings.defaultModelValue
            ? status.modelOptions.first(where: { $0.isDefault && Self.concreteLaunchModel($0) != nil })
            : nil
        guard let option = exactOption ?? defaultOption,
              let launchModel = concreteLaunchModel(option) else {
            throw PullRequestReviewTeamResolutionError.modelUnavailable(
                memberID: member.id,
                memberName: member.name,
                harnessID: member.harnessID,
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
        if member.harnessID == "opencode" {
            if requested == AppSettings.openCodeDefaultEffort { return requested }
            if let variant = AppSettings.openCodeNativeEffort(stored: requested),
               supported.contains(where: { $0.value == variant }) {
                return AppSettings.openCodeStoredEffort(nativeVariant: variant)
            }
        }
        guard !requested.isEmpty,
              member.harnessID != "opencode",
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
