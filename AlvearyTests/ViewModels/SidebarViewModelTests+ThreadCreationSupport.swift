import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// Fixtures and doubles for `SidebarViewModelTests+ThreadCreation.swift`. They live here rather
/// than beside the tests so that file stays inside the 500-line lint budget.

@MainActor
func makePreservedDraftRuntime(conversationID: String) -> PreservedDraftRuntime {
    let store = MockConversationRuntimeStore()
    let state = store.conversationState(for: conversationID)
    let attachmentDate = Date(timeIntervalSince1970: 123)
    let image = LocalImageAttachment(
        id: "image",
        fileURL: URL(fileURLWithPath: "/tmp/draft-image.png"),
        label: "draft-image.png",
        createdAt: attachmentDate
    )
    let file = LocalFileAttachment(
        id: "file",
        fileURL: URL(fileURLWithPath: "/tmp/draft-notes.txt"),
        createdAt: attachmentDate
    )
    let appShot = AppShotAttachment(
        id: "app-shot",
        appName: "Preview",
        bundleIdentifier: "com.apple.Preview",
        windowTitle: "Draft window",
        screenshot: image,
        axTreeText: "Draft accessibility text",
        focusedElementSummary: "Focused text field",
        attachmentStoreRoot: URL(fileURLWithPath: "/tmp/draft-app-shots", isDirectory: true)
    )
    let goal = AgentGoalSnapshot(
        objective: "Preserve the draft",
        status: .active,
        availableActions: [.pause, .delete],
        elapsedSeconds: 10
    )
    state.inputDraft = "Keep this composer text"
    state.inputDraftIsEffectivelyEmpty = false
    state.stagedContext = "Keep this staged context"
    state.stagedImageAttachments = [image]
    state.stagedFileAttachments = [file]
    state.stagedAppShots = [appShot]
    state.isGoalModeArmed = true
    state.goalSnapshot = goal
    return PreservedDraftRuntime(store: store, state: state, image: image, file: file, appShot: appShot, goal: goal)
}

@MainActor
func assertPreservedDraftRuntime(_ preserved: PreservedDraftRuntime, conversationID: String) {
    let movedState = preserved.store.conversationState(for: conversationID)
    XCTAssertTrue(movedState === preserved.state)
    XCTAssertEqual(movedState.inputDraft, "Keep this composer text")
    XCTAssertFalse(movedState.inputDraftIsEffectivelyEmpty)
    XCTAssertEqual(movedState.stagedContext, "Keep this staged context")
    XCTAssertEqual(movedState.stagedImageAttachments, [preserved.image])
    XCTAssertEqual(movedState.stagedFileAttachments, [preserved.file])
    XCTAssertEqual(movedState.stagedAppShots, [preserved.appShot])
    XCTAssertTrue(movedState.isGoalModeArmed)
    XCTAssertEqual(movedState.goalSnapshot, preserved.goal)
}

struct PreservedDraftRuntime {
    let store: MockConversationRuntimeStore
    let state: ConversationState
    let image: LocalImageAttachment
    let file: LocalFileAttachment
    let appShot: AppShotAttachment
    let goal: AgentGoalSnapshot
}

actor PausingDraftProviderDiscoveryService: AgentCLIKit.AgentProviderDiscoveryService {
    private let statuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus]
    private var isPaused: Bool
    private var callCount = 0
    private var didRequestProviderStatuses = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var providerStatusesContinuation: CheckedContinuation<Void, Never>?

    /// `startsPaused: false` lets a test seed a cache decorator before arming the hold, so the
    /// probe it blocks is the *refresh* rather than the initial fill.
    init(
        statuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus],
        startsPaused: Bool = true
    ) {
        self.statuses = statuses
        isPaused = startsPaused
    }

    func providerStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        didRequestProviderStatuses = true
        callCount += 1
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        if isPaused {
            await withCheckedContinuation { providerStatusesContinuation = $0 }
        }
        return statuses
    }

    func installedProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses.filter { $0.value.isInstalled }
    }

    func availableProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses.filter { $0.value.isEnabled && $0.value.installation != .missing }
    }

    func modelOptions(for providerId: AgentCLIKit.AgentProviderID) async -> [AgentCLIKit.AgentModelOption] {
        statuses[providerId]?.modelOptions ?? []
    }

    func stableProviderOrdering() async -> [AgentCLIKit.AgentProviderID] {
        [.claude, .codex]
    }

    func waitUntilProviderStatusesRequested() async {
        guard !didRequestProviderStatuses else {
            return
        }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func pause() {
        isPaused = true
    }

    func providerStatusesCallCount() -> Int {
        callCount
    }

    func resumeProviderStatuses() {
        isPaused = false
        providerStatusesContinuation?.resume()
        providerStatusesContinuation = nil
    }
}

/// A clock the test advances by hand, so a stale snapshot needs no sleeping.
final class DraftDiscoveryTestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000)

    func advance(_ interval: TimeInterval) {
        now += interval
    }
}

enum DraftProjectMoveSaveError: Error {
    case forced
}

final class DraftProjectChangeNotificationRecorder: @unchecked Sendable {
    private let expectedThreadID: PersistentIdentifier
    private let lock = NSLock()
    private var recordedCount = 0

    init(expectedThreadID: PersistentIdentifier) {
        self.expectedThreadID = expectedThreadID
    }

    var count: Int {
        lock.withLock { recordedCount }
    }

    func recordIfMatching(_ payload: [AnyHashable: Any]?) {
        guard payload?[ThreadDraftNotificationKey.threadID] as? PersistentIdentifier == expectedThreadID else {
            return
        }
        lock.withLock { recordedCount += 1 }
    }
}
