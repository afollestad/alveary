import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testExplicitOpenCodeHarnessSelectionUsesNativeDefaults() throws {
        let fixture = try ConversationViewModelTestFixture(hasCompletedInitialSetup: false)
        fixture.viewModel.applyHarnessChange("opencode")
        XCTAssertEqual(fixture.conversation.harness, "opencode")
        XCTAssertEqual(fixture.thread.permissionMode, "ask")
        XCTAssertEqual(fixture.thread.effort, AppSettings.openCodeDefaultEffort)
        XCTAssertNil(try fixture.viewModel.makeSpawnConfig().effort)
    }

    func testOpenCodeRestoredGoalIsNotConvertedToOrdinaryMessage() async throws {
        let fixture = try openCodeFixture()
        fixture.viewModel.state.isGoalModeArmed = true
        do {
            try await fixture.viewModel.send("Complete the goal")
            XCTFail("Expected unsupported goal rejection")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("does not support goals"))
        }
        XCTAssertTrue(fixture.viewModel.state.isGoalModeArmed)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        let messages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(messages.isEmpty)
    }

    func testRestoredNativeOpenCodeBindingKeepsProviderAndCapabilityGates() async throws {
        let fixture = try openCodeFixture(imageSupport: true)
        fixture.conversation.harness = nil
        fixture.conversation.harnessSessionHarnessId = "opencode"
        fixture.settingsService.update { $0.defaultHarness = "claude" }
        XCTAssertEqual(try fixture.viewModel.makeSpawnConfig().harnessId, "opencode")
        XCTAssertFalse(fixture.viewModel.declaredHarnessFeatures.supportsGoalMode)
        fixture.thread.speedMode = "fast"
        fixture.viewModel.normalizeUnsupportedSpeedModeIfNeeded(supportsSpeedMode: false)
        XCTAssertEqual(fixture.thread.speedMode, "fast")
        fixture.thread.speedMode = "standard"
        let attachment = openCodeImage(label: "retain-restored.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]
        do {
            try await fixture.viewModel.queueOrSend("Describe", supportsLocalImageInput: false)
            XCTFail("Image transport cannot silently degrade to a file path")
        } catch {}
        XCTAssertEqual(fixture.viewModel.state.stagedImageAttachments, [attachment])
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testOpenCodeImagesRemainStagedWhenDiscoveryIsUnavailable() async throws {
        let fixture = try openCodeFixture()
        let attachment = openCodeImage(label: "retain.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]
        do {
            try await fixture.viewModel.queueOrSend("Describe", supportsLocalImageInput: false)
            XCTFail("Expected image capability rejection")
        } catch {}
        XCTAssertEqual(fixture.viewModel.state.stagedImageAttachments, [attachment])
        XCTAssertTrue(fixture.viewModel.state.messageQueue.pending.isEmpty)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testOpenCodeImageModelSendsAttachmentAndNativeDefaultEffort() async throws {
        let fixture = try openCodeFixture(imageSupport: true)
        let attachment = openCodeImage(label: "send.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]
        try await fixture.viewModel.send("Describe")
        let sent = await fixture.agentsManager.sentAttachments()
        XCTAssertEqual(sent, [[attachment]])
        XCTAssertNil(try fixture.viewModel.makeSpawnConfig().effort)
        XCTAssertTrue(fixture.viewModel.state.stagedImageAttachments.isEmpty)
    }

    func testOpenCodeQueuedImagesRejectChangedModelWithoutRemovingQueue() async throws {
        let fixture = try openCodeFixture(imageSupport: false)
        let attachment = openCodeImage(label: "queued.png")
        fixture.viewModel.state.messageQueue.enqueue("Describe", attachments: [attachment])
        fixture.viewModel.activateViewLifecycle()
        defer { fixture.viewModel.deactivateViewLifecycle() }
        fixture.viewModel.handleTurnCompleted()
        try await waitUntil("incompatible restored attachment rejection") {
            fixture.viewModel.lastTurnError != nil
        }
        XCTAssertTrue(fixture.viewModel.lastTurnError?.contains("supports images") == true)
        XCTAssertEqual(fixture.viewModel.state.messageQueue.peekNext()?.attachments, [attachment])
        let messages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(messages.isEmpty)
    }

    func testOpenCodeSavedFastModeIsPreservedAndBlockedUntilExplicitlyChanged() async throws {
        let fixture = try openCodeFixture()
        fixture.thread.speedMode = "fast"
        fixture.viewModel.state.runtimeSpeedMode = .fast
        fixture.viewModel.normalizeUnsupportedSpeedModeIfNeeded(supportsSpeedMode: false)
        XCTAssertEqual(fixture.thread.speedMode, "fast")
        do {
            try await fixture.viewModel.send("Continue")
            XCTFail("Expected unsupported Fast rejection")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Fast mode"))
        }
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        await fixture.viewModel.applySpeedModeChange(.standard).value
        XCTAssertEqual(fixture.thread.speedMode, "standard")
    }

    func testOpenCodeSavedReasoningVariantIsRejectedInsteadOfDiscarded() async throws {
        let fixture = try openCodeFixture(imageSupport: false)
        fixture.thread.effort = "unavailable-variant"
        do {
            try await fixture.viewModel.send("Continue")
            XCTFail("Expected unsupported variant rejection")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("unavailable-variant"))
        }
        XCTAssertEqual(fixture.thread.effort, "unavailable-variant")
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testOpenCodeSteeringDoesNotUsePendingVisionModelForNativeDefaultRuntime() async throws {
        let fixture = try openCodeFixture(imageSupport: true)
        fixture.viewModel.state.liveSessionConfig = AgentSpawnConfig(
            harnessId: "opencode", workingDirectory: fixture.project.path, permissionMode: "ask"
        )
        fixture.viewModel.state.turnState.beginTurn()
        let attachment = openCodeImage(label: "pending-model.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]
        do {
            try await fixture.viewModel.steer("Look at this")
            XCTFail("Native default is not verified image capable")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("supports images"))
        }
        XCTAssertEqual(fixture.viewModel.state.stagedImageAttachments, [attachment])
        let steers = await fixture.agentsManager.steeringCalls()
        XCTAssertTrue(steers.isEmpty)
    }

    func testOpenCodeContinuationPreservesSnapshotNativeDefaultsBeforeNextTurnSelection() throws {
        let fixture = try openCodeFixture()
        fixture.viewModel.state.liveSessionConfig = nil
        let original = fixture.viewModel.sessionSettingsSnapshot(for: fixture.thread)
        fixture.thread.model = "test/next-model"
        fixture.thread.effort = "next-variant"
        let pending = fixture.viewModel.sessionSettingsSnapshot(for: fixture.thread)
        fixture.viewModel.state.pendingSessionSettingsChange = .init(
            original: original, pending: pending, liveSessionConfig: nil
        )

        let continuation = try fixture.viewModel.makeSpawnConfig(settingsSource: .currentContinuation)
        XCTAssertNil(continuation.model)
        XCTAssertNil(continuation.effort)
        let nextTurn = try fixture.viewModel.makeSpawnConfig(settingsSource: .nextTurn)
        XCTAssertEqual(nextTurn.model, "test/next-model")
        XCTAssertEqual(nextTurn.effort, "next-variant")
    }

    func testOpenCodeAdmissionRepairsMissingWorktreeBeforeProjectDiscovery() async throws {
        let fixture = try openCodeFixture(imageSupport: true)
        fixture.thread.useWorktree = true
        fixture.thread.worktreePath = "/tmp/missing-opencode-worktree-\(UUID().uuidString)"
        fixture.thread.hasCompletedInitialSetup = true
        try await fixture.viewModel.validateOutboundCapabilities()
        XCTAssertNil(fixture.thread.worktreePath)
        XCTAssertFalse(fixture.thread.hasCompletedInitialSetup)
        let discovery = try XCTUnwrap(fixture.viewModel.harnessDiscovery as? RecordingHarnessDiscoveryService)
        let directories = await discovery.requestedProjectURLs
        XCTAssertEqual(directories.last, URL(fileURLWithPath: fixture.project.path, isDirectory: true))
    }

    private func openCodeFixture(imageSupport: Bool? = nil) throws -> ConversationViewModelTestFixture {
        let model = imageSupport.map { _ in "test/model" }
        let options = imageSupport.map { support in [AgentModelOption(
            harnessId: .opencode, id: "test/model", model: "test/model", label: "Test",
            metadata: [OpenCodeModelMetadata.supportsImageInput: .bool(support)]
        )] } ?? []
        let status = AgentHarnessStatus(
            harnessId: .opencode, definition: OpenCodeHarnessDefinition.definition,
            installation: .installed,
            availability: .init(harnessId: .opencode, executablePath: "/tmp/opencode"),
            setup: .ready, modelOptions: options
        )
        let fixture = try ConversationViewModelTestFixture(
            harnessId: "opencode", harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [.opencode: status])
        )
        fixture.thread.model = model
        fixture.thread.effort = AppSettings.openCodeDefaultEffort
        fixture.thread.permissionMode = "ask"
        fixture.viewModel.state.liveSessionConfig = try fixture.viewModel.makeSpawnConfig()
        return fixture
    }

    private func openCodeImage(label: String) -> LocalImageAttachment {
        LocalImageAttachment(
            id: UUID().uuidString, fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(label),
            label: label, createdAt: Date()
        )
    }
}
