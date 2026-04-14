import Foundation
import SwiftData
import SwiftUI

struct ChatView: View {
    let viewModel: ConversationViewModel
    let conversation: Conversation
    let agentsManager: any AgentsManager
    let modelContext: ModelContext
    let diffViewModel: DiffViewerViewModel
    let composerCapabilities: ComposerCapabilities
    let workingDirectory: String?
    let loadFileCompletions: @Sendable () async -> [String]
    let loadSkillCompletions: @Sendable () async -> [Skill]
    @Bindable var appState: AppState

    @Query private var events: [ConversationEventRecord]
    @State private var lastScrollTime: Date = .distantPast
    @State private var isFollowing = true

    private var hasVisibleChatContent: Bool {
        !events.isEmpty || !viewModel.state.grouper.items.isEmpty || viewModel.streamingText != nil
    }

    private var showsCenteredPreHistoryRetry: Bool {
        !hasVisibleChatContent && viewModel.setupPhase == nil && viewModel.lastTurnError != nil
    }

    private var composerIsBusy: Bool {
        viewModel.turnState.isActive || viewModel.state.isSendingMessage
    }

    private var promptSubmissionIsBusy: Bool {
        composerIsBusy || viewModel.state.isReconfiguringSession
    }

    private var composerMode: ComposerMode {
        if !hasVisibleChatContent, viewModel.setupPhase != nil {
            return .progressOnly(.initialSetup)
        }
        if viewModel.state.isReconfiguringSession {
            return .progressOnly(.reconfiguringSession)
        }
        if viewModel.turnState.isActive {
            return .busy(canStop: true)
        }
        if viewModel.state.isSendingMessage {
            return .busy(canStop: false)
        }
        return .idle
    }

    private var canShowWriteEscalation: Bool {
        guard let suggestedMode = composerCapabilities.suggestedWriteEscalationMode,
              suggestedMode != selectedPermissionModeBinding.wrappedValue else {
            return false
        }

        return !viewModel.state.lastPermissionDeniedToolNames.isDisjoint(with: composerCapabilities.writeEscalationEligibleTools)
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { viewModel.state.selectedModel ?? "default" },
            set: { applyModelChange($0) }
        )
    }

    private var selectedEffortBinding: Binding<String> {
        Binding(
            get: { conversation.thread?.effort ?? "medium" },
            set: { applyEffortChange($0) }
        )
    }

    private var selectedPermissionModeBinding: Binding<String> {
        Binding(
            get: { conversation.thread?.permissionMode ?? "default" },
            set: { applyPermissionModeChange($0) }
        )
    }

    init(
        viewModel: ConversationViewModel,
        conversation: Conversation,
        agentsManager: any AgentsManager,
        modelContext: ModelContext,
        diffViewModel: DiffViewerViewModel,
        composerCapabilities: ComposerCapabilities,
        workingDirectory: String?,
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        appState: AppState
    ) {
        self.viewModel = viewModel
        self.conversation = conversation
        self.agentsManager = agentsManager
        self.modelContext = modelContext
        self.diffViewModel = diffViewModel
        self.composerCapabilities = composerCapabilities
        self.workingDirectory = workingDirectory
        self.loadFileCompletions = loadFileCompletions
        self.loadSkillCompletions = loadSkillCompletions
        self.appState = appState

        let conversationID = conversation.id
        _events = Query(
            filter: #Predicate { $0.conversationId == conversationID },
            sort: \.timestamp
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hasVisibleChatContent {
                EmptyThreadState(
                    showsRetryState: showsCenteredPreHistoryRetry,
                    setupPhase: viewModel.setupPhase,
                    error: showsCenteredPreHistoryRetry ? viewModel.lastTurnError : nil,
                    onRetry: retryDraft
                )
            } else {
                ChatTranscriptView(
                    viewModel: viewModel,
                    events: events,
                    promptSubmissionIsBusy: promptSubmissionIsBusy,
                    lastScrollTime: $lastScrollTime,
                    isFollowing: $isFollowing
                )
            }

            ChatComposerPanel(
                viewModel: viewModel,
                diffViewModel: diffViewModel,
                composerCapabilities: composerCapabilities,
                workingDirectory: workingDirectory,
                showsCenteredPreHistoryRetry: showsCenteredPreHistoryRetry,
                composerMode: composerMode,
                composerIsBusy: composerIsBusy,
                canShowWriteEscalation: canShowWriteEscalation,
                permissionEscalationLabel: permissionEscalationLabel,
                selectedModel: selectedModelBinding,
                selectedEffort: selectedEffortBinding,
                selectedPermissionMode: selectedPermissionModeBinding,
                loadFileCompletions: loadFileCompletions,
                loadSkillCompletions: loadSkillCompletions,
                onSubmit: sendDraft,
                onSteer: steerDraft,
                onStop: {
                    Task { await viewModel.cancel() }
                },
                onApplyPermissionModeChange: applyPermissionModeChange,
                appState: appState
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension ChatView {
    var permissionEscalationLabel: String {
        switch composerCapabilities.suggestedWriteEscalationMode {
        case "acceptEdits":
            return "Switch to Auto-Edit"
        case "auto":
            return "Switch to Auto"
        case "bypassPermissions":
            return "Switch to Auto-Approve"
        case let mode?:
            return "Switch to \(mode)"
        case nil:
            return "Update permissions"
        }
    }

    func retryDraft() {
        let message = viewModel.state.inputDraft
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let outboundMessage = outboundMessage(from: message)

        viewModel.state.inputDraft = ""
        Task {
            do {
                try await viewModel.queueOrSend(outboundMessage)
            } catch {
                viewModel.state.inputDraft = message
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = error.localizedDescription
                }
            }
        }
    }

    func sendDraft() {
        let message = viewModel.state.inputDraft
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let outboundMessage = outboundMessage(from: message)

        viewModel.state.inputDraft = ""
        Task {
            do {
                try await viewModel.queueOrSend(outboundMessage)
            } catch {
                viewModel.state.inputDraft = message
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = error.localizedDescription
                }
            }
        }
    }

    func steerDraft() {
        let message = viewModel.state.inputDraft
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let outboundMessage = outboundMessage(from: message)

        viewModel.state.inputDraft = ""
        Task {
            do {
                try await viewModel.steer(outboundMessage)
            } catch {
                viewModel.state.inputDraft = message
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = "Steer failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func applyModelChange(_ newValue: String) {
        let previousValue = viewModel.state.selectedModel ?? "default"
        guard previousValue != newValue else {
            return
        }

        viewModel.state.selectedModel = newValue == "default" ? nil : newValue
        viewModel.lastTurnError = nil

        Task { @MainActor in
            guard await agentsManager.isRunning(conversationId: conversation.id) else {
                return
            }

            do {
                try await viewModel.reconfigureSession()
            } catch {
                viewModel.state.selectedModel = previousValue == "default" ? nil : previousValue
                viewModel.lastTurnError = error.localizedDescription
            }
        }
    }

    func applyEffortChange(_ newValue: String) {
        guard let threadID = conversation.thread?.persistentModelID,
              let dbThread = modelContext.model(for: threadID) as? AgentThread else {
            return
        }

        let previousValue = dbThread.effort
        guard previousValue != newValue else {
            return
        }

        dbThread.effort = newValue
        viewModel.lastTurnError = nil

        do {
            try modelContext.save()
        } catch {
            dbThread.effort = previousValue
            viewModel.lastTurnError = error.localizedDescription
            return
        }

        Task { @MainActor in
            guard await agentsManager.isRunning(conversationId: conversation.id) else {
                return
            }

            do {
                try await viewModel.reconfigureSession()
            } catch {
                dbThread.effort = previousValue
                try? modelContext.save()
                viewModel.lastTurnError = error.localizedDescription
            }
        }
    }

    func applyPermissionModeChange(_ newValue: String) {
        guard let threadID = conversation.thread?.persistentModelID,
              let dbThread = modelContext.model(for: threadID) as? AgentThread else {
            return
        }

        let previousValue = dbThread.permissionMode
        guard previousValue != newValue else {
            return
        }

        let previousBannerVisibility = viewModel.state.showPermissionBanner
        let previousDeniedTools = viewModel.state.lastPermissionDeniedToolNames

        dbThread.permissionMode = newValue
        viewModel.lastTurnError = nil

        do {
            try modelContext.save()
        } catch {
            dbThread.permissionMode = previousValue
            viewModel.lastTurnError = error.localizedDescription
            return
        }

        Task { @MainActor in
            guard await agentsManager.isRunning(conversationId: conversation.id) else {
                viewModel.state.showPermissionBanner = false
                viewModel.state.lastPermissionDeniedToolNames = []
                return
            }

            do {
                try await viewModel.reconfigureSession()
            } catch {
                dbThread.permissionMode = previousValue
                try? modelContext.save()
                viewModel.state.showPermissionBanner = previousBannerVisibility
                viewModel.state.lastPermissionDeniedToolNames = previousDeniedTools
                viewModel.lastTurnError = error.localizedDescription
            }
        }
    }

    func outboundMessage(from message: String) -> String {
        guard message.contains("@") else {
            return message
        }

        let pattern = #"(^|[\s\(\[\{<"'])@([^\s\)\]\}>"']+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return message
        }

        let fullRange = NSRange(location: 0, length: (message as NSString).length)
        let matches = regex.matches(in: message, range: fullRange)
        guard !matches.isEmpty else {
            return message
        }

        let source = message as NSString
        let mutable = NSMutableString(string: message)
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else {
                continue
            }

            let prefix = source.substring(with: match.range(at: 1))
            let path = source.substring(with: match.range(at: 2))
            let normalizedPath = normalizedMentionPath(path)
            mutable.replaceCharacters(in: match.range, with: prefix + normalizedPath)
        }

        return mutable as String
    }

    func normalizedMentionPath(_ path: String) -> String {
        CanonicalPath.normalizeMentionPath(path, relativeTo: workingDirectory)
    }
}
