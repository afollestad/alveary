import Foundation
import XCTest

@testable import Alveary

@MainActor
final class PullRequestLinksToolbarStateTests: XCTestCase {
    func testNoLinksShowsANeutralGlyphAndOpensThePopover() {
        let state = PullRequestLinksToolbarState(links: [])

        XCTAssertEqual(state.linkCount, 0)
        XCTAssertNil(state.status)
        XCTAssertFalse(state.opensPaneDirectly)
        XCTAssertEqual(state.helpText, "Link a pull request")
        XCTAssertEqual(state.accessibilityLabel, "Link a pull request")
        XCTAssertEqual(state.accessibilityValue, "None linked")
    }

    /// One link is the only case that can carry a status, and the only one whose
    /// primary action skips the popover.
    func testSingleLinkCarriesItsStatusAndOpensThePaneDirectly() {
        let state = PullRequestLinksToolbarState(links: [makeLink(number: 7, status: .merged)])

        XCTAssertEqual(state.linkCount, 1)
        XCTAssertEqual(state.status, .merged)
        XCTAssertTrue(state.opensPaneDirectly)
        XCTAssertEqual(state.helpText, "Open linked pull request")
        XCTAssertEqual(state.accessibilityLabel, "Open linked pull request")
        XCTAssertEqual(state.accessibilityValue, "1 linked, Merged pull request")
    }

    func testEveryStatusMapsToItsOwnGlyphAndTint() {
        let statuses: [PullRequestStatus] = [.open, .draft, .merged, .closed]
        let assetNames = statuses.map(PullRequestStatusGlyph.assetName(for:))

        XCTAssertEqual(assetNames, [
            "PullRequestOcticon",
            "PullRequestDraftOcticon",
            "PullRequestMergeOcticon",
            "PullRequestClosedOcticon"
        ])
        XCTAssertEqual(Set(assetNames).count, statuses.count)
        XCTAssertEqual(PullRequestStatusGlyph.tint(for: .open), .green)
        XCTAssertEqual(PullRequestStatusGlyph.tint(for: .draft), .secondary)
        XCTAssertEqual(PullRequestStatusGlyph.tint(for: .closed), .red)
    }

    /// With several linked, no single status describes the button, so it falls
    /// back to the neutral glyph and the popover disambiguates.
    func testMultipleLinksDropTheStatusAndOpenThePopover() {
        let state = PullRequestLinksToolbarState(links: [
            makeLink(number: 7, status: .merged),
            makeLink(number: 9, status: .open)
        ])

        XCTAssertEqual(state.linkCount, 2)
        XCTAssertNil(state.status)
        XCTAssertFalse(state.opensPaneDirectly)
        XCTAssertEqual(state.helpText, "2 linked pull requests")
        XCTAssertEqual(state.accessibilityValue, "2 linked")
    }

    private func makeLink(number: Int, status: PullRequestStatus) -> LinkedPullRequest {
        LinkedPullRequest(
            summary: makePullRequestSummary(number: number, status: status),
            linkedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
