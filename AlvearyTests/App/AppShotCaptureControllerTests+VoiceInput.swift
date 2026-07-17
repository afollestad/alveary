import XCTest

@testable import Alveary

@MainActor
extension AppShotCaptureControllerTests {
    func testVoiceInputLockPreventsAppShotCaptureFromStarting() async throws {
        let fixture = try AppShotCaptureControllerFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-voice-lock")
        let seeded = try fixture.insertThread(name: "Thread", project: project)
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)
        fixture.voiceInputLock.isLocked = true

        XCTAssertNil(fixture.controller.captureIfIdle())
        let preparationCount = await fixture.prepareGate.count()
        XCTAssertEqual(preparationCount, 0)
    }

    func testVoiceInputLockAfterStorageRemovesCapturedFileInsteadOfStaging() async throws {
        let fixture = try AppShotCaptureControllerFixture(pausesStorage: true)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/app-shot-voice-storage")
        let seeded = try fixture.insertThread(name: "Thread", project: project)
        let conversation = try XCTUnwrap(seeded.conversations.first)
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)

        let capture = try XCTUnwrap(fixture.controller.captureIfIdle())
        for _ in 0..<500 {
            if await fixture.attachmentStore.hasBegunStorage() { break }
            await Task.yield()
        }
        fixture.voiceInputLock.isLocked = true
        await fixture.attachmentStore.resumeStorage()
        await capture.value

        XCTAssertTrue(fixture.runtimeStore.conversationState(for: conversation.id).stagedAppShots.isEmpty)
        let removedAttachmentCount = await fixture.attachmentStore.removedAttachmentURLs.count
        XCTAssertEqual(removedAttachmentCount, 1)
    }
}
