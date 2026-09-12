import Foundation

/// A same-process guard against replacing a proposal while a person edits or submits it.
struct PullRequestReviewProposalEditStateToken: Codable, Equatable, Sendable {
    let proposalID: String
    let processID: String
    let revision: Int
    let isSubmitting: Bool
}

/// App-scoped because proposal coordinators are window-scoped and every window can edit the same envelope.
@MainActor
enum PullRequestReviewProposalEditState {
    private static let processID = UUID().uuidString
    private static var revisions: [String: Int] = [:]
    private static var submittingProposalIDs: Set<String> = []

    static func current(proposalID: String) -> PullRequestReviewProposalEditStateToken? {
        guard let revision = revisions[proposalID] else {
            return nil
        }
        return PullRequestReviewProposalEditStateToken(
            proposalID: proposalID,
            processID: processID,
            revision: revision,
            isSubmitting: submittingProposalIDs.contains(proposalID)
        )
    }

    static func recordEdit(proposalID: String) {
        revisions[proposalID, default: 0] += 1
    }

    static func beginSubmission(proposalID: String) {
        revisions[proposalID, default: 0] += 1
        submittingProposalIDs.insert(proposalID)
    }

    static func endSubmission(proposalID: String) {
        revisions[proposalID, default: 0] += 1
        submittingProposalIDs.remove(proposalID)
    }

    /// A persisted token from another process carries no live edit state. Any token created in the
    /// current process, however, represents activity after relaunch and must still block replacement.
    static func isUnchanged(
        from expected: PullRequestReviewProposalEditStateToken?,
        to current: PullRequestReviewProposalEditStateToken?
    ) -> Bool {
        guard let expected else {
            return current == nil
        }
        guard expected.processID == processID else {
            return current == nil
        }
        return expected == current && current?.isSubmitting == false
    }
}
