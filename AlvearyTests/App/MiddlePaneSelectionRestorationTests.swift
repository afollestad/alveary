import XCTest

@testable import Alveary

@MainActor
final class MiddlePaneSelectionRestorationTests: XCTestCase {
    func testResolveScheduledBookmarkReturnsScheduledDestination() throws {
        let fixture = try SidebarTestFixture()

        XCTAssertEqual(
            resolveSidebarSelectionBookmark(.scheduled, modelContext: fixture.context),
            .scheduled
        )
    }

    func testResolveSidebarBookmarkReturnsThreadForActiveThreadBookmark() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project"
        )

        let item = resolveSidebarSelectionBookmark(.threadId(thread.persistentModelID), modelContext: fixture.context)

        XCTAssertEqual(item, .thread(thread))
    }

    func testResolveSidebarBookmarkReturnsProjectForArchivedThreadBookmark() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            archivedAt: Date()
        )

        let item = resolveSidebarSelectionBookmark(.threadId(thread.persistentModelID), modelContext: fixture.context)

        XCTAssertEqual(item, .project(try XCTUnwrap(thread.project)))
    }

    func testResolveSidebarBookmarkDoesNotRouteArchivedLinkedRunFallbackIntoProject() throws {
        let fixture = try SidebarTestFixture()
        let (thread, _) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .success,
            conversationID: "archived-fallback-bookmark"
        )
        let project = Project(path: "/tmp/archived-fallback-bookmark", name: "Project")
        fixture.context.insert(project)
        thread.modeRawValue = "future-mode"
        thread.project = project
        thread.archivedAt = Date()
        try fixture.context.save()

        let item = resolveSidebarSelectionBookmark(.threadId(thread.persistentModelID), modelContext: fixture.context)

        XCTAssertNil(item)
    }

    func testQueuedDraftProjectMoveRechecksVoiceLockBeforeMutation() async {
        let lifecycleController = VoiceInputLifecycleController(service: DisabledVoiceInputService())
        let sink = MiddlePaneVoiceInputSinkFake()
        var moveCount = 0

        let queuedMove = Task { @MainActor in
            performDraftProjectMoveIfVoiceInputUnlocked(
                lifecycleController: lifecycleController,
                operation: {
                    moveCount += 1
                    return true
                }
            )
        }
        lifecycleController.setActiveComposerSink(sink)

        let result = await queuedMove.value
        XCTAssertNil(result)
        XCTAssertEqual(moveCount, 0)
    }
}

@MainActor
private final class MiddlePaneVoiceInputSinkFake: VoiceInputComposerSink {
    func forceVoiceInputCommitSynchronously() {}
}
