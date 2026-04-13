extension ConversationViewModel {
    static func threadName(from message: String) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else {
            return nil
        }

        let lowercased = trimmed.lowercased()
        let confirmations: Set<String> = ["y", "yes", "ok", "sure", "yep", "yeah", "yea", "go", "do it", "go ahead"]
        guard !confirmations.contains(lowercased), !trimmed.hasPrefix("/") else {
            return nil
        }
        guard trimmed.count > 50 else {
            return trimmed
        }

        let prefix = trimmed.prefix(50)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[prefix.startIndex..<lastSpace]) + "..."
        }
        return String(prefix) + "..."
    }

    static func formatPromptAnswers(answers: [(question: String, answer: String)]) -> String {
        answers.map { question, answer in
            "For the question '\(question)': \(answer)"
        }
        .joined(separator: "\n")
    }

    static func promptSummary(answers: [(question: String, answer: String)]) -> String {
        answers.map { question, answer in
            let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(trimmedQuestion): \(answer)"
        }
        .joined(separator: "\n")
    }
}

extension Conversation {
    func displayName() -> String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedTitle, !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        if isMain {
            return "Main"
        }

        return "Conversation (\(displayOrder + 1))"
    }
}
