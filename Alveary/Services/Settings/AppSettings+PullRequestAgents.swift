import Foundation

/// Route-local overrides share resolution and picker rules without sharing persisted values.
struct PullRequestAgentSettings: Equatable {
    var provider: String?
    var model: String?
    var effort: String?
    var permissionMode: String?
}

extension AppSettings {
    var pullRequestReviewAgent: PullRequestAgentSettings {
        get {
            PullRequestAgentSettings(
                provider: pullRequestReviewProvider,
                model: pullRequestReviewModel,
                effort: pullRequestReviewEffort,
                permissionMode: pullRequestReviewPermissionMode
            )
        }
        set {
            pullRequestReviewProvider = newValue.provider
            pullRequestReviewModel = newValue.model
            pullRequestReviewEffort = newValue.effort
            pullRequestReviewPermissionMode = newValue.permissionMode
        }
    }

    var pullRequestAddressFeedbackAgent: PullRequestAgentSettings {
        get {
            PullRequestAgentSettings(
                provider: pullRequestAddressFeedbackProvider,
                model: pullRequestAddressFeedbackModel,
                effort: pullRequestAddressFeedbackEffort,
                permissionMode: pullRequestAddressFeedbackPermissionMode
            )
        }
        set {
            pullRequestAddressFeedbackProvider = newValue.provider
            pullRequestAddressFeedbackModel = newValue.model
            pullRequestAddressFeedbackEffort = newValue.effort
            pullRequestAddressFeedbackPermissionMode = newValue.permissionMode
        }
    }
}
