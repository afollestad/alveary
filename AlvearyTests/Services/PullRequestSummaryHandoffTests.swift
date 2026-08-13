import Foundation
import XCTest

@testable import Alveary

@MainActor
final class PullRequestSummaryHandoffTests: XCTestCase {
    func testARecordedSummaryComesBackByIdentifierAndUnknownsAreNil() {
        let handoff = PullRequestSummaryHandoff(now: { Date(timeIntervalSince1970: 0) })
        let summary = makePullRequestSummary(number: 7, isReviewRequested: true)

        handoff.record([summary])

        XCTAssertEqual(handoff.summary(for: summary.id), summary)
        XCTAssertNil(handoff.summary(for: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 8)))
    }

    func testASummaryExpiresAfterTheMaxAge() {
        var clock = Date(timeIntervalSince1970: 0)
        let handoff = PullRequestSummaryHandoff(now: { clock }, maxAge: 60)
        let summary = makePullRequestSummary(number: 7)
        handoff.record([summary])

        clock = Date(timeIntervalSince1970: 59)
        XCTAssertEqual(handoff.summary(for: summary.id), summary)

        clock = Date(timeIntervalSince1970: 60)
        XCTAssertNil(handoff.summary(for: summary.id))
    }

    /// A later list refreshes both the row and its clock, so paging through a long backlog keeps
    /// the earliest pages alive for as long as the model is still working through them.
    func testReRecordingReplacesTheRowAndRestartsItsClock() {
        var clock = Date(timeIntervalSince1970: 0)
        let handoff = PullRequestSummaryHandoff(now: { clock }, maxAge: 60)
        handoff.record([makePullRequestSummary(number: 7, title: "First page")])

        clock = Date(timeIntervalSince1970: 40)
        let refreshed = makePullRequestSummary(number: 7, title: "Refetched")
        handoff.record([refreshed])

        clock = Date(timeIntervalSince1970: 80)
        XCTAssertEqual(handoff.summary(for: refreshed.id)?.title, "Refetched")
    }
}
