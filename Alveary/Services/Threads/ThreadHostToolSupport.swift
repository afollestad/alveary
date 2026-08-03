import Foundation

/// Where a requested thread will live. A Project thread works inside a registered Project; a Task
/// thread gets its own private workspace, so folder grants are the only way it reaches anything
/// else — which is why grants belong to this case alone.
enum ThreadHostToolCreateWorkspace: Equatable {
    case project(path: String)
    case task(grantedRoots: [String])

    var kind: AgentThreadMode {
        switch self {
        case .project:
            .project
        case .task:
            .task
        }
    }
}

/// The placement a `create_thread` request asked for, before host state resolves it. `inherit` is
/// what a request naming neither `mode` nor `project_path` means: wherever the calling thread
/// already works. Grants ride along with it because the parser cannot know which placement it
/// resolves to.
enum ThreadHostToolRequestedWorkspace: Equatable {
    case project(path: String)
    case task(grantedRoots: [String])
    case inherit(grantedRoots: [String])
}

/// Where the calling conversation's own thread lives, as plain values. Snapshotted before the
/// defaults resolver's `await`, because an inherited placement must not read a SwiftData model
/// across that suspension.
struct ThreadHostToolSourcePlacement: Equatable {
    let mode: AgentThreadMode
    let projectPath: String?

    /// A Task's `project` is sidebar placement, not a workspace, so the mode decides alone.
    init(thread: AgentThread) {
        mode = thread.effectiveMode
        projectPath = thread.project?.path
    }
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
    case automatedRunCannotManageThreads
    case projectNotRegistered(path: String)
    case grantedRootUnavailable(path: String)
    case grantsRequireTaskThread
    case sourcePlacementUnavailable
    case noReadyProvider
    case providerNotReady(providerID: String, ready: [String])
    case modelUnavailable(model: String)
    case effortUnavailable(effort: String, supported: [String])
    case permissionModeUnavailable(mode: String, providerID: String, supported: [String])
    case threadNotFound
    case cannotArchiveOwnThread
    case threadCannotBeArchived(reason: String)
    case threadAbsorbedByPinnedProject(projectName: String)
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
        case .automatedRunCannotManageThreads:
            "Automated scheduled runs cannot create or archive Alveary threads."
        case .projectNotRegistered(let path):
            "\(path) is not a Project in Alveary. Call list_projects and use one of its paths."
        case .grantedRootUnavailable(let path):
            "\(path) cannot be granted to the new thread. Each granted_roots entry must be an " +
                "absolute path to a folder that already exists."
        case .grantsRequireTaskThread:
            "granted_roots applies only to a task thread, and this conversation's thread works in a Project, which " +
                "the new thread inherits. Pass mode \"task\" to create a thread with its own private workspace instead."
        case .sourcePlacementUnavailable:
            "Alveary cannot tell where this conversation's thread works, so the new thread's placement has to be " +
                "named: pass project_path, or mode \"task\"."
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
            "That thread no longer exists. Call list_threads again before archiving."
        case .cannotArchiveOwnThread:
            "This conversation cannot archive its own thread. Ask the user to archive it from Alveary's sidebar."
        case .threadCannotBeArchived(let reason):
            reason
        case .threadAbsorbedByPinnedProject(let projectName):
            "That thread cannot be pinned on its own because the pinned project \(projectName) already carries it. " +
                "Unpin the project first if the thread should be pinned separately."
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
