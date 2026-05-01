import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testChatComposerPanelErrorBannerWithRetryAction() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.lastTurnError = "Session handoff failed: the hidden handoff prompt returned no context."
        fixture.viewModel.state.failedSessionHandoffMessage = fixture.viewModel.lastTurnError

        assertMacSnapshot(
            ChatComposerPanelSnapshotView(
                viewModel: fixture.viewModel,
                composerCapabilities: composerPanelSnapshotCapabilities
            ),
            size: CGSize(width: 1000, height: 210),
            named: "chat_composer_panel_error_banner_retry",
            colorScheme: .dark
        )
    }

    func testChatComposerPanelWithoutBanners() throws {
        let fixture = try ConversationViewModelTestFixture()

        assertMacSnapshot(
            ChatComposerPanelSnapshotView(
                viewModel: fixture.viewModel,
                composerCapabilities: composerPanelSnapshotCapabilities
            ),
            size: CGSize(width: 1000, height: 150),
            named: "chat_composer_panel_without_banners",
            colorScheme: .dark
        )
    }

    private var composerPanelSnapshotCapabilities: ComposerCapabilities {
        ComposerCapabilities(
            supportedEffortLevels: ["low", "medium", "high"],
            supportedPermissionModes: samplePermissionModes,
            supportsMidTurnSteering: true
        )
    }
}

private struct ChatComposerPanelSnapshotView: View {
    let viewModel: ConversationViewModel
    let composerCapabilities: ComposerCapabilities

    @State private var selectedModel = "sonnet"
    @State private var selectedEffort = "medium"
    @State private var selectedPermissionMode = "default"
    @State private var selectedUseWorktree = false
    @State private var focusRequestToken: UUID?

    var body: some View {
        ChatComposerPanel(
            viewModel: viewModel,
            composerCapabilities: composerCapabilities,
            workingDirectory: "/tmp/alveary",
            showsTopDivider: true,
            composerMode: .idle,
            defaultEnterBehavior: .queue,
            composerIsBusy: false,
            isProjectTrustBlocked: false,
            selectedModel: $selectedModel,
            selectedEffort: $selectedEffort,
            selectedPermissionMode: $selectedPermissionMode,
            selectedUseWorktree: $selectedUseWorktree,
            showWorktreePicker: false,
            sessionLocationLabel: nil,
            usageSummary: nil,
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            onSubmit: {},
            onSteer: {},
            onStop: {},
            focusRequestToken: $focusRequestToken
        )
    }
}
