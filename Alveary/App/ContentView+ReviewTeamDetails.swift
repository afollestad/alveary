import SwiftUI

struct ReviewTeamDetailsRequest: Identifiable {
    let run: ReviewTeamRun
    let reviewerID: String?
    var id: String { run.id }
}

extension ContentView {
    func reviewTeamDetailsSheetHost<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .reviewTeamDetailsRequested)) { notification in
                guard let run = notification.userInfo?["run"] as? ReviewTeamRun else { return }
                reviewTeamDetailsRequest = ReviewTeamDetailsRequest(
                    run: run, reviewerID: notification.userInfo?["reviewerID"] as? String
                )
            }
            .sheet(item: $reviewTeamDetailsRequest) { request in
                ReviewTeamRunDetailsSheet(
                    initialRun: request.run, coordinator: pullRequestReviewTeamCoordinator,
                    initialReviewerID: request.reviewerID
                ) {
                    reviewTeamDetailsRequest = nil
                }
            }
    }
}
