import AgentCLIKit
@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatSurfaceViewTests {
    func testGoalElapsedClockTicksActiveGoalFromProviderElapsed() {
        var now = 100.0
        let clock = GoalElapsedDisplayClock(now: { now })
        let snapshot = goalSnapshot(elapsedSeconds: 15)

        XCTAssertEqual(clock.synchronize(with: snapshot), 15)
        now = 102.4

        XCTAssertEqual(clock.tickElapsed(for: snapshot), 17)
    }

    func testGoalElapsedClockStartsMissingActiveElapsedAtZero() {
        var now = 10.0
        let clock = GoalElapsedDisplayClock(now: { now })
        let snapshot = goalSnapshot(elapsedSeconds: nil)

        XCTAssertEqual(clock.synchronize(with: snapshot), 0)
        now = 11.2

        XCTAssertEqual(clock.tickElapsed(for: snapshot), 1)
    }

    func testGoalElapsedClockPreservesElapsedAcrossElapsedMissingRefresh() {
        var now = 0.0
        let clock = GoalElapsedDisplayClock(now: { now })
        let snapshot = goalSnapshot(elapsedSeconds: nil)

        XCTAssertEqual(clock.synchronize(with: snapshot), 0)
        now = 3.7
        XCTAssertEqual(clock.tickElapsed(for: snapshot), 3)

        XCTAssertEqual(clock.synchronize(with: goalSnapshot(elapsedSeconds: nil, tokenCount: 50)), 3)
    }

    func testGoalElapsedClockRebasesUpwardAndIgnoresLowerActiveElapsed() {
        var now = 0.0
        let clock = GoalElapsedDisplayClock(now: { now })
        let snapshot = goalSnapshot(elapsedSeconds: 10)

        XCTAssertEqual(clock.synchronize(with: snapshot), 10)
        now = 5.2
        XCTAssertEqual(clock.tickElapsed(for: snapshot), 15)

        XCTAssertEqual(clock.synchronize(with: goalSnapshot(elapsedSeconds: 30)), 30)
        now = 6.2
        XCTAssertEqual(clock.tickElapsed(for: goalSnapshot(elapsedSeconds: 30)), 31)
        XCTAssertEqual(clock.synchronize(with: goalSnapshot(elapsedSeconds: 20)), 31)
    }

    func testGoalElapsedClockFreezesPausedAndResumesSameObjective() {
        var now = 0.0
        let clock = GoalElapsedDisplayClock(now: { now })
        let snapshot = goalSnapshot(elapsedSeconds: 5)

        XCTAssertEqual(clock.synchronize(with: snapshot), 5)
        now = 2.3
        XCTAssertEqual(clock.tickElapsed(for: snapshot), 7)
        XCTAssertEqual(clock.synchronize(with: goalSnapshot(status: .paused, elapsedSeconds: nil)), 7)

        now = 10.0
        XCTAssertEqual(clock.synchronize(with: goalSnapshot(status: .active, elapsedSeconds: nil)), 7)
        now = 12.1
        XCTAssertEqual(clock.tickElapsed(for: goalSnapshot(status: .active, elapsedSeconds: nil)), 9)
    }

    func testGoalElapsedClockResetsAfterTerminalOrObjectiveChange() {
        var now = 0.0
        let clock = GoalElapsedDisplayClock(now: { now })
        let snapshot = goalSnapshot(elapsedSeconds: 10)

        XCTAssertEqual(clock.synchronize(with: snapshot), 10)
        now = 5.0
        XCTAssertEqual(clock.tickElapsed(for: snapshot), 15)
        XCTAssertEqual(clock.synchronize(with: goalSnapshot(status: .achieved, elapsedSeconds: nil)), 15)
        XCTAssertEqual(clock.synchronize(with: goalSnapshot(elapsedSeconds: nil)), 0)

        now = 6.0
        XCTAssertEqual(clock.synchronize(with: goalSnapshot(objective: "A different goal", elapsedSeconds: nil)), 0)
    }

    func testTopContentGoalMetadataUpdatesElapsedWithInjectedClock() {
        var now = 0.0
        let view = AppKitChatComposerTopContentView(goalElapsedTimeProvider: { now })
        view.configure(.init(items: [
            goalStatusItem(elapsedSeconds: 15, tokenCount: 2_531)
        ]))

        XCTAssertTrue(goalMetadataStrings(in: view).contains(goalMetadata(elapsed: "15s", tokenCount: 2_531)))

        now = 2.2
        view.refreshGoalElapsedMetadataForTesting()

        XCTAssertTrue(goalMetadataStrings(in: view).contains(goalMetadata(elapsed: "17s", tokenCount: 2_531)))
    }

    func testTopContentGoalMetadataConfigureDoesNotResetElapsedForSameActiveGoal() {
        var now = 0.0
        let view = AppKitChatComposerTopContentView(goalElapsedTimeProvider: { now })
        view.configure(.init(items: [
            goalStatusItem(elapsedSeconds: nil, tokenCount: 1)
        ]))

        now = 3.4
        view.refreshGoalElapsedMetadataForTesting()
        view.configure(.init(items: [
            goalStatusItem(elapsedSeconds: nil, tokenCount: 2)
        ]))

        XCTAssertTrue(goalMetadataStrings(in: view).contains(goalMetadata(elapsed: "3s", tokenCount: 2)))
        XCTAssertFalse(goalMetadataStrings(in: view).contains(goalMetadata(elapsed: "0s", tokenCount: 2)))
    }

    func testTopContentGoalMetadataKeepsTokenCountProviderDriven() {
        var now = 0.0
        let view = AppKitChatComposerTopContentView(goalElapsedTimeProvider: { now })
        view.configure(.init(items: [
            goalStatusItem(elapsedSeconds: 10, tokenCount: 2_531)
        ]))

        now = 4.1
        view.refreshGoalElapsedMetadataForTesting()

        XCTAssertTrue(goalMetadataStrings(in: view).contains(goalMetadata(elapsed: "14s", tokenCount: 2_531)))
        XCTAssertFalse(goalMetadataStrings(in: view).contains(goalMetadata(elapsed: "14s", tokenCount: 2_532)))

        view.configure(.init(items: [
            goalStatusItem(elapsedSeconds: 15, tokenCount: 3_000)
        ]))

        XCTAssertTrue(goalMetadataStrings(in: view).contains(goalMetadata(elapsed: "15s", tokenCount: 3_000)))
    }

    func testTopContentGoalMetadataDoesNotTickWhenDisabled() {
        var now = 0.0
        let view = AppKitChatComposerTopContentView(goalElapsedTimeProvider: { now })
        view.configure(.init(
            items: [goalStatusItem(elapsedSeconds: 10, tokenCount: 2_531)],
            ticksGoalElapsedTime: false
        ))

        now = 5.0
        view.refreshGoalElapsedMetadataForTesting()

        XCTAssertTrue(goalMetadataStrings(in: view).contains(goalMetadata(elapsed: "10s", tokenCount: 2_531)))
    }

    func testTopContentGoalElapsedTimerDoesNotRunWithoutWindowAndContentCanClear() {
        let view = AppKitChatComposerTopContentView()
        view.configure(.init(items: [
            goalStatusItem(elapsedSeconds: 10, tokenCount: 2_531)
        ]))

        XCTAssertFalse(view.isGoalElapsedTimerRunningForTesting)

        view.configure(.empty)

        XCTAssertFalse(view.isGoalElapsedTimerRunningForTesting)
    }

    func testTopContentDisabledGoalRestartButtonHasTooltipAndDoesNotPress() throws {
        var didRestart = false
        let view = AppKitChatComposerTopContentView()
        view.configure(.init(items: [
            .goalStatus(.init(
                snapshot: goalSnapshot(status: .blocked, elapsedSeconds: 10),
                actionError: nil,
                onPause: nil,
                onResume: nil,
                onDelete: nil,
                onRestartTerminal: { didRestart = true },
                isRestartTerminalEnabled: false,
                restartTerminalDisabledTooltip: "Wait for the current turn to finish before starting Goal mode.",
                onDismissTerminal: {}
            ))
        ]))

        let restartButton = try XCTUnwrap(view.goalElapsedDescendants(of: ComposerTopContentButton.self).first {
            $0.accessibilityLabel() == "Restart"
        })

        XCTAssertEqual(restartButton.toolTip, "Wait for the current turn to finish before starting Goal mode.")
        XCTAssertFalse(restartButton.accessibilityPerformPress())
        XCTAssertFalse(didRestart)
    }
}

private func goalSnapshot(
    objective: String = "Fix the flaky goal row",
    status: AgentGoalStatus = .active,
    elapsedSeconds: Int?,
    tokenCount: Int? = nil
) -> AgentGoalSnapshot {
    AgentGoalSnapshot(
        objective: objective,
        status: status,
        elapsedSeconds: elapsedSeconds,
        tokenCount: tokenCount
    )
}

private func goalStatusItem(
    elapsedSeconds: Int?,
    tokenCount: Int
) -> AppKitChatComposerTopContentView.Item {
    .goalStatus(.init(
        snapshot: goalSnapshot(elapsedSeconds: elapsedSeconds, tokenCount: tokenCount),
        actionError: nil,
        onPause: nil,
        onResume: nil,
        onDelete: nil,
        onDismissTerminal: nil
    ))
}

private func goalMetadata(elapsed: String, tokenCount: Int) -> String {
    let tokenText = NumberFormatter.localizedString(from: NSNumber(value: tokenCount), number: .decimal)
    return "\(elapsed) | \(tokenText) tokens"
}

@MainActor
private func goalMetadataStrings(in view: NSView) -> [String] {
    var strings: [String] = []
    if let field = view as? NSTextField,
       field.stringValue.contains("tokens") {
        strings.append(field.stringValue)
    }
    view.subviews.forEach { strings.append(contentsOf: goalMetadataStrings(in: $0)) }
    return strings
}

private extension NSView {
    func goalElapsedDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.goalElapsedDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
