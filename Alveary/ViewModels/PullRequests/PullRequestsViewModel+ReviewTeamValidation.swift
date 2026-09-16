import Foundation

/// Throws when any saved reviewer cannot resolve to a concrete launch configuration.
typealias PullRequestReviewTeamSettingsValidator = @MainActor @Sendable (AppSettings) async throws -> Void

/// The settings that can change strict review-team resolution; unrelated settings do not restart validation.
struct PullRequestReviewTeamSettingsSignature: Equatable, Sendable {
    let mode: PullRequestReviewMode
    let peers: [PullRequestReviewPeer]
    let defaultHarness: String
    let defaultModel: String
    let defaultEffort: String
    let disabledHarnessIDs: Set<String>
    let leadHarness: String?
    let leadModel: String?
    let leadEffort: String?

    init(settings: AppSettings) {
        mode = settings.pullRequestReviewMode
        peers = settings.pullRequestReviewPeers
        defaultHarness = settings.defaultHarness
        defaultModel = settings.defaultModel
        defaultEffort = settings.effort
        disabledHarnessIDs = settings.disabledHarnessIDs
        leadHarness = settings.pullRequestReviewHarness
        leadModel = settings.pullRequestReviewModel
        leadEffort = settings.pullRequestReviewEffort
    }
}

/// Lets tests release the deadline independently of a validator that ignores cancellation.
typealias PullRequestReviewTeamValidationSleeper = @MainActor @Sendable () async throws -> Void

/// Caches successful checks for unchanged settings across panes; actual review launches still run strict preflight.
extension PullRequestsViewModel {
    /// Keeps settings out of the memoized footer body while still reflecting changes immediately.
    func observePullRequestReviewSettings() {
        guard let settingsService else {
            return
        }
        pullRequestReviewSettingsObserver = NotificationCenter.default.addObserver(
            forName: .appSettingsChanged,
            object: settingsService,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPullRequestReviewConfiguration()
            }
        }
    }

    func endPullRequestReviewSettingsObservation() {
        guard let pullRequestReviewSettingsObserver else {
            return
        }
        NotificationCenter.default.removeObserver(pullRequestReviewSettingsObserver)
        self.pullRequestReviewSettingsObserver = nil
    }

    func retryReviewTeamValidation() {
        refreshPullRequestReviewConfiguration(force: true, refreshDiscovery: true)
    }

    /// Navigation reuses success without a TTL spinner. Failed checks still discover external CLI repairs on reopening.
    func refreshPullRequestReviewConfigurationForPane() {
        let refreshDiscovery: Bool
        switch mirroredReviewTeamValidationStatus {
        case .invalid, .failed:
            refreshDiscovery = true
        default:
            refreshDiscovery = false
        }
        refreshPullRequestReviewConfiguration(
            force: mirroredReviewTeamValidationStatus != .valid,
            refreshDiscovery: refreshDiscovery
        )
    }

    /// Relevant settings changes invalidate cached success; an identical in-flight check is always shared.
    func refreshPullRequestReviewConfiguration(force: Bool = false, refreshDiscovery: Bool = false) {
        let settings = settingsService?.current ?? AppSettings()
        let signature = PullRequestReviewTeamSettingsSignature(settings: settings)
        let signatureChanged = signature != reviewTeamSettingsSignature
        guard force || signatureChanged,
              signatureChanged || reviewTeamValidationToken == nil else {
            return
        }

        // Discovery snapshots include enablement; a newly enabled harness must not reuse its disabled snapshot.
        reviewTeamDiscoveryNeedsRefresh = reviewTeamDiscoveryNeedsRefresh
            || signature.disabledHarnessIDs != reviewTeamSettingsSignature.disabledHarnessIDs
        let needsDiscoveryRefresh = refreshDiscovery || reviewTeamDiscoveryNeedsRefresh
        reviewTeamSettingsSignature = signature
        cancelReviewTeamValidation()
        mirroredPullRequestReviewMode = settings.pullRequestReviewMode

        guard settings.pullRequestReviewMode == .reviewTeam else {
            mirroredReviewTeamValidationStatus = .notRequired
            mirrorPullRequestReviewConfiguration()
            return
        }

        guard let reviewTeamSettingsValidator else {
            mirroredReviewTeamValidationStatus = .unvalidated
            mirrorPullRequestReviewConfiguration()
            return
        }

        let token = UUID()
        reviewTeamValidationToken = token
        mirroredReviewTeamValidationStatus = .validating
        mirrorPullRequestReviewConfiguration()
        let refreshHarnesses = refreshReviewTeamHarnessDiscovery
        reviewTeamValidationTask = Task { [weak self] in
            let status: PullRequestReviewTeamValidationStatus
            do {
                try Task.checkCancellation()
                if needsDiscoveryRefresh {
                    await refreshHarnesses()
                    try Task.checkCancellation()
                    self?.finishReviewTeamDiscoveryRefresh(token: token)
                }
                try Task.checkCancellation()
                try await reviewTeamSettingsValidator(settings)
                try Task.checkCancellation()
                status = .valid
            } catch {
                status = error is CancellationError || Task.isCancelled
                    ? .failed("Review team check was interrupted. Try again.")
                    : .invalid(error.localizedDescription)
            }
            self?.finishReviewTeamValidation(status, token: token)
        }
        startReviewTeamValidationDeadline(token: token)
    }

    private func finishReviewTeamDiscoveryRefresh(token: UUID) {
        guard token == reviewTeamValidationToken else { return }
        reviewTeamDiscoveryNeedsRefresh = false
    }

    private func startReviewTeamValidationDeadline(token: UUID) {
        let sleep = reviewTeamValidationSleeper
        reviewTeamValidationDeadlineTask = Task { [weak self] in
            do {
                try await sleep()
                try Task.checkCancellation()
            } catch {
                return
            }
            self?.finishReviewTeamValidation(.failed("Review team check timed out. Try again."), token: token)
        }
    }

    /// Disown first so a cancelled or noncooperative task can never publish into a replacement attempt.
    func cancelReviewTeamValidation() {
        reviewTeamValidationToken = nil
        let validation = reviewTeamValidationTask
        let deadline = reviewTeamValidationDeadlineTask
        reviewTeamValidationTask = nil
        reviewTeamValidationDeadlineTask = nil
        validation?.cancel()
        deadline?.cancel()
    }

    /// A sibling deadline settles the UI without awaiting discovery, whose shared probe may ignore cancellation.
    /// Clearing the token also rejects late results before another attempt has started.
    private func finishReviewTeamValidation(
        _ status: PullRequestReviewTeamValidationStatus,
        token: UUID
    ) {
        guard token == reviewTeamValidationToken else {
            return
        }
        cancelReviewTeamValidation()
        mirroredReviewTeamValidationStatus = status
        mirrorPullRequestReviewConfiguration()
    }

    private func mirrorPullRequestReviewConfiguration() {
        for target in Array(paneSessions.keys) {
            mutateSession(target) { session in
                session.pullRequestReviewMode = mirroredPullRequestReviewMode
                session.pullRequestReviewTeamValidationStatus = mirroredReviewTeamValidationStatus
            }
        }
    }
}
