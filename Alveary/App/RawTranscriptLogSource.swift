#if DEBUG
import AgentCLIKit
import Foundation

struct RawTranscriptLogEntry: Identifiable, Equatable {
    let id: String
    let text: String
    let isUserMessage: Bool
}

struct RawTranscriptSource: Hashable {
    let providerID: String
    let providerSessionID: String
    let workingDirectory: String?

    var id: String {
        [providerID, providerSessionID, workingDirectory ?? ""].joined(separator: "\u{1F}")
    }

    init?(providerID: String?, providerSessionID: String?, workingDirectory: String?) {
        guard let providerID, !providerID.isEmpty,
              let providerSessionID, !providerSessionID.isEmpty else {
            return nil
        }
        self.providerID = providerID
        self.providerSessionID = providerSessionID
        self.workingDirectory = workingDirectory
    }

    func fileURL(fileManager: FileManager = .default) -> URL? {
        switch providerID {
        case "claude":
            guard let workingDirectory, !workingDirectory.isEmpty else {
                return nil
            }
            return AgentCLIKit.ClaudePathEncoder.sessionFileURL(
                sessionId: AgentCLIKit.AgentSessionID(rawValue: providerSessionID),
                workingDirectoryPath: workingDirectory
            )
        case "codex":
            return RawTranscriptCodexSessionLocator.sessionFileURL(
                threadID: providerSessionID,
                fileManager: fileManager
            )
        default:
            return nil
        }
    }
}

struct RawTranscriptJSONLineReader {
    private let sourceID: String
    private var pendingData = Data()
    private var offset: UInt64 = 0
    private var nextIndex = 0

    init(sourceID: String) {
        self.sourceID = sourceID
    }

    mutating func readAvailableEntries(from fileURL: URL, fileManager: FileManager = .default) -> [RawTranscriptLogEntry] {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let fileSize = (attributes[.size] as? NSNumber)?.uint64Value else {
            return []
        }

        if fileSize < offset {
            pendingData = Data()
            offset = 0
            nextIndex = 0
        }

        guard fileSize > offset,
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return []
        }
        defer {
            try? handle.close()
        }

        do {
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            offset += UInt64(data.count)
            pendingData.append(data)
            return consumeCompleteEntries()
        } catch {
            return []
        }
    }

    private mutating func consumeCompleteEntries() -> [RawTranscriptLogEntry] {
        var entries: [RawTranscriptLogEntry] = []
        while let newlineIndex = pendingData.firstIndex(of: 0x0A) {
            var lineData = Data(pendingData[..<newlineIndex])
            if lineData.last == 0x0D {
                lineData.removeLast()
            }
            pendingData.removeSubrange(...newlineIndex)
            guard let entry = entry(from: lineData) else {
                continue
            }
            entries.append(entry)
        }
        return entries
    }

    private mutating func entry(from lineData: Data) -> RawTranscriptLogEntry? {
        let trimmed = lineData.trimmingASCIIWhitespace()
        guard !trimmed.isEmpty,
              RawTranscriptJSONFormatter.isValidJSON(trimmed),
              let rawText = String(data: trimmed, encoding: .utf8) else {
            return nil
        }

        let id = "\(sourceID)-\(nextIndex)"
        nextIndex += 1
        return RawTranscriptLogEntry(
            id: id,
            text: RawTranscriptJSONFormatter.displayText(for: trimmed, fallback: rawText),
            isUserMessage: RawTranscriptJSONRoleDetector.isUserMessage(trimmed)
        )
    }
}

private enum RawTranscriptCodexSessionLocator {
    static func sessionFileURL(
        threadID: String,
        codexHomeDirectory: URL = AgentCLIKit.CodexConfigStore.defaultCodexHomeDirectoryURL,
        fileManager: FileManager = .default
    ) -> URL? {
        let sessionsDirectory = codexHomeDirectory.appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let suffix = "\(threadID).jsonl"
        var matches: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent.hasSuffix(suffix) {
            matches.append(fileURL)
        }
        return matches.sorted { $0.path > $1.path }.first
    }
}

private enum RawTranscriptJSONFormatter {
    static func isValidJSON(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    static func displayText(for data: Data, fallback: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let prettyText = String(data: prettyData, encoding: .utf8) else {
            return fallback
        }
        return prettyText
    }
}

private enum RawTranscriptJSONRoleDetector {
    static func isUserMessage(_ data: Data) -> Bool {
        guard let value = try? JSONDecoder().decode(AgentCLIKit.JSONValue.self, from: data) else {
            return false
        }
        return isClaudeUserMessage(value) || isCodexUserMessage(value)
    }

    private static func isClaudeUserMessage(_ value: AgentCLIKit.JSONValue) -> Bool {
        guard case let .object(object) = value else {
            return false
        }
        if object.stringValue("type") == "user" {
            return true
        }
        guard case let .object(message)? = object["message"] else {
            return false
        }
        return message.stringValue("role") == "user"
    }

    private static func isCodexUserMessage(_ value: AgentCLIKit.JSONValue) -> Bool {
        guard case let .object(object) = value else {
            return false
        }

        if object.stringValue("type") == "response_item",
           case let .object(payload)? = object["payload"],
           payload.stringValue("type") == "userMessage" {
            return true
        }

        guard object.stringValue("type") == "event_msg",
              case let .object(payload)? = object["payload"],
              payload.stringValue("type") == "item_completed",
              case let .object(item)? = payload["item"] else {
            return false
        }
        return item.stringValue("type") == "userMessage"
    }
}

private extension [String: AgentCLIKit.JSONValue] {
    func stringValue(_ key: String) -> String? {
        guard case let .string(value)? = self[key], !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension Data {
    func trimmingASCIIWhitespace() -> Data {
        var lowerBound = startIndex
        var upperBound = endIndex

        while lowerBound < upperBound, self[lowerBound].isASCIIWhitespace {
            formIndex(after: &lowerBound)
        }
        while upperBound > lowerBound {
            let previousIndex = index(before: upperBound)
            guard self[previousIndex].isASCIIWhitespace else {
                break
            }
            upperBound = previousIndex
        }

        return Data(self[lowerBound..<upperBound])
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D
    }
}
#endif
