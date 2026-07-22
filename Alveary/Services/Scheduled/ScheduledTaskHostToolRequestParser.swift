import AgentCLIKit
import CryptoKit
import Foundation

enum ScheduledTaskHostToolRequestError: Error, Equatable, LocalizedError, Sendable {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            message
        }
    }
}

struct ScheduledTaskHostToolRequestParser: Sendable {
    private let defaultTimeZoneIdentifierProvider: @Sendable () -> String
    private let recurrenceCalculator: ScheduledTaskRecurrenceCalculator

    init(
        defaultTimeZoneIdentifierProvider: @escaping @Sendable () -> String = { TimeZone.autoupdatingCurrent.identifier },
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator = ScheduledTaskRecurrenceCalculator()
    ) {
        self.defaultTimeZoneIdentifierProvider = defaultTimeZoneIdentifierProvider
        self.recurrenceCalculator = recurrenceCalculator
    }

    init(
        defaultTimeZoneIdentifier: String,
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator = ScheduledTaskRecurrenceCalculator()
    ) {
        self.init(
            defaultTimeZoneIdentifierProvider: { defaultTimeZoneIdentifier },
            recurrenceCalculator: recurrenceCalculator
        )
    }

    func parse(arguments: [String: AgentCLIKit.JSONValue]) throws -> ScheduledTaskParsedProposalRequest {
        try parse(arguments: arguments, validatesExplicitTimeZone: true)
    }

    func parseRetryIdentity(arguments: [String: AgentCLIKit.JSONValue]) throws -> ScheduledTaskParsedProposalRequest {
        try parse(arguments: arguments, validatesExplicitTimeZone: false)
    }
}

private extension ScheduledTaskHostToolRequestParser {
    func parse(
        arguments: [String: AgentCLIKit.JSONValue],
        validatesExplicitTimeZone: Bool
    ) throws -> ScheduledTaskParsedProposalRequest {
        let object = StrictHostToolObject(arguments, path: "arguments")
        let action = try proposalAction(in: object)

        let request: ScheduledTaskProposalRequest
        var canonicalTimeZoneIdentity: ScheduledTaskCanonicalTimeZoneIdentity?
        switch action {
        case .create:
            try object.requireOnly(["action", "title", "prompt", "schedule"])
            let parsedSchedule = try parseSchedule(
                object.requiredObject("schedule"),
                validatesExplicitTimeZone: validatesExplicitTimeZone
            )
            request = .create(
                title: try object.requiredNonEmptyString("title"),
                prompt: try object.requiredNonEmptyString("prompt"),
                schedule: parsedSchedule.schedule
            )
            canonicalTimeZoneIdentity = parsedSchedule.canonicalTimeZoneIdentity
        case .edit:
            try object.requireOnly(["action", "task_id", "revision", "changes"])
            let parsedChanges = try parseChanges(
                object.requiredObject("changes"),
                validatesExplicitTimeZone: validatesExplicitTimeZone
            )
            request = .edit(
                definitionID: try object.requiredNonEmptyString("task_id"),
                expectedRevision: try object.requiredPositiveInteger("revision"),
                changes: parsedChanges.changes
            )
            canonicalTimeZoneIdentity = parsedChanges.canonicalTimeZoneIdentity
        case .pause, .resume, .delete, .runNow:
            try object.requireOnly(["action", "task_id", "revision"])
            let definitionID = try object.requiredNonEmptyString("task_id")
            let revision = try object.requiredPositiveInteger("revision")
            switch action {
            case .pause:
                request = .pause(definitionID: definitionID, expectedRevision: revision)
            case .resume:
                request = .resume(definitionID: definitionID, expectedRevision: revision)
            case .delete:
                request = .delete(definitionID: definitionID, expectedRevision: revision)
            case .runNow:
                request = .runNow(definitionID: definitionID, expectedRevision: revision)
            case .create, .edit:
                preconditionFailure("Create and edit are handled above")
            }
        }

        return try parsedProposalRequest(request, timeZoneIdentity: canonicalTimeZoneIdentity)
    }
}

private extension ScheduledTaskHostToolRequestParser {
    func parseChanges(
        _ values: [String: AgentCLIKit.JSONValue],
        validatesExplicitTimeZone: Bool
    ) throws -> ScheduledTaskParsedProposalEditChanges {
        let object = StrictHostToolObject(values, path: "arguments.changes")
        try object.requireOnly(["title", "prompt", "schedule"])
        guard !values.isEmpty else {
            throw invalid("arguments.changes must contain title, prompt, or schedule.")
        }
        let parsedSchedule = try object.optionalObject("schedule").map {
            try parseSchedule($0, validatesExplicitTimeZone: validatesExplicitTimeZone)
        }
        return ScheduledTaskParsedProposalEditChanges(
            changes: ScheduledTaskProposalEditChanges(
                title: try object.optionalNonEmptyString("title"),
                prompt: try object.optionalNonEmptyString("prompt"),
                schedule: parsedSchedule?.schedule
            ),
            canonicalTimeZoneIdentity: parsedSchedule?.canonicalTimeZoneIdentity
        )
    }

    func parseSchedule(
        _ values: [String: AgentCLIKit.JSONValue],
        validatesExplicitTimeZone: Bool
    ) throws -> ScheduledTaskParsedProposalSchedule {
        let object = StrictHostToolObject(values, path: "arguments.schedule")
        let kind = try object.requiredString("kind")
        let timeZone = try localTimeZone(
            in: object,
            validatesExplicitTimeZone: validatesExplicitTimeZone
        )
        let recurrence = try parseRecurrence(kind: kind, object: object)

        do {
            try recurrenceCalculator.validate(recurrence, timeZoneIdentifier: timeZone.identifier)
        } catch {
            throw invalid(error.localizedDescription)
        }
        return ScheduledTaskParsedProposalSchedule(
            schedule: ScheduledTaskProposalSchedule(
                recurrence: recurrence,
                timeZoneIdentifier: timeZone.identifier
            ),
            canonicalTimeZoneIdentity: timeZone.canonicalIdentity
        )
    }

    func parseRecurrence(
        kind: String,
        object: StrictHostToolObject
    ) throws -> ScheduledTaskRecurrence {
        switch kind {
        case "once":
            try object.requireOnly(["kind", "at", "time_zone"])
            return .once(try parseDate(object.requiredNonEmptyString("at"), field: "at"))
        case "interval":
            try object.requireOnly(["kind", "minutes", "anchor_at", "time_zone"])
            return .interval(
                minutes: try object.requiredPositiveInteger("minutes"),
                anchor: try parseDate(object.requiredNonEmptyString("anchor_at"), field: "anchor_at")
            )
        case "daily":
            try object.requireOnly(["kind", "hour", "minute", "time_zone"])
            return .daily(
                hour: try object.requiredInteger("hour"),
                minute: try object.requiredInteger("minute")
            )
        case "weekdays":
            try object.requireOnly(["kind", "days", "hour", "minute", "time_zone"])
            return .weekdays(
                days: try weekdayNumbers(object.requiredArray("days")),
                hour: try object.requiredInteger("hour"),
                minute: try object.requiredInteger("minute")
            )
        case "weekly":
            try object.requireOnly(["kind", "weekday", "hour", "minute", "time_zone"])
            return .weekly(
                weekday: try weekdayNumber(object.requiredNonEmptyString("weekday")),
                hour: try object.requiredInteger("hour"),
                minute: try object.requiredInteger("minute")
            )
        case "monthly":
            try object.requireOnly(["kind", "day", "hour", "minute", "time_zone"])
            return .monthly(
                day: try object.requiredInteger("day"),
                hour: try object.requiredInteger("hour"),
                minute: try object.requiredInteger("minute")
            )
        default:
            throw invalid("arguments.schedule.kind is not supported.")
        }
    }

    func localTimeZone(
        in object: StrictHostToolObject,
        validatesExplicitTimeZone: Bool
    ) throws -> (identifier: String, canonicalIdentity: ScheduledTaskCanonicalTimeZoneIdentity) {
        let identifier = defaultTimeZoneIdentifierProvider()
        let explicitTimeZone = try object.optionalNonEmptyString("time_zone")
        if validatesExplicitTimeZone,
           let explicitTimeZone,
           explicitTimeZone != identifier {
            throw invalid("arguments.schedule.time_zone must match the Mac's current local time zone.")
        }
        return (
            identifier,
            explicitTimeZone.map(ScheduledTaskCanonicalTimeZoneIdentity.explicit) ?? .local
        )
    }

    func parseDate(_ value: String, field: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let regular = ISO8601DateFormatter()
        regular.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: value) ?? regular.date(from: value) else {
            throw invalid("arguments.schedule.\(field) must be an RFC 3339 date-time with an offset.")
        }
        return date
    }

    func proposalAction(in object: StrictHostToolObject) throws -> ScheduledTaskProposalAction {
        let actionValue = try object.requiredString("action")
        guard let action = ScheduledTaskProposalAction(rawValue: actionValue) else {
            throw invalid("arguments.action must be one of create, edit, pause, resume, delete, or run_now.")
        }
        return action
    }

    func parsedProposalRequest(
        _ request: ScheduledTaskProposalRequest,
        timeZoneIdentity: ScheduledTaskCanonicalTimeZoneIdentity?
    ) throws -> ScheduledTaskParsedProposalRequest {
        let canonicalValue = canonicalValue(for: request, timeZoneIdentity: timeZoneIdentity)
        let canonicalJSON = try Self.canonicalJSON(canonicalValue)
        return ScheduledTaskParsedProposalRequest(
            request: request,
            canonicalPayloadJSON: canonicalJSON,
            canonicalPayloadHash: Self.sha256(canonicalJSON)
        )
    }

    func weekdayNumber(_ value: String, field: String = "weekday") throws -> Int {
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        guard let index = names.firstIndex(of: value) else {
            throw invalid("arguments.schedule.\(field) must be a lowercase full English weekday name.")
        }
        return index + 1
    }

    func weekdayNumbers(_ values: [AgentCLIKit.JSONValue]) throws -> [Int] {
        guard !values.isEmpty else {
            throw invalid("arguments.schedule.days must contain at least one weekday.")
        }
        let names = try values.enumerated().map { index, value in
            guard case .string(let name) = value else {
                throw invalid("arguments.schedule.days[\(index)] must be a string.")
            }
            return name
        }
        guard Set(names).count == names.count else {
            throw invalid("arguments.schedule.days must not contain duplicate weekdays.")
        }
        return try names.enumerated().map { index, name in
            try weekdayNumber(name, field: "days[\(index)]")
        }.sorted()
    }

    func canonicalValue(
        for request: ScheduledTaskProposalRequest,
        timeZoneIdentity: ScheduledTaskCanonicalTimeZoneIdentity?
    ) -> AgentCLIKit.JSONValue {
        var object: [String: AgentCLIKit.JSONValue] = ["action": .string(request.action.rawValue)]
        switch request {
        case let .create(title, prompt, schedule):
            object["title"] = .string(title)
            object["prompt"] = .string(prompt)
            guard let timeZoneIdentity else {
                preconditionFailure("Create requests must include a schedule time-zone identity")
            }
            object["schedule"] = canonicalValue(for: schedule, timeZoneIdentity: timeZoneIdentity)
        case let .edit(definitionID, expectedRevision, changes):
            object["task_id"] = .string(definitionID)
            object["revision"] = .number(Double(expectedRevision))
            var changeValues: [String: AgentCLIKit.JSONValue] = [:]
            if let title = changes.title {
                changeValues["title"] = .string(title)
            }
            if let prompt = changes.prompt {
                changeValues["prompt"] = .string(prompt)
            }
            if let schedule = changes.schedule {
                guard let timeZoneIdentity else {
                    preconditionFailure("Schedule edits must include a time-zone identity")
                }
                changeValues["schedule"] = canonicalValue(for: schedule, timeZoneIdentity: timeZoneIdentity)
            }
            object["changes"] = .object(changeValues)
        case let .pause(definitionID, expectedRevision),
             let .resume(definitionID, expectedRevision),
             let .delete(definitionID, expectedRevision),
             let .runNow(definitionID, expectedRevision):
            object["task_id"] = .string(definitionID)
            object["revision"] = .number(Double(expectedRevision))
        }
        return .object(object)
    }

    func canonicalValue(
        for schedule: ScheduledTaskProposalSchedule,
        timeZoneIdentity: ScheduledTaskCanonicalTimeZoneIdentity
    ) -> AgentCLIKit.JSONValue {
        var object: [String: AgentCLIKit.JSONValue] = [
            "kind": .string(schedule.recurrence.kind.rawValue),
            "time_zone_source": .string(timeZoneIdentity.source)
        ]
        if case .explicit(let identifier) = timeZoneIdentity {
            object["time_zone"] = .string(identifier)
        }
        switch schedule.recurrence {
        case .once(let date):
            object["at"] = .string(Self.canonicalDate(date))
        case let .interval(minutes, anchor):
            object["minutes"] = .number(Double(minutes))
            object["anchor_at"] = .string(Self.canonicalDate(anchor))
        case let .daily(hour, minute):
            object["hour"] = .number(Double(hour))
            object["minute"] = .number(Double(minute))
        case let .weekdays(days, hour, minute):
            let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            object["days"] = .array(days.map { .string(names[$0 - 1]) })
            object["hour"] = .number(Double(hour))
            object["minute"] = .number(Double(minute))
        case let .weekly(weekday, hour, minute):
            let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            object["weekday"] = .string(names[weekday - 1])
            object["hour"] = .number(Double(hour))
            object["minute"] = .number(Double(minute))
        case let .monthly(day, hour, minute):
            object["day"] = .number(Double(day))
            object["hour"] = .number(Double(hour))
            object["minute"] = .number(Double(minute))
        }
        return .object(object)
    }

    static func canonicalJSON(_ value: AgentCLIKit.JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ScheduledTaskHostToolRequestError.invalidArguments("The scheduling request could not be encoded.")
        }
        return string
    }

    static func canonicalDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func invalid(_ message: String) -> ScheduledTaskHostToolRequestError {
        .invalidArguments(message)
    }
}

private struct ScheduledTaskParsedProposalEditChanges {
    let changes: ScheduledTaskProposalEditChanges
    let canonicalTimeZoneIdentity: ScheduledTaskCanonicalTimeZoneIdentity?
}

private struct ScheduledTaskParsedProposalSchedule {
    let schedule: ScheduledTaskProposalSchedule
    let canonicalTimeZoneIdentity: ScheduledTaskCanonicalTimeZoneIdentity
}

private enum ScheduledTaskCanonicalTimeZoneIdentity {
    case local
    case explicit(String)

    var source: String {
        switch self {
        case .local:
            "local"
        case .explicit:
            "explicit"
        }
    }
}

private struct StrictHostToolObject {
    let values: [String: AgentCLIKit.JSONValue]
    let path: String

    init(_ values: [String: AgentCLIKit.JSONValue], path: String) {
        self.values = values
        self.path = path
    }

    func requireOnly(_ allowedKeys: Set<String>) throws {
        let unknownKeys = Set(values.keys).subtracting(allowedKeys).sorted()
        guard unknownKeys.isEmpty else {
            throw ScheduledTaskHostToolRequestError.invalidArguments(
                "\(path) contains unsupported field(s): \(unknownKeys.joined(separator: ", "))."
            )
        }
    }

    func requiredString(_ key: String) throws -> String {
        guard case .string(let value)? = values[key] else {
            throw invalid("\(path).\(key) must be a string.")
        }
        return value
    }

    func requiredNonEmptyString(_ key: String) throws -> String {
        let value = try requiredString(key).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw invalid("\(path).\(key) must not be empty.")
        }
        return value
    }

    func optionalNonEmptyString(_ key: String) throws -> String? {
        guard values[key] != nil else {
            return nil
        }
        return try requiredNonEmptyString(key)
    }

    func requiredObject(_ key: String) throws -> [String: AgentCLIKit.JSONValue] {
        guard case .object(let value)? = values[key] else {
            throw invalid("\(path).\(key) must be an object.")
        }
        return value
    }

    func requiredArray(_ key: String) throws -> [AgentCLIKit.JSONValue] {
        guard case .array(let value)? = values[key] else {
            throw invalid("\(path).\(key) must be an array.")
        }
        return value
    }

    func optionalObject(_ key: String) throws -> [String: AgentCLIKit.JSONValue]? {
        guard values[key] != nil else {
            return nil
        }
        return try requiredObject(key)
    }

    func requiredInteger(_ key: String) throws -> Int {
        guard case .number(let value)? = values[key],
              value.isFinite,
              value.rounded() == value,
              let integer = Int(exactly: value) else {
            throw invalid("\(path).\(key) must be an integer.")
        }
        return integer
    }

    func requiredPositiveInteger(_ key: String) throws -> Int {
        let value = try requiredInteger(key)
        guard value >= 1 else {
            throw invalid("\(path).\(key) must be at least 1.")
        }
        return value
    }

    private func invalid(_ message: String) -> ScheduledTaskHostToolRequestError {
        .invalidArguments(message)
    }
}
