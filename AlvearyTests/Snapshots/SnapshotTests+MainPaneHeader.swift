import SwiftUI

@testable import Alveary

extension SnapshotTests {
    func testMainPaneHeaderPlainTitle() {
        assertMacSnapshot(
            MainPaneToolbarHeader(
                presentation: MainPaneHeaderPresentation(selection: .skills),
                onNewConversation: nil
            )
            .padding(8),
            size: CGSize(width: 180, height: 56),
            named: "main_pane_header_plain"
        )
    }

    func testMainPaneHeaderRichThreadTitleWithCreateButton() {
        let thread = AgentThread(name: "Fix `ContentView`", hasCompletedInitialSetup: true)

        assertMacSnapshot(
            MainPaneToolbarHeader(
                presentation: MainPaneHeaderPresentation(selection: .thread(thread)),
                onNewConversation: {}
            )
            .padding(8),
            size: CGSize(width: 260, height: 56),
            named: "main_pane_header_rich_thread"
        )
    }

    func testMainPaneHeaderLongThreadTitleKeepsCreateButtonVisible() {
        let thread = AgentThread(
            name: "Investigate `ContentView` and @/Users/alice/Development/Alveary/Alveary/App/ContentView.swift before release",
            hasCompletedInitialSetup: true
        )

        assertMacSnapshot(
            MainPaneToolbarHeader(
                presentation: MainPaneHeaderPresentation(selection: .thread(thread)),
                onNewConversation: {}
            )
            .padding(8),
            size: CGSize(width: 420, height: 56),
            named: "main_pane_header_long_thread"
        )
    }

    func testMainPaneHeaderDisabledCreateButton() {
        let thread = AgentThread(name: "Blocked thread", hasCompletedInitialSetup: true)

        assertMacSnapshot(
            MainPaneToolbarHeader(
                presentation: MainPaneHeaderPresentation(selection: .thread(thread)),
                onNewConversation: nil
            )
            .padding(8),
            size: CGSize(width: 240, height: 56),
            named: "main_pane_header_disabled_create"
        )
    }
}
