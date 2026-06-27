import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerDraftTests {
    func testFastCommandFailureRestoresStagedAppShotAttachment() async throws {
        let root = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let screenshotURL = root.appendingPathComponent("appshot.png")
        try Self.pngHeaderData.write(to: screenshotURL)
        let screenshot = LocalImageAttachment(
            id: "appshot-image",
            fileURL: screenshotURL,
            label: "appshot.png",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let appShot = AppShotAttachment(
            id: "appshot",
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "Preview - Document.pdf",
            screenshot: screenshot,
            axTreeText: "AX tree",
            focusedElementSummary: "",
            attachmentStoreRoot: root
        )
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        await fixture.agentsManager.enqueueSendResult(.failure(.sendFailed))
        fixture.viewModel.state.runtimeSpeedMode = .standard
        fixture.viewModel.state.stagedAppShots = [appShot]
        fixture.viewModel.replaceInputDraft("/fast Fix the tests", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            supportsSpeedMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertNotNil(appState.pendingComposerFocusToken)
        try await waitUntil("expected fast command send failure") {
            fixture.viewModel.lastTurnError != nil
        }
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Fix the tests")
        XCTAssertEqual(fixture.viewModel.state.stagedAppShots, [appShot])
    }
}
