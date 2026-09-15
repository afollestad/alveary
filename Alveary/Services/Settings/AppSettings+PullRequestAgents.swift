import Foundation

/// Route-local overrides share resolution and picker rules without sharing persisted values.
struct PullRequestAgentSettings: Equatable {
    var harness: String?
    var model: String?
    var effort: String?
    var permissionMode: String?
}

extension AppSettings {
    var pullRequestReviewAgent: PullRequestAgentSettings {
        get {
            PullRequestAgentSettings(
                harness: pullRequestReviewHarness,
                model: pullRequestReviewModel,
                effort: pullRequestReviewEffort,
                permissionMode: pullRequestReviewPermissionMode
            )
        }
        set {
            pullRequestReviewHarness = newValue.harness
            pullRequestReviewModel = newValue.model
            pullRequestReviewEffort = newValue.effort
            pullRequestReviewPermissionMode = newValue.permissionMode
        }
    }

    var pullRequestAddressFeedbackAgent: PullRequestAgentSettings {
        get {
            PullRequestAgentSettings(
                harness: pullRequestAddressFeedbackHarness,
                model: pullRequestAddressFeedbackModel,
                effort: pullRequestAddressFeedbackEffort,
                permissionMode: pullRequestAddressFeedbackPermissionMode
            )
        }
        set {
            pullRequestAddressFeedbackHarness = newValue.harness
            pullRequestAddressFeedbackModel = newValue.model
            pullRequestAddressFeedbackEffort = newValue.effort
            pullRequestAddressFeedbackPermissionMode = newValue.permissionMode
        }
    }
}
