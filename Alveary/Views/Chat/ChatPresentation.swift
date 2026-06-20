import Foundation

// Presentation types are pure snapshots of chat display decisions. They should
// not own mutable conversation state, start tasks, save models, or call services;
// `ConversationViewModel` keeps that runtime ownership.
enum ChatContentMode: Equatable {
    case projectTrust(ProjectTrustPrompt)
    case projectTrustPlaceholder
    case emptyThread
    case transcript

    static func resolve(
        projectTrustPrompt: ProjectTrustPrompt?,
        isProjectTrustBlocked: Bool,
        hasVisibleChatContent: Bool
    ) -> ChatContentMode {
        if let projectTrustPrompt {
            return .projectTrust(projectTrustPrompt)
        }
        // The blank placeholder prevents a flash of empty-thread UI while trust
        // refresh is still deciding whether the composer/transcript should unlock.
        if isProjectTrustBlocked, !hasVisibleChatContent {
            return .projectTrustPlaceholder
        }
        if !hasVisibleChatContent {
            return .emptyThread
        }
        return .transcript
    }

    var transitionID: String {
        switch self {
        case .projectTrust(let prompt):
            return "projectTrust-\(prompt.threadID)"
        case .projectTrustPlaceholder:
            return "projectTrustPlaceholder"
        case .emptyThread:
            return "emptyThread"
        case .transcript:
            return "transcript"
        }
    }
}

enum ChatPresentation {
    static func hasVisibleChatContent(
        hasEvents: Bool,
        hasGroupedItems: Bool,
        hasStreamingText: Bool
    ) -> Bool {
        hasEvents || hasGroupedItems || hasStreamingText
    }

    static func composerMode(for state: ChatComposerModeState) -> ComposerMode {
        if state.isCancellingInitialSetup {
            return .progressOnly(.cancellingInitialSetup)
        }
        if state.hasSetupPhase {
            return .progressOnly(.initialSetup)
        }
        if state.isReconfiguringSession {
            return .progressOnly(.reconfiguringSession)
        }
        if state.isAwaitingHandoffSteering {
            return .idle
        }
        if state.isHandingOffSession {
            return .progressOnly(.sessionHandoff)
        }
        if state.isAwaitingExitPlanModeFollowUp {
            return .busy(canStop: false)
        }
        if let pendingToolApprovalStatusText = state.pendingToolApprovalStatusText {
            return .progressOnly(.toolApproval(pendingToolApprovalStatusText))
        }
        if state.isTurnActive || state.runtimeStatus == .busy {
            return .busy(canStop: true)
        }
        if state.isSendingMessage {
            return .busy(canStop: false)
        }
        return .idle
    }
}

struct ChatComposerModeState: Equatable, Sendable {
    let isCancellingInitialSetup: Bool
    let hasSetupPhase: Bool
    let isReconfiguringSession: Bool
    let isAwaitingHandoffSteering: Bool
    let isHandingOffSession: Bool
    let isAwaitingExitPlanModeFollowUp: Bool
    let pendingToolApprovalStatusText: DeferredToolComposerStatusText?
    let isTurnActive: Bool
    let runtimeStatus: ActivitySignal
    let isSendingMessage: Bool
}

// Reads SwiftData-backed thread fields into value state that SwiftUI and native
// AppKit chat views can share without duplicating render-branch logic.
struct ChatThreadPresentation: Equatable, Sendable {
    let selectedModel: String
    let selectedEffort: String
    let selectedSpeedMode: AgentSpeedMode
    let selectedPermissionMode: String
    let selectedPlanModeEnabled: Bool
    let selectedUseWorktree: Bool
    let showWorktreePicker: Bool
    let contextWindowCacheLookupID: String

    @MainActor
    init(
        thread: AgentThread?,
        providerID: String,
        runtimePermissionMode: String? = nil,
        pendingPermissionMode: String? = nil,
        runtimePlanModeEnabled: Bool? = nil,
        pendingPlanModeEnabled: Bool? = nil
    ) {
        selectedModel = thread?.model ?? AppSettings.defaultModelValue
        selectedEffort = AppSettings.normalizedEffortLevel(thread?.effort)
        selectedSpeedMode = thread?.normalizedSpeedMode ?? .standard
        selectedPermissionMode = Self.nonPlanPermissionMode(
            pendingPermissionMode ?? runtimePermissionMode ?? thread?.permissionMode,
            providerID: providerID,
            fallback: thread?.permissionMode
        )
        selectedPlanModeEnabled = pendingPlanModeEnabled ?? runtimePlanModeEnabled ?? thread?.planModeEnabled ?? false
        selectedUseWorktree = thread?.useWorktree ?? false

        if let thread,
           let project = thread.project,
           project.isGitRepository,
           !thread.hasCompletedInitialSetup {
            showWorktreePicker = true
        } else {
            showWorktreePicker = false
        }

        contextWindowCacheLookupID = "\(providerID):\(selectedModel)"
    }

    private static func nonPlanPermissionMode(_ mode: String?, providerID: String, fallback: String?) -> String {
        if let mode, mode != "plan" {
            return mode
        }
        if let fallback, fallback != "plan" {
            return fallback
        }
        return AppSettings.defaultPermissionMode(forProvider: providerID)
    }
}
