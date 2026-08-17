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
            guard let self, !Task.isCancelled, !entries.isEmpty else {
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

    /// Drops a card's preview and its refresh marker together, so the next render reloads it.
    func invalidatePreview(proposalID: String) {
        previews[proposalID] = nil
        refreshedProposalIDs.remove(proposalID)
        previewTasks[proposalID]?.cancel()
        previewTasks[proposalID] = nil
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
    }
}
