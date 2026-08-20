import Foundation

/// Every transition the card's diff preview goes through: painted from cache, refreshed from
/// GitHub behind that paint, and invalidated when what it drew stops being true.
///
/// The preview state these mutate stays internal on the coordinator rather than `private(set)`
/// because Swift cannot scope a setter to two files; this file and the coordinator's own are its
/// only writers.
extension PullRequestReviewProposalCoordinator {
    /// Paints every pending card from its cached hunks, so a reopened thread shows the review it
    /// would publish rather than a loading caption while the refresh runs.
    ///
    /// Runs from every `reload()`, not once at init: propose time seeds the cache *then* posts the
    /// lifecycle notification, so the re-read that reload triggers is how the proposing session's
    /// own card finds its seed. Repainting is idempotent — the guard below skips every proposal
    /// that already holds anything newer than a cached paint.
    func loadCachedPreviews() {
        guard let previewCache else {
            return
        }
        // Cancel the predecessor: a read still in flight from an earlier reload could otherwise
        // land after an invalidation and repaint what the invalidation just dropped.
        previewCacheTask?.cancel()
        previewCacheTask = Task { @MainActor [weak self] in
            let entries = await previewCache.load()
            guard let self, !Task.isCancelled else {
                return
            }
            var painted = false
            for (proposalID, entry) in entries {
                guard let presentation = presentations[proposalID],
                      // An entry against a different pull request belongs to a superseded proposal
                      // that reused the id; painting it would show the wrong review's code.
                      presentation.identifier == entry.identifier,
                      // A refresh that landed while the file was being read is the newer truth.
                      previews[proposalID] == nil || previews[proposalID] == .loading else {
                    continue
                }
                previews[proposalID] = .loaded(Self.preview(from: entry, presentation: presentation))
                painted = true
            }
            if painted {
                notifyChanged()
            }
            // Chained behind the paint rather than run beside it: a refresh that failed first
            // would leave `.failed` in `previews`, which the guard above overwrites for neither
            // `nil` nor `.loading` — so the card would show an error in place of hunks already on
            // disk. A coordinator built without a cache therefore skips the launch warm entirely
            // and loads on render as it always did.
            warmPreviews()
        }
    }

    /// Starts every pending card's refresh without waiting for its thread to be opened, so opening
    /// one costs no `gh` round trip at all — a cold cache included, which is the case that used to
    /// leave a loading caption on screen for two of them.
    ///
    /// Every pending proposal warms, one at a time, newest first. Nothing under `fetchDetail` and
    /// `fetchDiff` limits concurrency, so warming them together would put a `gh` pair per
    /// unresolved proposal on the CPU at the moment of launch — and a proposal stays pending until
    /// it is confirmed or rejected, so how many there are is the user's to decide, not a bound.
    /// Serializing costs only latency, which is free here: no card is on screen waiting for it, and
    /// one that does appear calls `ensurePreview` from its own render rather than queuing behind
    /// this — so a warm working through older proposals never delays the card the user opened.
    ///
    /// Idempotent: `ensurePreview` skips anything already refreshed, so this only ever fetches for
    /// proposals that have not been, which is what lets `scheduleRemoteReload` call it to reload
    /// exactly what an announcement invalidated.
    private func warmPreviews() {
        previewWarmTask?.cancel()
        previewWarmTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            for proposal in presentations.values.sorted(by: { $0.createdAt > $1.createdAt }) {
                guard !Task.isCancelled else {
                    return
                }
                ensurePreview(proposalID: proposal.id)
                // Held as a value, because the load clears its own slot before it returns. Awaiting
                // it is not cancellable, which is wanted: a load already in flight should still
                // apply its result, and cancellation only has to stop the *next* one from starting.
                await previewTasks[proposal.id]?.value
            }
        }
    }

    /// Refreshes the card's diff preview once per proposal, whether or not a cached paint already
    /// filled it. The card is confirmable without it, so a failure is reported in place rather than
    /// blocking the decision.
    func ensurePreview(proposalID: String) {
        guard !refreshedProposalIDs.contains(proposalID),
              previewTasks[proposalID] == nil,
              let presentation = presentations[proposalID] else {
            return
        }
        // Marked before the task so a second render in the same frame cannot start a second
        // refresh. Safe to write mid-render only because the set is `@ObservationIgnored`.
        refreshedProposalIDs.insert(proposalID)
        // The transcript calls this while resolving card state mid-render, so the observable
        // `.loading` write waits for the task — an absent preview already renders as loading.
        //
        // Whoever cancels this task also clears its handle, and a cancelled run touches neither:
        // `addStagedComment` cancels an in-flight load, so a task that cleared the slot on its way
        // out would clobber the handle of the reload that replaced it.
        previewTasks[proposalID] = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else {
                return
            }
            // Only when there is nothing to show. Writing `.loading` over a cached paint would
            // flash the card back to its caption to reload what it is already displaying.
            if previews[proposalID] == nil {
                previews[proposalID] = .loading
            }
            let load = await loadPreview(for: presentation)
            guard !Task.isCancelled, presentations[proposalID] != nil else {
                return
            }
            previewTasks[proposalID] = nil
            applyRefresh(load, forProposalID: proposalID)
            // The loaded diff changes the card's height and body; without the notification the
            // transcript would keep rendering the loading state until something else invalidates.
            notifyChanged()
        }
    }

    /// Publishes a refresh and caches what it parsed.
    ///
    /// A failure keeps a preview already on screen: the hunks the user is reading are still the
    /// ones confirming would publish, so replacing them with an error banner would take content
    /// away to report a refresh they never asked for. With nothing painted, the failure shows.
    func applyRefresh(_ load: PullRequestReviewProposalPreviewLoad, forProposalID proposalID: String) {
        switch load.state {
        case .loaded:
            previews[proposalID] = load.state
        case .failed:
            if case .loaded = previews[proposalID] {
                break
            }
            previews[proposalID] = load.state
        case .loading:
            break
        }
        guard let entry = load.cacheEntry, let previewCache else {
            return
        }
        Task {
            await previewCache.save(entry, forProposalID: proposalID)
        }
    }

    /// Drops a card's preview and its refresh marker together, leaving the reload to whichever
    /// caller knows how soon it should run.
    ///
    /// The drop must not be answered by repainting from cache: the entry holds exactly the hunks
    /// that just stopped being true — the pre-force-push lines, or a narrowing that predates the
    /// comment `addStagedComment` staged, which a cached paint would report as unplaceable on a
    /// comment the user just wrote. So the card *is* blank until a reload lands, and the two
    /// callers differ on how to shorten that: a staged comment is one deliberate click and reloads
    /// at once, while announcements arrive in bursts and reload through `scheduleRemoteReload`.
    func invalidatePreview(proposalID: String) {
        previews[proposalID] = nil
        refreshedProposalIDs.remove(proposalID)
        previewTasks[proposalID]?.cancel()
        previewTasks[proposalID] = nil
    }

    /// Reloads what the announcements dropped, once for the whole burst.
    ///
    /// Debounced like `PullRequestsViewModel`'s own refetch and for the same reason: one
    /// address-feedback turn answers and resolves several threads in a row, and each is its own
    /// announcement — reloading per announcement would cost a `gh` detail-plus-diff pair each.
    /// Reloading at all, rather than waiting for the card's next render, is what keeps a thread
    /// the user is not looking at from opening on a loading caption once they return to it.
    private func scheduleRemoteReload() {
        remoteReloadTask?.cancel()
        let delay = remoteReloadDelay
        remoteReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else {
                return
            }
            // A cancelled run clears nothing: its handle already belongs to the schedule that
            // replaced it, matching `previewTasks` and the pane's own remote refreshes.
            remoteReloadTask = nil
            warmPreviews()
        }
    }

    /// A pull request that changed on GitHub invalidates the hunks its card drew. This matters more
    /// now that a preview survives relaunch: without it a force-push would leave stale lines on
    /// screen until the proposal was resolved. Skips this coordinator's own announcement, which it
    /// posts from `confirm` for a proposal it is about to clear.
    func invalidatePreviews(for notification: Notification) {
        guard (notification.object as AnyObject?) !== self,
              let announcement = notification.userInfo?[
                PullRequestChangeNotificationKey.announcement
              ] as? PullRequestChangeAnnouncement else {
            return
        }
        let affected = presentations
            .filter { $0.value.identifier == announcement.identifier }
            .map(\.key)
        guard !affected.isEmpty else {
            return
        }
        for proposalID in affected {
            invalidatePreview(proposalID: proposalID)
        }
        notifyChanged()
        scheduleRemoteReload()
    }
}
