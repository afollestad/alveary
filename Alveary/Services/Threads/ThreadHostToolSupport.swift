import Foundation

/// Execution folders and sidebar placement are independent. Only this frozen value crosses
/// provider discovery; changing the caller's project later must not retarget an inherited launch.
struct ThreadHostToolCreateWorkspace: Equatable {
    let snapshot: WorkspaceSnapshot
    let placement: TaskThreadSidebarPlacement
    var useWorktree: Bool?

    var kind: AgentThreadMode { snapshot.primarySource == nil ? .task : .project }
    var sectionID: String? {
        if case .section(let id) = placement { return id }
        return nil
    }

    var projectID: String? {
        if case .project(let id) = placement { return id }
        return nil
    }
}

/// Optional grants distinguish inheritance from an explicit replacement, including removal of all grants.
enum ThreadHostToolRequestedWorkspace: Equatable {
    case project(path: String, primaryFolderPath: String? = nil, grantedRoots: [String]? = nil, isID: Bool = false, privateWorkspace: Bool = false)
    case task(grantedRoots: [String]?, sectionName: String? = nil)
    case inherit(grantedRoots: [String]?, sectionName: String? = nil)
}

/// A `move_thread_to_section` request. Both fields are required — the tool never guesses which
/// thread or which section, because either guess would silently move the wrong row.
struct ThreadHostToolSectionMoveRequest: Equatable {
    let threadID: String
    let sectionName: String
}

/// Where the calling conversation's own thread lives and renders, as plain values. Snapshotted
/// before the defaults resolver's `await`, because an inherited placement must not read a
/// SwiftData model across that suspension.
struct ThreadHostToolSourcePlacement: Equatable {
    let mode: AgentThreadMode
    /// The caller's Project for a project-mode thread, or its sidebar-nesting project for a Task —
    /// either way the project a task-mode spawn naming no `section` nests under.
    let projectID: String?
    let snapshot: WorkspaceSnapshot?
    let useWorktree: Bool
    /// The caller's custom-section membership as a `SidebarSection.id` — what a task-mode spawn
    /// naming no `section` inherits. Mutually exclusive with `projectPath` on a Task.
    let sectionID: String?

    /// A Task's `project` is sidebar placement, not a workspace, so the mode decides alone.
    init(thread: AgentThread) {
        mode = thread.effectiveMode
        projectID = thread.project?.id
        snapshot = thread.workspaceSnapshot
        useWorktree = thread.useWorktree || thread.resolvedWorkspaceDescriptor?.ownershipStrategy == .projectWorktreeOwned
        sectionID = thread.customSection?.id
    }
}

/// The calling conversation's own provider, model, and effort, as plain values — snapshotted
/// beside `ThreadHostToolSourcePlacement` for the same pre-`await` reason. A `create_thread`
/// request that omits a setting inherits these, which is also what hands a scheduled run's
/// fan-out the task's own settings: the run's thread carries the schedule's snapshots.
struct ThreadHostToolSourceSettings: Equatable {
    let provider: String
    let model: String?
    let effort: String
}

/// A validated `create_thread` request. Every field here is already checked against trusted host
/// state; the handler only has to apply it. A `.task` workspace's granted roots are canonical
/// absolute folder paths by this point.
struct ThreadHostToolCreateRequest {
    let workspace: ThreadHostToolCreateWorkspace
    let name: String?
    let provider: String
    let model: String?
    let effort: String
    let permissionMode: String
    let initialPrompt: String?
    let pinned: Bool
}

/// A `create_thread` request as parsed, before any host-state validation, paired with the hash
/// that identifies an exact retry of it.
struct ThreadHostToolParsedCreateRequest {
    let workspace: ThreadHostToolRequestedWorkspace
    let name: String?
    let provider: String?
    let model: String?
    let effort: String?
    let permissionMode: String?
    let initialPrompt: String?
    let pinned: Bool?
    let canonicalPayloadHash: String
}

/// A `send_prompt_to_thread` request as parsed, paired with the hash that identifies an exact
/// retry of it. Whether the thread exists, may receive a prompt, or is the caller's own is host
/// state, so `ThreadHostToolService+SendPrompt.swift` decides.
struct ThreadHostToolParsedSendPromptRequest: Equatable {
    let threadID: String
    let prompt: String
    let canonicalPayloadHash: String
}

/// The message `send_prompt_to_thread` posts into its target. The visible text is the prompt
/// itself; the sender rides on the persisted row as `RelayedPromptAttribution`, which the
/// transcript renders as a note above the bubble, so the user can tell a relayed prompt from one
/// they typed without it reading as part of the prompt. The transport text adds the sender's
/// thread ID and how to answer, which only the model acts on. Nothing here carries attachments,
/// app shots, or plan guidance — those belong to whatever the target's own user is composing.
struct ThreadHostToolRelayedPrompt: Equatable {
    let prompt: String
    let senderName: String
    let senderThreadID: String

    /// Answering is conditional on purpose: an unconditional "reply with this tool" had two
    /// threads echoing one another, because each reply read as a prompt to answer.
    var transportText: String {
        "[Sent by the Alveary thread \"\(senderName)\" (thread_id: \(senderThreadID)) through send_prompt_to_thread. " +
            "That thread is not waiting on this turn. If this message asks for an answer, reply with " +
            "send_prompt_to_thread and that thread_id; otherwise do not acknowledge or echo it, and never answer " +
            "a reply that asks nothing.]\n\n\(prompt)"
    }

    var outbound: OutboundMessageText {
        OutboundMessageText(
            visibleText: prompt,
            transportText: transportText,
            relayedFrom: RelayedPromptAttribution(conversationID: senderThreadID, threadName: senderName)
        )
    }
}

/// A `link_pr` request. `threadID` omitted means the calling conversation's thread.
struct ThreadHostToolPullRequestLinkRequest {
    let identifier: PullRequestIdentifier
    let threadID: String?
}

/// An `unlink_pr` request. `identifier` omitted means the thread's only linked pull request, which
/// only the handler can resolve; `threadID` omitted means the calling conversation's thread.
struct ThreadHostToolPullRequestUnlinkRequest {
    let identifier: PullRequestIdentifier?
    let threadID: String?
}

/// One date rendering for every thread-tool timestamp (`modified_at`, `linked_at`), matching the
/// catalog's `dateTimeSchema`.
enum ThreadHostToolDates {
    static func canonical(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

enum ThreadHostToolServiceError: LocalizedError, Equatable {
    case unsupportedTool
    case listDoesNotAcceptArguments(toolName: String)
    case missingRequestIdentity
    case sourceConversationUnavailable
    case sourceProviderMismatch
    case projectNotRegistered(path: String)
    case grantedRootUnavailable(path: String)
    case sourcePlacementUnavailable
    case noReadyProvider
    case providerNotReady(providerID: String, ready: [String])
    case modelUnavailable(model: String)
    case effortUnavailable(effort: String, supported: [String])
    case permissionModeUnavailable(mode: String, providerID: String, supported: [String])
    case threadNotFound
    case threadArchived(name: String)
    case cannotArchiveOwnThread
    case cannotSendToOwnThread
    case relayEchoesPrompt(threadName: String)
    case relayRepeatsPrompt(threadName: String, count: Int)
    case promptDeliveryFailed(threadName: String, reason: String)
    case threadCannotBeArchived(reason: String)
    case threadAbsorbedByPinnedProject(projectName: String)
    case sectionUnknown(name: String, existing: [String])
    case sectionNotCustom(name: String)
    case invalidPullRequestURL(String)
    case ambiguousPullRequestUnlink(threadName: String, linked: [String])
    case pullRequestUnavailable(String)
    case persistenceFailure

    var errorDescription: String? {
        switch self {
        case .unsupportedTool:
            "This Alveary host tool is not available."
        case .listDoesNotAcceptArguments(let toolName):
            "\(toolName) does not accept arguments."
        case .missingRequestIdentity:
            "Alveary could not verify this thread request for safe retry handling."
        case .sourceConversationUnavailable:
            "Alveary thread tools require an active, saved Project or Task conversation."
        case .sourceProviderMismatch:
            "The thread request provider does not match its source conversation."
        case .projectNotRegistered(let path):
            "\(path) is not a Project in Alveary. Call list_projects and use its project_id. Shared folder paths require an explicit project_id."
        case .grantedRootUnavailable(let path):
            "\(path) cannot be granted to the new thread. Each granted_roots entry must be an " +
                "absolute path to a folder that already exists."
        case .sourcePlacementUnavailable:
            "Alveary cannot tell where this conversation's thread works, so the new thread's placement has to be " +
                "named: pass project_id, or mode \"task\"."
        case .noReadyProvider:
            "No Alveary provider is installed, enabled, and ready, so a new thread cannot be created."
        case let .providerNotReady(providerID, ready):
            "\(providerID) is not an installed, enabled, ready provider. Available: \(Self.list(ready))."
        case .modelUnavailable(let model):
            "\(model) is not a model this provider offers. Omit model to use the user's default."
        case let .effortUnavailable(effort, supported):
            "\(effort) is not a reasoning effort this model supports. Supported: \(Self.list(supported))."
        case let .permissionModeUnavailable(mode, providerID, supported):
            "\(mode) is not a permission mode \(providerID) supports. Supported: \(Self.list(supported))."
        case .threadNotFound:
            "That thread no longer exists. Call list_threads again."
        case .threadArchived(let name):
            "The thread \"\(name)\" is archived, so it cannot receive a prompt. The user can restore it from " +
                "Alveary's Archived screen."
        case .cannotArchiveOwnThread:
            "This conversation cannot archive its own thread. Ask the user to archive it from Alveary's sidebar."
        case .cannotSendToOwnThread:
            "This conversation cannot send a prompt to its own thread; it would only queue behind the turn making " +
                "this call. Continue the work here instead."
        case .relayEchoesPrompt(let threadName):
            "That is the prompt the thread \"\(threadName)\" just sent here. Never echo a relayed prompt back; reply " +
                "only with what it asked for, or end your turn."
        case let .relayRepeatsPrompt(threadName, count):
            "This conversation has already sent that exact prompt to the thread \"\(threadName)\" \(count) times " +
                "since the user last typed, so sending it again would only loop. Do not send it again; end your " +
                "turn and let the user decide."
        case let .promptDeliveryFailed(threadName, reason):
            "Alveary could not deliver the prompt to the thread \"\(threadName)\": \(reason)"
        case .threadCannotBeArchived(let reason):
            reason
        case .threadAbsorbedByPinnedProject(let projectName):
            "That thread cannot be pinned on its own because the pinned project \(projectName) already carries it. " +
                "Unpin the project first if the thread should be pinned separately."
        case .sectionUnknown(let name, let existing):
            "\(name) is not a sidebar section. Existing sections: \(existing.joined(separator: ", ")). " +
                "Call create_section first if it should exist."
        case .sectionNotCustom(let name):
            "\(name) is a built-in sidebar section, so threads cannot be moved into it. " +
                "Use Tasks to move a thread out of a custom section."
        case .invalidPullRequestURL(let url):
            "\(url) is not a GitHub pull request. Pass a URL like https://github.com/owner/repo/pull/123, " +
                "or the owner/repo#123 shorthand."
        case let .ambiguousPullRequestUnlink(threadName, linked):
            "The thread \"\(threadName)\" has \(linked.count) linked pull requests, so which one to unlink has to be " +
                "named: \(Self.list(linked)). Call unlink_pr again with one of them as url."
        case .pullRequestUnavailable(let reason):
            "Alveary could not reach that pull request on GitHub, so it was not linked: \(reason)"
        case .persistenceFailure:
            "Alveary could not read or save thread state."
        }
    }

    private static func list(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.joined(separator: ", ")
    }
}
