import AppKit
import Foundation
import Observation

/// One window's side of ignoring pull requests: the "Show ignored" choice, the row and pane
/// actions, and the sheet that grants the `notifications` scope `updateSubscription` needs.
/// The ignore list itself is the app-scoped `PullRequestIgnoreService`; this owns only what
/// one window shows and asks.
///
/// **An action reads as done the moment it is asked for.** `actionOverrides` covers the hop
/// before the service marks it pending, and the time it spends parked behind the access sheet,
/// so a row never flickers back between the click and GitHub's answer. A failure removes the
/// override, which is the revert.
///
/// **The access flow explains before it launches anything.** A missing scope parks the action
/// on an `explain` request; only Continue starts `gh auth refresh`, and only Open GitHub opens
/// the browser. Success retries every parked action; Cancel reverts them all.
@MainActor @Observable
final class PullRequestIgnoreCoordinator {
    static let notificationsScope = "notifications"

    let ignoreService: PullRequestIgnoreService
    private(set) var showsIgnored: Bool
    /// The access sheet, presented once from the window root; nil when it is not up.
    private(set) var notificationsAccessRequest: PullRequestNotificationsAccessRequest?
    /// Actions this window asked for and has not seen finish: `true` ignores, `false` un-ignores.
    private(set) var actionOverrides: [PullRequestIdentifier: Bool] = [:]

    /// Non-nil only while this flow's `gh auth refresh` is running. `DefaultGitHubCLIService` has one
    /// device-flow process shared with sign-in, so stopping it when this flow never started one
    /// would kill a sign-in begun from Settings or onboarding.
    @ObservationIgnored private var accessTask: Task<Void, Never>?

    private let gitHubCLI: (any GitHubCLIService)?
    private let settingsService: (any SettingsService)?
    private let presentToast: @MainActor @Sendable (String) -> Void
    private let openURL: @MainActor (URL) -> Void
    private let copyToPasteboard: @MainActor (String) -> Void

    init(
        ignoreService: PullRequestIgnoreService,
        gitHubCLI: (any GitHubCLIService)? = nil,
        settingsService: (any SettingsService)? = nil,
        presentToast: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        copyToPasteboard: @escaping @MainActor (String) -> Void = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    ) {
        self.ignoreService = ignoreService
        self.gitHubCLI = gitHubCLI
        self.settingsService = settingsService
        self.presentToast = presentToast
        self.openURL = openURL
        self.copyToPasteboard = copyToPasteboard
        showsIgnored = settingsService?.current.pullRequestsShowIgnored ?? false
    }

    /// What the list treats as ignored: the service's set with this window's unfinished actions
    /// applied on top.
    var hiddenIDs: Set<PullRequestIdentifier> {
        var ids = ignoreService.effectiveIgnoredIDs
        for (id, ignoring) in actionOverrides {
            if ignoring {
                ids.insert(id)
            } else {
                ids.remove(id)
            }
        }
        return ids
    }

    func isIgnored(_ id: PullRequestIdentifier) -> Bool {
        if let ignoring = actionOverrides[id] {
            return ignoring
        }
        return ignoreService.effectiveIgnoredIDs.contains(id)
    }

    /// Whether a change for `id` is still on its way to GitHub, from any window.
    func isPending(_ id: PullRequestIdentifier) -> Bool {
        actionOverrides[id] != nil || ignoreService.pendingIDs.contains(id)
    }

    func setShowsIgnored(_ shows: Bool) {
        guard showsIgnored != shows else {
            return
        }
        showsIgnored = shows
        settingsService?.update { $0.pullRequestsShowIgnored = shows }
    }

    func ignore(_ id: PullRequestIdentifier) {
        start(PullRequestIgnoreAction(id: id, ignored: true))
    }

    func unignore(_ id: PullRequestIdentifier) {
        start(PullRequestIgnoreAction(id: id, ignored: false))
    }

    // MARK: - Notifications access

    /// From `explain`, Continue; nothing has run before this.
    func continueNotificationsAccess() {
        guard notificationsAccessRequest?.phase == .explain else {
            return
        }
        startAccessFlow()
    }

    func retryNotificationsAccess() {
        guard case .failed? = notificationsAccessRequest?.phase else {
            return
        }
        startAccessFlow()
    }

    /// The only thing that launches the browser.
    func openNotificationsAccessBrowser() {
        guard case .code(let deviceCode, _)? = notificationsAccessRequest?.phase else {
            return
        }
        openURL(deviceCode.verificationURL)
        notificationsAccessRequest?.phase = .code(deviceCode, didOpenBrowser: true)
    }

    func copyNotificationsAccessCode() {
        guard case .code(let deviceCode, _)? = notificationsAccessRequest?.phase else {
            return
        }
        copyToPasteboard(deviceCode.code)
    }

    /// Reverts every parked action, and stops `gh` if this flow started it.
    func cancelNotificationsAccess() {
        guard let request = notificationsAccessRequest else {
            return
        }
        if let accessTask {
            accessTask.cancel()
            self.accessTask = nil
            gitHubCLI?.cancelAuthentication()
        }
        for action in request.pendingActions {
            actionOverrides[action.id] = nil
        }
        notificationsAccessRequest = nil
    }

    // MARK: - Private

    private func start(_ action: PullRequestIgnoreAction) {
        guard !isPending(action.id) else {
            return
        }
        actionOverrides[action.id] = action.ignored
        Task {
            await perform(action)
        }
    }

    private func perform(_ action: PullRequestIgnoreAction) async {
        do {
            try await ignoreService.setIgnored(action.ignored, for: action.id)
            actionOverrides[action.id] = nil
        } catch PullRequestsServiceError.insufficientScopes {
            // The override stays: the row keeps its new state while the sheet asks.
            park(action)
        } catch {
            actionOverrides[action.id] = nil
            guard !(error is CancellationError) else {
                return
            }
            let verb = action.ignored ? "ignore" : "stop ignoring"
            presentToast("Couldn't \(verb) \(action.id.displayKey): \(error.localizedDescription)")
        }
    }

    private func park(_ action: PullRequestIgnoreAction) {
        guard var request = notificationsAccessRequest else {
            notificationsAccessRequest = PullRequestNotificationsAccessRequest(phase: .explain, pendingActions: [action])
            return
        }
        request.pendingActions.removeAll { $0.id == action.id }
        request.pendingActions.append(action)
        notificationsAccessRequest = request
    }

    private func startAccessFlow() {
        guard let gitHubCLI else {
            notificationsAccessRequest?.phase = .failed("The GitHub CLI isn't available.")
            return
        }
        accessTask?.cancel()
        notificationsAccessRequest?.phase = .requestingCode
        accessTask = Task {
            do {
                let deviceCode = try await gitHubCLI.refreshAuthentication(addingScopes: [Self.notificationsScope])
                guard !Task.isCancelled else {
                    return
                }
                notificationsAccessRequest?.phase = .code(deviceCode, didOpenBrowser: false)
                let didAuthorize = try await gitHubCLI.awaitAuthentication()
                guard !Task.isCancelled else {
                    return
                }
                if didAuthorize {
                    finishNotificationsAccess()
                } else {
                    failNotificationsAccess(
                        "GitHub didn't confirm the permission. Try again, or cancel to leave these pull requests as they were."
                    )
                }
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else {
                    return
                }
                failNotificationsAccess(error.localizedDescription)
            }
        }
    }

    /// `gh` has exited by now, so the flow no longer owns a process for Cancel to stop.
    private func failNotificationsAccess(_ message: String) {
        accessTask = nil
        notificationsAccessRequest?.phase = .failed(message)
    }

    /// Overrides stay in place through the retry, so the rows hold still while it runs.
    private func finishNotificationsAccess() {
        let actions = notificationsAccessRequest?.pendingActions ?? []
        notificationsAccessRequest = nil
        accessTask = nil
        for action in actions {
            Task {
                await perform(action)
            }
        }
    }
}

/// An ignore (`ignored`) or un-ignore the user asked for.
struct PullRequestIgnoreAction: Equatable, Sendable {
    let id: PullRequestIdentifier
    let ignored: Bool
}

/// The notifications-access sheet: where the flow is, and which actions wait on it.
struct PullRequestNotificationsAccessRequest: Equatable {
    enum Phase: Equatable {
        /// Why the permission is needed; nothing has launched yet.
        case explain
        /// `gh auth refresh` is starting and its code has not arrived.
        case requestingCode
        /// The code to enter on GitHub; `gh` is already polling for the approval.
        case code(GitHubDeviceCode, didOpenBrowser: Bool)
        case failed(String)
    }

    var phase: Phase
    var pendingActions: [PullRequestIgnoreAction]
}
