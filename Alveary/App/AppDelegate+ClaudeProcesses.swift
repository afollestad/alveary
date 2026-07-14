import Foundation

struct ClaudeProcessCandidate {
    let pid: Int32
    let sessionId: String

    static func parse(psOutput: String) -> [ClaudeProcessCandidate] {
        psOutput
            .split(whereSeparator: \.isNewline)
            .compactMap(Self.parse(line:))
    }

    private static func parse(line: Substring) -> ClaudeProcessCandidate? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else {
            return nil
        }
        let parts = trimmedLine.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.count == 2,
              let pid = Int32(parts[0]) else {
            return nil
        }
        let command = String(parts[1])
        guard executableBasename(in: command) == "claude",
              let sessionId = sessionId(in: command) else {
            return nil
        }
        return ClaudeProcessCandidate(pid: pid, sessionId: sessionId)
    }

    private static func executableBasename(in command: String) -> String? {
        guard let executable = command.split(whereSeparator: \.isWhitespace).first else {
            return nil
        }
        return executable.split(separator: "/").last.map(String.init)
    }

    private static func sessionId(in command: String) -> String? {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        for (index, token) in tokens.enumerated() {
            switch token {
            case "--resume", "--session-id":
                let nextIndex = index + 1
                guard nextIndex < tokens.count else {
                    continue
                }
                return tokens[nextIndex]
            default:
                if token.hasPrefix("--resume=") {
                    return String(token.dropFirst("--resume=".count))
                }
                if token.hasPrefix("--session-id=") {
                    return String(token.dropFirst("--session-id=".count))
                }
            }
        }
        return nil
    }
}

struct TrackedClaudeProcess {
    let pid: Int32
    let sessionId: String
    let cwd: String
}
