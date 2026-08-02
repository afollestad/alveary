import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testAppKitTranscriptPullRequestPromptAssistantAligned() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptPullRequestPromptView()
                view.configure(Self.pullRequestPromptConfiguration(alignment: .leading))
                return view
            },
            size: CGSize(width: 640, height: 60),
            named: "appkit_transcript_pull_request_prompt_assistant"
        )
    }

    func testAppKitTranscriptPullRequestPromptUserAligned() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptPullRequestPromptView()
                view.configure(Self.pullRequestPromptConfiguration(alignment: .trailing))
                return view
            },
            size: CGSize(width: 640, height: 60),
            named: "appkit_transcript_pull_request_prompt_user"
        )
    }

    /// The menus only change which action the primary half runs, so the selected
    /// titles are the visible difference.
    func testAppKitTranscriptPullRequestPromptAlwaysAndNeverSelected() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptPullRequestPromptView()
                view.configure(
                    Self.pullRequestPromptConfiguration(
                        alignment: .leading,
                        selection: PullRequestLinkPromptSelection(acceptsAlways: true, declinesForever: true)
                    )
                )
                return view
            },
            size: CGSize(width: 640, height: 60),
            named: "appkit_transcript_pull_request_prompt_always_never"
        )
    }

    func testAppKitTranscriptPullRequestPromptDark() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptPullRequestPromptView()
                view.configure(Self.pullRequestPromptConfiguration(alignment: .leading))
                return view
            },
            size: CGSize(width: 640, height: 60),
            named: "appkit_transcript_pull_request_prompt_dark",
            colorScheme: .dark
        )
    }

    private static func pullRequestPromptConfiguration(
        alignment: AppKitTranscriptPullRequestPromptView.Alignment,
        selection: PullRequestLinkPromptSelection = PullRequestLinkPromptSelection()
    ) -> AppKitTranscriptPullRequestPromptView.Configuration {
        .init(
            promptID: "message-1|octo/alpha#42",
            displayKey: "octo/alpha#42",
            alignment: alignment,
            selection: selection,
            maxWidth: 560,
            typography: TranscriptTypography()
        )
    }
}
