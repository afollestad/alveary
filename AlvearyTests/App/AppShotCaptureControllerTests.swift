import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class AppShotCaptureControllerTests: XCTestCase {
    func testSelectedRealThreadStagesIntoSelectedSecondaryConversationBeforeViewMounts() async throws {
        let fixture = try AppShotCaptureControllerFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-secondary")
        let seeded = try fixture.insertThread(
            name: "Feature work",
            project: project,
            conversationIDs: ["main", "secondary"]
        )
        let secondary = try XCTUnwrap(seeded.conversations.last)
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)
        fixture.appState.selectConversation(secondary, in: seeded.thread)

        await fixture.runCapture()

        let secondaryState = fixture.runtimeStore.conversationState(for: secondary.id)
        let stagedAppShot = try XCTUnwrap(secondaryState.stagedAppShots.first)
        XCTAssertFalse(secondaryState.isViewMounted)
        XCTAssertEqual(secondaryState.stagedAppShots.count, 1)
        XCTAssertFalse(secondaryState.inputDraftIsEffectivelyEmpty)
        XCTAssertEqual(stagedAppShot.appName, "Preview")
        XCTAssertEqual(stagedAppShot.bundleIdentifier, "com.apple.Preview")
        XCTAssertEqual(stagedAppShot.windowTitle, "Document")
        XCTAssertEqual(stagedAppShot.axTreeText, "standard window Document")
        XCTAssertEqual(stagedAppShot.focusedElementSummary, "button Open")
        XCTAssertEqual(
            stagedAppShot.attachmentStoreRoot,
            fixture.attachmentStore.conversationRootDirectory(conversationId: secondary.id)
        )
        XCTAssertTrue(fixture.runtimeStore.conversationState(for: "main").stagedAppShots.isEmpty)
        XCTAssertEqual(fixture.draftOpener.openCount, 0)
        XCTAssertNotNil(fixture.appState.pendingComposerFocusToken)
        XCTAssertEqual(fixture.feedback.successSoundCount, 1)
    }

    func testVisibleDraftStagesIntoMainConversationWithoutMaterializing() async throws {
        let fixture = try AppShotCaptureControllerFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-draft")
        let seeded = try fixture.insertThread(name: "New thread", project: project, isDraft: true)
        let main = try XCTUnwrap(seeded.conversations.first)
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)

        await fixture.runCapture()

        XCTAssertTrue(try XCTUnwrap(fixture.context.resolveThread(id: seeded.thread.persistentModelID)).isDraft)
        XCTAssertEqual(fixture.runtimeStore.conversationState(for: main.id).stagedAppShots.count, 1)
        XCTAssertEqual(fixture.draftOpener.openCount, 0)
    }

    func testSelectedProjectCreatesAndOpensDraftOnlyAfterSuccessfulStaging() async throws {
        let fixture = try AppShotCaptureControllerFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-project")
        fixture.appState.selectedSidebarItem = .project(project)

        await fixture.runCapture()

        guard case .thread(let selectedDraft) = fixture.appState.selectedSidebarItem else {
            return XCTFail("Expected the staged draft to open")
        }
        let draft = try XCTUnwrap(fixture.context.resolveThread(id: selectedDraft.persistentModelID))
        let conversation = try XCTUnwrap(draft.conversations.first)
        XCTAssertTrue(draft.isDraft)
        XCTAssertEqual(draft.project?.persistentModelID, project.persistentModelID)
        XCTAssertEqual(fixture.runtimeStore.conversationState(for: conversation.id).stagedAppShots.count, 1)
        XCTAssertNotNil(fixture.appState.pendingComposerFocusToken)
    }

    func testNoThreadRouteUsesStaleLastActiveFallbackAndRewritesIt() async throws {
        var settings = AppSettings()
        settings.lastActiveProjectPath = "/tmp/deleted"
        let fixture = try AppShotCaptureControllerFixture(settings: settings)
        _ = try fixture.insertProject(name: "Beta", path: "/tmp/beta")
        let fallback = try fixture.insertProject(name: "alveary", path: "/tmp/z-alveary")
        let deterministicFirst = try fixture.insertProject(name: "Alveary", path: "/tmp/a-alveary")

        await fixture.runCapture()

        XCTAssertNotEqual(fallback.persistentModelID, deterministicFirst.persistentModelID)
        XCTAssertEqual(fixture.draftOpener.lastProjectID, deterministicFirst.persistentModelID)
        XCTAssertEqual(fixture.settingsService.current.lastActiveProjectPath, deterministicFirst.path)
    }

    func testNoProjectsShortCircuitsBeforePermissionsOrPreparation() async throws {
        let fixture = try AppShotCaptureControllerFixture()

        await fixture.runCapture()

        let preparationCount = await fixture.prepareGate.count()
        let storedConversationIDs = await fixture.attachmentStore.storedConversationIDs
        XCTAssertEqual(preparationCount, 0)
        XCTAssertEqual(fixture.draftOpener.openCount, 0)
        XCTAssertTrue(storedConversationIDs.isEmpty)
        XCTAssertEqual(fixture.feedback.activationCount, 1)
        XCTAssertTrue(fixture.feedback.permissions.isEmpty)
        XCTAssertEqual(fixture.appState.unexpectedErrorToasts.map(\.message), [AppShotCaptureController.noProjectMessage])
    }

    func testUnavailableSelectedDestinationUsesAppToastBeforePreparation() async throws {
        let fixture = try AppShotCaptureControllerFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-unavailable")
        let seeded = try fixture.insertThread(name: "Unavailable", project: project, conversationIDs: [])
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)

        await fixture.runCapture()

        let preparationCount = await fixture.prepareGate.count()
        let storedConversationIDs = await fixture.attachmentStore.storedConversationIDs
        XCTAssertEqual(preparationCount, 0)
        XCTAssertEqual(fixture.draftOpener.openCount, 0)
        XCTAssertTrue(storedConversationIDs.isEmpty)
        XCTAssertEqual(fixture.feedback.activationCount, 1)
        XCTAssertEqual(
            fixture.appState.unexpectedErrorToasts.map(\.message),
            [AppShotRoutingError.destinationUnavailable.localizedDescription]
        )
    }

    func testPermissionFailurePresentsGrantAssistantWithoutDraftOrFile() async throws {
        let fixture = try AppShotCaptureControllerFixture(prepareError: .accessibilityPermissionMissing)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-permission")
        fixture.appState.selectedSidebarItem = .project(project)

        await fixture.runCapture()

        let storedConversationIDs = await fixture.attachmentStore.storedConversationIDs
        XCTAssertEqual(fixture.feedback.permissions, [.accessibility])
        XCTAssertEqual(fixture.feedback.activationCount, 0)
        XCTAssertEqual(fixture.draftOpener.openCount, 0)
        XCTAssertTrue(storedConversationIDs.isEmpty)
        XCTAssertTrue(fixture.appState.unexpectedErrorToasts.isEmpty)
    }

    func testPreparationFailureUsesAppToastWithoutCreatingDraft() async throws {
        let fixture = try AppShotCaptureControllerFixture(prepareError: .noTargetWindow)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-prepare")
        fixture.appState.selectedSidebarItem = .project(project)

        await fixture.runCapture()

        let storedConversationIDs = await fixture.attachmentStore.storedConversationIDs
        XCTAssertEqual(fixture.feedback.activationCount, 1)
        XCTAssertEqual(fixture.draftOpener.openCount, 0)
        XCTAssertTrue(storedConversationIDs.isEmpty)
        XCTAssertEqual(fixture.appState.unexpectedErrorToasts.map(\.message), [AppShotCaptureError.noTargetWindow.localizedDescription])
    }

    func testSelectionChangeDuringPreparationCancelsBeforeDraftCreationOrStorage() async throws {
        let fixture = try AppShotCaptureControllerFixture(pausesPreparation: true)
        let first = try fixture.insertProject(name: "First", path: "/tmp/app-shot-prepare-first")
        let second = try fixture.insertProject(name: "Second", path: "/tmp/app-shot-prepare-second")
        fixture.appState.selectedSidebarItem = .project(first)

        let capture = try XCTUnwrap(fixture.controller.captureIfIdle())
        await fixture.prepareGate.waitUntilPreparationBegins()
        fixture.appState.selectedSidebarItem = .project(second)
        await fixture.prepareGate.resumePreparation()
        await capture.value

        let storedConversationIDs = await fixture.attachmentStore.storedConversationIDs
        XCTAssertEqual(fixture.draftOpener.openCount, 0)
        XCTAssertTrue(storedConversationIDs.isEmpty)
        XCTAssertEqual(fixture.feedback.activationCount, 0)
    }

    func testMainConversationSelectionRepairDuringPreparationKeepsDestination() async throws {
        let fixture = try AppShotCaptureControllerFixture(pausesPreparation: true)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-selection-repair")
        let seeded = try fixture.insertThread(name: "Feature work", project: project)
        let main = try XCTUnwrap(seeded.conversations.first)
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)
        XCTAssertNil(fixture.appState.selectedConversationIDs[seeded.thread.persistentModelID])

        let capture = try XCTUnwrap(fixture.controller.captureIfIdle())
        await fixture.prepareGate.waitUntilPreparationBegins()
        fixture.appState.selectConversation(main, in: seeded.thread)
        await fixture.prepareGate.resumePreparation()
        await capture.value

        XCTAssertEqual(fixture.runtimeStore.conversationState(for: main.id).stagedAppShots.count, 1)
        XCTAssertEqual(fixture.feedback.successSoundCount, 1)
    }

    func testSecondaryConversationSelectionChangeDuringPreparationCancelsBeforeStorage() async throws {
        let fixture = try AppShotCaptureControllerFixture(pausesPreparation: true)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-conversation-change")
        let seeded = try fixture.insertThread(
            name: "Feature work",
            project: project,
            conversationIDs: ["main", "secondary"]
        )
        let secondary = try XCTUnwrap(seeded.conversations.last)
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)

        let capture = try XCTUnwrap(fixture.controller.captureIfIdle())
        await fixture.prepareGate.waitUntilPreparationBegins()
        fixture.appState.selectConversation(secondary, in: seeded.thread)
        await fixture.prepareGate.resumePreparation()
        await capture.value

        let storedConversationIDs = await fixture.attachmentStore.storedConversationIDs
        XCTAssertTrue(storedConversationIDs.isEmpty)
        XCTAssertEqual(fixture.feedback.successSoundCount, 0)
    }

    func testVisibleDraftProjectReassignmentDuringPreparationCancelsBeforeStorage() async throws {
        let fixture = try AppShotCaptureControllerFixture(pausesPreparation: true)
        let first = try fixture.insertProject(name: "First", path: "/tmp/app-shot-visible-draft-first")
        let second = try fixture.insertProject(name: "Second", path: "/tmp/app-shot-visible-draft-second")
        let seeded = try fixture.insertThread(name: "New thread", project: first, isDraft: true)
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)

        let capture = try XCTUnwrap(fixture.controller.captureIfIdle())
        await fixture.prepareGate.waitUntilPreparationBegins()
        seeded.thread.project = second
        try fixture.context.save()
        await fixture.prepareGate.resumePreparation()
        await capture.value

        let storedConversationIDs = await fixture.attachmentStore.storedConversationIDs
        XCTAssertTrue(storedConversationIDs.isEmpty)
        XCTAssertEqual(fixture.feedback.successSoundCount, 0)
    }

    func testSelectionChangeDuringDraftCreationLeavesReusableHiddenDraftWithoutStorage() async throws {
        let fixture = try AppShotCaptureControllerFixture(pausesDraftCreation: true)
        let first = try fixture.insertProject(name: "First", path: "/tmp/app-shot-draft-first")
        let second = try fixture.insertProject(name: "Second", path: "/tmp/app-shot-draft-second")
        fixture.appState.selectedSidebarItem = .project(first)

        let capture = try XCTUnwrap(fixture.controller.captureIfIdle())
        await fixture.draftOpener.waitUntilDraftIsCreated()
        fixture.appState.selectedSidebarItem = .project(second)
        fixture.draftOpener.resumeDraftCreation()
        await capture.value

        let storedConversationIDs = await fixture.attachmentStore.storedConversationIDs
        let draftID = try XCTUnwrap(fixture.draftOpener.createdThreadID)
        XCTAssertTrue(try XCTUnwrap(fixture.context.resolveThread(id: draftID)).isDraft)
        XCTAssertTrue(storedConversationIDs.isEmpty)
        XCTAssertEqual(fixture.appState.selectedSidebarItem, .project(second))
    }

    func testRepeatedShortcutPressIsIgnoredUntilCaptureFinishes() async throws {
        let fixture = try AppShotCaptureControllerFixture(pausesPreparation: true)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-repeat")
        fixture.appState.selectedSidebarItem = .project(project)

        let firstCapture = try XCTUnwrap(fixture.controller.captureIfIdle())
        await fixture.prepareGate.waitUntilPreparationBegins()
        XCTAssertNil(fixture.controller.captureIfIdle())
        await fixture.prepareGate.resumePreparation()
        await firstCapture.value

        let laterCapture = try XCTUnwrap(fixture.controller.captureIfIdle())
        await laterCapture.value

        let preparationCount = await fixture.prepareGate.count()
        let storedConversationIDs = await fixture.attachmentStore.storedConversationIDs
        XCTAssertEqual(preparationCount, 2)
        XCTAssertEqual(storedConversationIDs.count, 2)
    }

    func testSelectionChangeAfterStorageBeginsStagesOriginalConversationAndShowsSuccessToast() async throws {
        let fixture = try AppShotCaptureControllerFixture(pausesStorage: true)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-storage-selection")
        let original = try fixture.insertThread(
            name: "Original thread",
            project: project,
            conversationIDs: ["original-main"]
        )
        let other = try fixture.insertThread(
            name: "Other thread",
            project: project,
            conversationIDs: ["other-main"]
        )
        let originalConversation = try XCTUnwrap(original.conversations.first)
        fixture.appState.selectedSidebarItem = .thread(original.thread)

        let capture = try XCTUnwrap(fixture.controller.captureIfIdle())
        try await waitUntil("app-shot storage to begin", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.attachmentStore.hasBegunStorage()
        }
        fixture.appState.selectedSidebarItem = .thread(other.thread)
        await fixture.attachmentStore.resumeStorage()
        await capture.value

        XCTAssertEqual(fixture.runtimeStore.conversationState(for: originalConversation.id).stagedAppShots.count, 1)
        XCTAssertEqual(fixture.appState.selectedSidebarItem, .thread(other.thread))
        XCTAssertEqual(fixture.appState.unexpectedErrorToasts.last?.kind, .success)
        XCTAssertEqual(fixture.appState.unexpectedErrorToasts.last?.message, "App shot added to Original thread.")
        XCTAssertEqual(fixture.feedback.activationCount, 1)
        XCTAssertEqual(fixture.feedback.successSoundCount, 1)
    }

    func testProjectRouteDoesNotForceDraftNavigationAfterStorageSelectionChange() async throws {
        let fixture = try AppShotCaptureControllerFixture(pausesStorage: true)
        let originalProject = try fixture.insertProject(name: "Original", path: "/tmp/app-shot-project-storage")
        let otherProject = try fixture.insertProject(name: "Other", path: "/tmp/app-shot-project-other")
        fixture.appState.selectedSidebarItem = .project(originalProject)

        let capture = try XCTUnwrap(fixture.controller.captureIfIdle())
        try await waitUntil("app-shot storage to begin", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.attachmentStore.hasBegunStorage()
        }
        fixture.appState.selectedSidebarItem = .project(otherProject)
        await fixture.attachmentStore.resumeStorage()
        await capture.value

        let draftID = try XCTUnwrap(fixture.draftOpener.createdThreadID)
        let draft = try XCTUnwrap(fixture.context.resolveThread(id: draftID))
        let conversation = try XCTUnwrap(draft.conversations.first)
        XCTAssertEqual(fixture.runtimeStore.conversationState(for: conversation.id).stagedAppShots.count, 1)
        XCTAssertEqual(fixture.appState.selectedSidebarItem, .project(otherProject))
        XCTAssertEqual(fixture.appState.unexpectedErrorToasts.last?.kind, .success)
    }

    func testDestinationDeletionAfterStorageBeginsRemovesStoredAttachmentAndReportsFailure() async throws {
        let fixture = try AppShotCaptureControllerFixture(pausesStorage: true)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-delete")
        let seeded = try fixture.insertThread(name: "Deleted thread", project: project)
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)

        let capture = try XCTUnwrap(fixture.controller.captureIfIdle())
        try await waitUntil("app-shot storage to begin", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.attachmentStore.hasBegunStorage()
        }
        fixture.context.delete(seeded.thread)
        try fixture.context.save()
        await fixture.attachmentStore.resumeStorage()
        await capture.value

        let removedURLs = await fixture.attachmentStore.removedAttachmentURLs
        XCTAssertEqual(removedURLs.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(removedURLs.first).path))
        XCTAssertEqual(fixture.feedback.successSoundCount, 0)
        XCTAssertEqual(fixture.appState.unexpectedErrorToasts.last?.kind, .error)
        XCTAssertEqual(
            fixture.appState.unexpectedErrorToasts.last?.message,
            AppShotRoutingError.destinationDeleted.localizedDescription
        )
    }

    func testMountedSelectedStorageFailureUsesConversationError() async throws {
        let fixture = try AppShotCaptureControllerFixture(storageError: .storageFailed)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-mounted-error")
        let seeded = try fixture.insertThread(name: "Mounted", project: project)
        let conversation = try XCTUnwrap(seeded.conversations.first)
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)
        let state = fixture.runtimeStore.conversationState(for: conversation.id)
        state.registerViewMount()

        await fixture.runCapture()

        XCTAssertEqual(state.lastTurnError, AppShotRoutingTestError.storageFailed.localizedDescription)
        XCTAssertTrue(fixture.appState.unexpectedErrorToasts.isEmpty)
        XCTAssertEqual(fixture.feedback.successSoundCount, 0)
    }

    func testUnmountedStorageFailureUsesAppToast() async throws {
        let fixture = try AppShotCaptureControllerFixture(storageError: .storageFailed)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-unmounted-error")
        let seeded = try fixture.insertThread(name: "Unmounted", project: project)
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)

        await fixture.runCapture()

        XCTAssertEqual(fixture.appState.unexpectedErrorToasts.last?.message, AppShotRoutingTestError.storageFailed.localizedDescription)
        XCTAssertEqual(fixture.appState.unexpectedErrorToasts.last?.kind, .error)
    }

    func testStagingFailureRollsBackStateAndRemovesStoredAttachment() async throws {
        let fixture = try AppShotCaptureControllerFixture(stagingError: .stagingFailed)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-stage-error")
        let seeded = try fixture.insertThread(name: "Staging failure", project: project)
        let conversation = try XCTUnwrap(seeded.conversations.first)
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)

        await fixture.runCapture()

        let removedURLs = await fixture.attachmentStore.removedAttachmentURLs
        XCTAssertTrue(fixture.runtimeStore.conversationState(for: conversation.id).stagedAppShots.isEmpty)
        XCTAssertEqual(removedURLs.count, 1)
        XCTAssertEqual(fixture.appState.unexpectedErrorToasts.last?.message, AppShotRoutingTestError.stagingFailed.localizedDescription)
        XCTAssertEqual(fixture.feedback.successSoundCount, 0)
    }

    func testStagingFailureReportsStoredAttachmentCleanupFailure() async throws {
        let fixture = try AppShotCaptureControllerFixture(
            removalError: .removalFailed,
            stagingError: .stagingFailed
        )
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-stage-cleanup-error")
        let seeded = try fixture.insertThread(name: "Cleanup failure", project: project)
        let conversation = try XCTUnwrap(seeded.conversations.first)
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)

        await fixture.runCapture()

        let removedURLs = await fixture.attachmentStore.removedAttachmentURLs
        let expectedError = AppShotAttachmentCleanupError(
            originalError: AppShotRoutingTestError.stagingFailed.localizedDescription,
            cleanupError: AppShotRoutingTestError.removalFailed.localizedDescription
        )
        XCTAssertTrue(fixture.runtimeStore.conversationState(for: conversation.id).stagedAppShots.isEmpty)
        XCTAssertEqual(removedURLs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(removedURLs.first).path))
        XCTAssertEqual(fixture.appState.unexpectedErrorToasts.last?.message, expectedError.localizedDescription)
        XCTAssertEqual(fixture.feedback.successSoundCount, 0)
    }

    func testDraftCreationFailureStoresNoAttachment() async throws {
        let fixture = try AppShotCaptureControllerFixture(draftError: .draftCreationFailed)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-draft-error")
        fixture.appState.selectedSidebarItem = .project(project)

        await fixture.runCapture()

        let storedConversationIDs = await fixture.attachmentStore.storedConversationIDs
        XCTAssertTrue(storedConversationIDs.isEmpty)
        XCTAssertEqual(fixture.appState.unexpectedErrorToasts.last?.message, AppShotRoutingTestError.draftCreationFailed.localizedDescription)
        XCTAssertEqual(fixture.feedback.successSoundCount, 0)
    }
}
