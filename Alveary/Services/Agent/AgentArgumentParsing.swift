/// Parses shell-style provider argument text into tokens without shell expansion.
///
/// Alveary uses this for provider extra-args settings and approval-summary command grouping.
/// It accepts quotes and backslash escapes, but intentionally does not perform substitutions,
/// globbing, or environment expansion.
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
