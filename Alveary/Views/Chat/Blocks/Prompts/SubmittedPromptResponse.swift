import Foundation

struct SubmittedPromptResponse: Identifiable, Equatable {
    let question: String
    let answer: String

    var id: String { question + "\u{0}" + answer }

    static func parse(from summary: String) -> [SubmittedPromptResponse] {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else {
            return []
        }

        let paragraphs = trimmedSummary
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let parsedParagraphs = paragraphs.compactMap(parseParagraph)
        if parsedParagraphs.count == paragraphs.count {
            return parsedParagraphs
        }

        return trimmedSummary
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap(parseLegacyLine)
    }

    private static func parseParagraph(_ paragraph: String) -> SubmittedPromptResponse? {
        let lines = paragraph
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2,
              let questionLine = lines.first,
              let answerLine = lines.dropFirst().first,
              let question = payload(from: questionLine, prefix: "Q: "),
              let answer = payload(from: answerLine, prefix: "A: ") else {
            return nil
        }

        return SubmittedPromptResponse(question: question, answer: answer)
    }

    private static func parseLegacyLine(_ line: String) -> SubmittedPromptResponse? {
        guard let separator = line.range(of: ": ") else {
            return nil
        }

        let question = String(line[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !answer.isEmpty else {
            return nil
        }

        return SubmittedPromptResponse(question: question, answer: answer)
    }

    private static func payload(from line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else {
            return nil
        }

        let payload = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            return nil
        }
        return payload
    }
}
