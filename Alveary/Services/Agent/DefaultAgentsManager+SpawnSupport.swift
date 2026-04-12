import Foundation

struct PreparedSpawnContext {
    let cliPath: String
    let adapter: AgentAdapter
    let customConfig: ProviderCustomConfig?
    let isResuming: Bool
    let sessionLaunch: SessionLaunchDecision
    let arguments: [String]
    let environment: [String: String]
}

struct LaunchedProcess {
    let process: Process
    let stdin: Pipe
    let stdout: Pipe
    let stderr: Pipe

    var stdoutReader: FileHandle {
        stdout.fileHandleForReading
    }

    var stderrReader: FileHandle {
        stderr.fileHandleForReading
    }

    func closeParentLaunchHandles() {
        stdin.fileHandleForReading.closeFile()
        stdout.fileHandleForWriting.closeFile()
        stderr.fileHandleForWriting.closeFile()
    }

    func closeAllHandles() {
        stdin.fileHandleForWriting.closeFile()
        stdin.fileHandleForReading.closeFile()
        stdout.fileHandleForWriting.closeFile()
        stdout.fileHandleForReading.closeFile()
        stderr.fileHandleForWriting.closeFile()
        stderr.fileHandleForReading.closeFile()
    }
}

struct PublishedRuntime {
    let pid: Int32
    let generation: UUID
}

// Accept shell-style quoting for custom extra args, but intentionally stop short of a
// full shell parser: Alveary does not perform expansions, substitutions, or globbing here.
func parseExtraArgs(_ raw: String) throws -> [String] {
    var parser = ShellStyleArgumentsParser()
    return try parser.parse(raw)
}

private struct ShellStyleArgumentsParser {
    private var arguments: [String] = []
    private var current = ""
    private var activeQuote: Character?
    private var isEscaping = false

    mutating func parse(_ raw: String) throws -> [String] {
        for character in raw {
            consume(character)
        }

        if isEscaping {
            current.append("\\")
        }
        if let activeQuote {
            throw AgentError.spawnFailed("Invalid provider extra args: unmatched \(activeQuote) quote")
        }

        flushCurrentIfNeeded()
        return arguments
    }

    private mutating func consume(_ character: Character) {
        if consumeEscaped(character) || consumeQuote(character) || consumeWhitespace(character) {
            return
        }

        current.append(character)
    }

    private mutating func consumeEscaped(_ character: Character) -> Bool {
        guard isEscaping else {
            return false
        }

        current.append(character)
        isEscaping = false
        return true
    }

    private mutating func consumeQuote(_ character: Character) -> Bool {
        guard character == "\"" || character == "'" else {
            return false
        }

        if activeQuote == character {
            activeQuote = nil
        } else if activeQuote != nil {
            current.append(character)
        } else {
            activeQuote = character
        }
        return true
    }

    private mutating func consumeWhitespace(_ character: Character) -> Bool {
        if character == "\\" {
            isEscaping = true
            return true
        }

        guard character == " " || character == "\t" || character == "\n" else {
            return false
        }

        if activeQuote != nil {
            current.append(character)
        } else {
            flushCurrentIfNeeded()
        }
        return true
    }

    private mutating func flushCurrentIfNeeded() {
        guard !current.isEmpty else {
            return
        }

        arguments.append(current)
        current = ""
    }
}
