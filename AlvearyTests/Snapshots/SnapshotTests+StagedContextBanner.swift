import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testStagedContextBannerRestoreContext() {
        assertMacSnapshot(
            StagedContextBanner(
                context: """
                Restoring context from local history.
                This is a fresh provider session; do not assume memory from earlier turns.
                Conversation: Git status cleanup
                """,
                onDismiss: {}
            )
            .padding(24),
            size: CGSize(width: 760, height: 96),
            named: "staged_context_banner_restore_context"
        )
    }
}
