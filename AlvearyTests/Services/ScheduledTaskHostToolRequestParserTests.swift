import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

final class ScheduledTaskHostToolRequestParserTests: XCTestCase {
    func testParsesEverySupportedScheduleKindWithPinnedOrDefaultTimeZone() throws {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        let date = "2030-01-02T03:04:05Z"
        let fixtures: [([String: AgentCLIKit.JSONValue], ScheduledTaskProposalSchedule)] = [
            (schedule(["kind": .string("once"), "at": .string(date)]),
             ScheduledTaskProposalSchedule(
                 recurrence: .once(Date(timeIntervalSince1970: 1_893_553_445)),
                 timeZoneIdentifier: "UTC"
             )),
            (schedule(["kind": .string("interval"), "minutes": .number(1), "anchor_at": .string(date)]),
             ScheduledTaskProposalSchedule(
                 recurrence: .interval(minutes: 1, anchor: Date(timeIntervalSince1970: 1_893_553_445)),
                 timeZoneIdentifier: "UTC"
             )),
            (schedule(["kind": .string("daily"), "hour": .number(8), "minute": .number(5)]),
             ScheduledTaskProposalSchedule(recurrence: .daily(hour: 8, minute: 5), timeZoneIdentifier: "UTC")),
            (schedule(weekdays(days: ["monday", "wednesday", "saturday"], hour: 9, minute: 10)),
             ScheduledTaskProposalSchedule(
                recurrence: .weekdays(days: [2, 4, 7], hour: 9, minute: 10),
                timeZoneIdentifier: "UTC"
            )),
            (schedule([
                "kind": .string("weekly"),
                "weekday": .string("monday"),
                "hour": .number(10),
                "minute": .number(15)
            ]), ScheduledTaskProposalSchedule(
                recurrence: .weekly(weekday: 2, hour: 10, minute: 15),
                timeZoneIdentifier: "UTC"
            )),
            (schedule([
                "kind": .string("monthly"),
                "day": .number(31),
                "hour": .number(11),
                "minute": .number(20)
            ]), ScheduledTaskProposalSchedule(
                recurrence: .monthly(day: 31, hour: 11, minute: 20),
                timeZoneIdentifier: "UTC"
            ))
        ]

        for (arguments, expectedSchedule) in fixtures {
            let parsed = try parser.parse(arguments: arguments)
            guard case .create(_, _, let parsedSchedule) = parsed.request else {
                return XCTFail("Expected a create request")
            }
            XCTAssertEqual(parsedSchedule, expectedSchedule)
        }
    }

    func testRejectsLegacyExplicitTimeZoneThatDoesNotMatchMac() {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        let arguments = schedule([
            "kind": .string("daily"),
            "hour": .number(8),
            "minute": .number(0),
            "time_zone": .string("America/Chicago")
        ])

        assertInvalid(arguments, parser: parser, containing: "Mac's current local time zone")
    }

    func testOmittedTimeZoneIsResolvedForEachParseWithoutChangingRetryIdentity() throws {
        let timeZone = ScheduledTaskHostToolTimeZoneBox("UTC")
        let parser = ScheduledTaskHostToolRequestParser(
            defaultTimeZoneIdentifierProvider: { timeZone.identifier }
        )
        let arguments = schedule([
            "kind": .string("daily"),
            "hour": .number(8),
            "minute": .number(0)
        ])

        let first = try parser.parse(arguments: arguments)
        timeZone.identifier = "America/Chicago"
        let second = try parser.parse(arguments: arguments)

        guard case .create(_, _, let firstSchedule) = first.request,
              case .create(_, _, let secondSchedule) = second.request else {
            return XCTFail("Expected create requests")
        }
        XCTAssertEqual(firstSchedule.timeZoneIdentifier, "UTC")
        XCTAssertEqual(secondSchedule.timeZoneIdentifier, "America/Chicago")
        XCTAssertEqual(first.canonicalPayloadJSON, second.canonicalPayloadJSON)
        XCTAssertEqual(first.canonicalPayloadHash, second.canonicalPayloadHash)
    }

    func testRetryIdentityAcceptsPriorLegacyExplicitTimeZoneAfterMacTimeZoneChanges() throws {
        let timeZone = ScheduledTaskHostToolTimeZoneBox("UTC")
        let parser = ScheduledTaskHostToolRequestParser(
            defaultTimeZoneIdentifierProvider: { timeZone.identifier }
        )
        let arguments = schedule([
            "kind": .string("daily"),
            "hour": .number(8),
            "minute": .number(0),
            "time_zone": .string("UTC")
        ])
        let first = try parser.parse(arguments: arguments)
        timeZone.identifier = "America/Chicago"

        let retryIdentity = try parser.parseRetryIdentity(arguments: arguments)

        XCTAssertEqual(retryIdentity.canonicalPayloadJSON, first.canonicalPayloadJSON)
        XCTAssertEqual(retryIdentity.canonicalPayloadHash, first.canonicalPayloadHash)
        assertInvalid(arguments, parser: parser, containing: "Mac's current local time zone")
    }

    func testRejectsWeekdayCasingOutsideAdvertisedEnum() {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        let arguments = schedule([
            "kind": .string("weekly"),
            "weekday": .string("Monday"),
            "hour": .number(10),
            "minute": .number(15)
        ])

        assertInvalid(arguments, parser: parser, containing: "lowercase")
    }

    func testWeekdaysRequireUniqueExplicitDays() {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        let missing = schedule([
            "kind": .string("weekdays"),
            "hour": .number(10),
            "minute": .number(15)
        ])
        let empty = schedule([
            "kind": .string("weekdays"),
            "days": .array([]),
            "hour": .number(10),
            "minute": .number(15)
        ])
        let duplicate = schedule([
            "kind": .string("weekdays"),
            "days": .array([.string("monday"), .string("monday")]),
            "hour": .number(10),
            "minute": .number(15)
        ])

        assertInvalid(missing, parser: parser, containing: "must be an array")
        assertInvalid(empty, parser: parser, containing: "at least one")
        assertInvalid(duplicate, parser: parser, containing: "duplicate")
    }

    func testWeekdayCanonicalPayloadNormalizesDayOrder() throws {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        let first = schedule([
            "kind": .string("weekdays"),
            "days": .array([.string("friday"), .string("monday")]),
            "hour": .number(10),
            "minute": .number(15)
        ])
        let second = schedule([
            "kind": .string("weekdays"),
            "days": .array([.string("monday"), .string("friday")]),
            "hour": .number(10),
            "minute": .number(15)
        ])

        XCTAssertEqual(
            try parser.parse(arguments: first).canonicalPayloadHash,
            try parser.parse(arguments: second).canonicalPayloadHash
        )
    }

    func testRejectsUnknownFieldsAndNonIntegralNumbersRecursively() {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        var rootUnknown = schedule(["kind": .string("daily"), "hour": .number(8), "minute": .number(0)])
        rootUnknown["conversation_id"] = .string("forged")
        assertInvalid(rootUnknown, parser: parser, containing: "unsupported field")

        let nestedUnknown = schedule([
            "kind": .string("daily"),
            "hour": .number(8),
            "minute": .number(0),
            "folder_path": .string("/tmp/forged")
        ])
        assertInvalid(nestedUnknown, parser: parser, containing: "folder_path")

        let fractional = schedule([
            "kind": .string("interval"),
            "minutes": .number(1.5),
            "anchor_at": .string("2030-01-02T03:04:05Z")
        ])
        assertInvalid(fractional, parser: parser, containing: "integer")
    }

    func testParserRetainsActionSpecificStrictnessBeyondAdvertisedSchema() {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        var create = schedule(["kind": .string("daily"), "hour": .number(8), "minute": .number(0)])
        create["task_id"] = .string("not-valid-for-create")
        assertInvalid(create, parser: parser, containing: "task_id")

        let pause: [String: AgentCLIKit.JSONValue] = [
            "action": .string("pause"),
            "task_id": .string("task-1"),
            "revision": .number(1),
            "title": .string("not-valid-for-pause")
        ]
        assertInvalid(pause, parser: parser, containing: "title")
    }

    func testCanonicalPayloadHashIgnoresObjectOrderAndNormalizesDatesAndWhitespace() throws {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        let first: [String: AgentCLIKit.JSONValue] = [
            "action": .string("create"),
            "title": .string("  Daily review  "),
            "prompt": .string("  Review changes.  "),
            "schedule": .object([
                "kind": .string("once"),
                "at": .string("2030-01-01T21:00:00-06:00")
            ])
        ]
        let second: [String: AgentCLIKit.JSONValue] = [
            "schedule": .object([
                "at": .string("2030-01-02T03:00:00Z"),
                "kind": .string("once")
            ]),
            "prompt": .string("Review changes."),
            "title": .string("Daily review"),
            "action": .string("create")
        ]

        let parsedFirst = try parser.parse(arguments: first)
        let parsedSecond = try parser.parse(arguments: second)

        XCTAssertEqual(parsedFirst.canonicalPayloadJSON, parsedSecond.canonicalPayloadJSON)
        XCTAssertEqual(parsedFirst.canonicalPayloadHash, parsedSecond.canonicalPayloadHash)
        XCTAssertTrue(parsedFirst.canonicalPayloadJSON.contains(#""time_zone_source":"local""#))
        XCTAssertFalse(parsedFirst.canonicalPayloadJSON.contains(#""time_zone":"UTC""#))
    }

    func testCatalogAdvertisesExactlyTwoClosedDomainToolsWithoutTrustedFields() throws {
        XCTAssertEqual(
            ScheduledTaskHostToolCatalog.tools.map(\.name),
            ["list_scheduled_tasks", "propose_scheduled_task"]
        )
        let listTool = try XCTUnwrap(ScheduledTaskHostToolCatalog.tools.first)
        let proposeTool = try XCTUnwrap(ScheduledTaskHostToolCatalog.tools.last)
        XCTAssertEqual(listTool.annotations.readOnlyHint, true)
        XCTAssertEqual(listTool.annotations.idempotentHint, true)
        XCTAssertEqual(proposeTool.annotations.readOnlyHint, false)
        XCTAssertEqual(proposeTool.annotations.destructiveHint, false)
        XCTAssertEqual(proposeTool.annotations.idempotentHint, true)

        let encoded = try JSONEncoder().encode(proposeTool.inputSchema)
        let schema = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        for forbiddenField in ["conversation_id", "provider_id", "permission_mode", "folder_path", "project_path", "time_zone"] {
            XCTAssertFalse(schema.contains(#""\#(forbiddenField)""#))
        }

        let listRoot = try object(listTool.inputSchema)
        XCTAssertEqual(listRoot["additionalProperties"], .bool(false))
        let proposeRoot = try object(proposeTool.inputSchema)
        XCTAssertEqual(proposeRoot["additionalProperties"], .bool(false))
        XCTAssertEqual(proposeRoot["required"], .array([.string("action")]))
        let proposeProperties = try object(try XCTUnwrap(proposeRoot["properties"]))
        XCTAssertEqual(
            Set(proposeProperties.keys),
            ["action", "title", "prompt", "schedule", "task_id", "revision", "changes"]
        )
        XCTAssertNil(proposeRoot["oneOf"])
        XCTAssertNil(proposeRoot["anyOf"])
        XCTAssertNil(proposeRoot["allOf"])

        assertEveryObjectSchemaDeclaresProperties(proposeTool.inputSchema)
        XCTAssertTrue(proposeTool.description.contains("Use action create"))
        let serverInstructions = try XCTUnwrap(
            ScheduledTaskHostToolCatalog.serverMetadata(timeZoneIdentifier: "Pacific/Auckland").instructions
        )
        XCTAssertTrue(serverInstructions.contains("propose_scheduled_task"))
        XCTAssertTrue(serverInstructions.contains("action create"))
        XCTAssertTrue(serverInstructions.contains("Never use shell commands"))
        XCTAssertTrue(serverInstructions.contains("Mac's current local time zone (Pacific/Auckland)"))

        XCTAssertTrue(schema.contains(#""days""#))
        XCTAssertTrue(schema.contains(#""uniqueItems":true"#))
    }
}

private extension ScheduledTaskHostToolRequestParserTests {
    func schedule(_ schedule: [String: AgentCLIKit.JSONValue]) -> [String: AgentCLIKit.JSONValue] {
        [
            "action": .string("create"),
            "title": .string("Review"),
            "prompt": .string("Review changes."),
            "schedule": .object(schedule)
        ]
    }

    func weekdays(days: [String], hour: Int, minute: Int) -> [String: AgentCLIKit.JSONValue] {
        [
            "kind": .string("weekdays"),
            "days": .array(days.map(AgentCLIKit.JSONValue.string)),
            "hour": .number(Double(hour)),
            "minute": .number(Double(minute))
        ]
    }

    func assertInvalid(
        _ arguments: [String: AgentCLIKit.JSONValue],
        parser: ScheduledTaskHostToolRequestParser,
        containing expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try parser.parse(arguments: arguments), file: file, line: line) { error in
            XCTAssertTrue(error.localizedDescription.contains(expectedMessage), file: file, line: line)
        }
    }

    func object(_ value: AgentCLIKit.JSONValue) throws -> [String: AgentCLIKit.JSONValue] {
        guard case .object(let object) = value else {
            throw TestValueError.unexpectedJSON
        }
        return object
    }

    func assertEveryObjectSchemaDeclaresProperties(
        _ value: AgentCLIKit.JSONValue,
        path: String = "inputSchema",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch value {
        case .object(let object):
            if object["type"] == .string("object") {
                XCTAssertNotNil(
                    object["properties"],
                    "Object schema at \(path) must declare root properties for Claude tool loading",
                    file: file,
                    line: line
                )
            }
            for (key, nestedValue) in object {
                assertEveryObjectSchemaDeclaresProperties(
                    nestedValue,
                    path: "\(path).\(key)",
                    file: file,
                    line: line
                )
            }
        case .array(let array):
            for (index, nestedValue) in array.enumerated() {
                assertEveryObjectSchemaDeclaresProperties(
                    nestedValue,
                    path: "\(path)[\(index)]",
                    file: file,
                    line: line
                )
            }
        case .null, .bool, .number, .string:
            break
        }
    }
}

private enum TestValueError: Error {
    case unexpectedJSON
}

private final class ScheduledTaskHostToolTimeZoneBox: @unchecked Sendable {
    var identifier: String

    init(_ identifier: String) {
        self.identifier = identifier
    }
}
