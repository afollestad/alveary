import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    private func makeAccessSheet(safariAccessible: Bool) -> PullRequestAttachmentAccessSheet {
        PullRequestAttachmentAccessSheet(
            onOpenSettings: {},
            onRetry: {},
            onCancel: {},
            probeSafariAccess: { safariAccessible }
        )
    }

    func testPullRequestAttachmentAccessSheet() {
        assertMacSnapshot(
            makeAccessSheet(safariAccessible: false),
            size: CGSize(width: 460, height: 480),
            named: "pull_request_attachment_access_sheet"
        )
    }

    // The green "Access granted" cue after the Full Disk Access toggle flips.
    func testPullRequestAttachmentAccessSheetGranted() {
        assertMacSnapshot(
            makeAccessSheet(safariAccessible: true),
            size: CGSize(width: 460, height: 480),
            named: "pull_request_attachment_access_sheet_granted"
        )
    }

    func testPullRequestAttachmentAccessSheetDark() {
        assertMacSnapshot(
            makeAccessSheet(safariAccessible: false),
            size: CGSize(width: 460, height: 480),
            named: "pull_request_attachment_access_sheet_dark",
            colorScheme: .dark
        )
    }
}
