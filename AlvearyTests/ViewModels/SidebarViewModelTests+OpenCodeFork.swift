import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testOpenCodeForkUsesNilNativeEffortForConfiguredDefault() async throws {
        try await assertOpenCodeForkEffort(stored: AppSettings.openCodeDefaultEffort, native: nil)
    }

    func testOpenCodeForkDecodesEscapedNativeVariantExactlyOnce() async throws {
        let native = "alveary.opencode.variant:Y3VzdG9t"
        try await assertOpenCodeForkEffort(stored: AppSettings.openCodeStoredEffort(nativeVariant: native), native: native)
    }

    private func assertOpenCodeForkEffort(stored: String, native: String?) async throws {
        let setup = try projectForkSetup(harnessId: .opencode, sessionId: "ses_source")
        setup.thread.effort = stored
        setup.thread.model = "provider/model"
        setup.thread.permissionMode = "ask"
        try setup.fixture.context.save()

        let fork = try await setup.fixture.viewModel.forkThreadIntoLocal(setup.thread)

        let calls = await setup.fixture.agentsManager.spawnCalls()
        let appConfig = try XCTUnwrap(calls.first?.config)
        XCTAssertEqual(appConfig.harnessId, "opencode")
        XCTAssertEqual(appConfig.effort, native)
        XCTAssertEqual(appConfig.model, "provider/model")
        XCTAssertEqual(fork.effort, stored)
        XCTAssertEqual(setup.thread.effort, stored)
        let sdkConfig = try AgentCLIKitHostAdapter().spawnConfig(from: appConfig)
        XCTAssertEqual(sdkConfig.effort, native)
    }
}
