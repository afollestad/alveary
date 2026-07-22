import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ScheduledTaskLocalTimeZoneRebaserTests: XCTestCase {
    func testRebaseMovesWallClockSchedulesBothDirectionsAndPreservesPendingOccurrence() throws {
        let fixture = try LocalTimeZoneRebaserFixture(currentTimeZoneIdentifier: "America/Chicago")
        let actionDate = try date("2026-07-21T12:00:00Z")
        let pendingOccurrence = try date("2026-07-21T11:00:00Z")
        let waitStartedAt = try date("2026-07-21T11:30:00Z")
        let west = fixture.insertDefinition(
            id: "west",
            timeZoneIdentifier: "America/Los_Angeles",
            nextOccurrenceAt: try date("2026-07-21T16:00:00Z")
        )
        west.pendingOccurrenceAt = pendingOccurrence
        west.targetWaitStartedAt = waitStartedAt
        let east = fixture.insertDefinition(
            id: "east",
            timeZoneIdentifier: "America/New_York",
            nextOccurrenceAt: try date("2026-07-21T13:00:00Z")
        )
        try fixture.context.save()

        XCTAssertTrue(try fixture.rebaser.rebaseAll(at: actionDate))

        let expectedNextOccurrence = try date("2026-07-21T14:00:00Z")
        XCTAssertEqual(west.nextOccurrenceAt, expectedNextOccurrence)
        XCTAssertEqual(east.nextOccurrenceAt, expectedNextOccurrence)
        XCTAssertEqual(west.pendingOccurrenceAt, pendingOccurrence)
        XCTAssertEqual(west.targetWaitStartedAt, waitStartedAt)
        XCTAssertEqual(west.timeZoneIdentifier, "America/Chicago")
        XCTAssertEqual(east.timeZoneIdentifier, "America/Chicago")
        XCTAssertFalse(try fixture.rebaser.rebaseAll(at: actionDate))
    }

    func testRebaseKeepsAbsoluteSchedulesAndClaimedRunSnapshotFrozen() throws {
        let fixture = try LocalTimeZoneRebaserFixture(currentTimeZoneIdentifier: "America/Chicago")
        let actionDate = try date("2026-07-21T12:00:00Z")
        let onceOccurrence = try date("2026-07-22T18:00:00Z")
        let intervalOccurrence = try date("2026-07-21T12:30:00Z")
        let once = fixture.insertDefinition(
            id: "once",
            recurrence: .once(onceOccurrence),
            timeZoneIdentifier: "America/Los_Angeles",
            nextOccurrenceAt: onceOccurrence
        )
        let interval = fixture.insertDefinition(
            id: "interval",
            recurrence: .interval(minutes: 30, anchor: try date("2026-07-21T12:00:00Z")),
            timeZoneIdentifier: "America/New_York",
            nextOccurrenceAt: intervalOccurrence
        )
        try fixture.context.save()

        XCTAssertTrue(try fixture.rebaser.rebaseAll(at: actionDate))
        XCTAssertEqual(once.nextOccurrenceAt, onceOccurrence)
        XCTAssertEqual(interval.nextOccurrenceAt, intervalOccurrence)

        let run = ScheduledTaskRun(
            snapshotting: once,
            occurrenceID: "timezone-snapshot",
            occurrenceAt: onceOccurrence,
            triggerKind: .scheduled
        )
        once.timeZoneIdentifier = "Asia/Tokyo"
        XCTAssertEqual(run.timeZoneIdentifierSnapshot, "America/Chicago")
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }
}

@MainActor
private struct LocalTimeZoneRebaserFixture {
    let context: ModelContext
    let rebaser: ScheduledTaskLocalTimeZoneRebaser

    init(currentTimeZoneIdentifier: String) throws {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        rebaser = ScheduledTaskLocalTimeZoneRebaser(
            modelContext: context,
            currentTimeZone: {
                TimeZone(identifier: currentTimeZoneIdentifier) ?? .current
            }
        )
    }

    func insertDefinition(
        id: String,
        recurrence: ScheduledTaskRecurrence = .daily(hour: 9, minute: 0),
        timeZoneIdentifier: String,
        nextOccurrenceAt: Date
    ) -> ScheduledTask {
        let definition = ScheduledTask(
            id: id,
            title: id,
            prompt: "Run",
            recurrence: recurrence,
            timeZoneIdentifier: timeZoneIdentifier,
            providerID: "codex",
            nextOccurrenceAt: nextOccurrenceAt
        )
        context.insert(definition)
        return definition
    }
}
