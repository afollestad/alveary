import AgentCLIKit
import Foundation

/// A `get_pr_review_instructions` call, as recorded durably in the transcript.
///
/// The card is what makes the user's standing review preferences visible at the moment they are
/// applied: collapsed it names the pull request being reviewed, expanded it shows the exact
/// instructions the agent received. Both review routes go through the tool, so both get the card.
struct ReviewInstructionsWidgetContent: Equatable {
    enum Status: Equatable {
        /// The call has not returned yet.
        case running
        case loaded
        /// The call landed but its payload carried no readable instructions — Codex emits the
        /// plain-text fallback rather than structured content, and that text *is* the
        /// instructions, so this only covers a payload with neither.
        case loadedWithoutInstructions
        case failed
    }

    /// Parsed from the call's own `url` argument, so the card can name its pull request while
    /// the call is still running.
    let identifier: PullRequestIdentifier?
    let instructions: String?
    let status: Status

    var hasInstructions: Bool {
        guard let instructions else {
            return false
        }
        return !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum ReviewInstructionsWidgetParsing {
    static func content(
        input: String?,
        output: String?,
        isError: Bool
    ) -> ReviewInstructionsWidgetContent? {
        let inputIdentifier = identifier(fromInput: input)
        guard let output else {
            return ReviewInstructionsWidgetContent(
                identifier: inputIdentifier,
                instructions: nil,
                status: isError ? .failed : .running
            )
        }
        guard !isError else {
            return ReviewInstructionsWidgetContent(
                identifier: inputIdentifier,
                instructions: nil,
                status: .failed
            )
        }
        // Claude emits the structured payload as JSON text; Codex emits the plain-text fallback,
        // which for this tool is the instructions themselves.
        let object = HostToolWidgetJSON.object(from: output)
        let instructions = object.flatMap { HostToolWidgetJSON.string($0["instructions"]) }
            ?? plainTextInstructions(output)
        return ReviewInstructionsWidgetContent(
            identifier: inputIdentifier ?? identifier(fromOutput: object),
            instructions: instructions,
            status: instructions == nil ? .loadedWithoutInstructions : .loaded
        )
    }

    /// A result that will not parse as JSON is still a success — it is the text fallback, and the
    /// text is what the agent read.
    private static func plainTextInstructions(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("{") else {
            return nil
        }
        return trimmed
    }

    private static func identifier(fromInput input: String?) -> PullRequestIdentifier? {
        guard let input,
              let object = HostToolWidgetJSON.object(from: input),
              let url = HostToolWidgetJSON.string(object["url"]) else {
            return nil
        }
        return PullRequestURLParser.identifier(from: url)
    }

    private static func identifier(fromOutput object: [String: AgentCLIKit.JSONValue]?) -> PullRequestIdentifier? {
        guard let object,
              let repository = HostToolWidgetJSON.string(object["repository"]),
              let number = HostToolWidgetJSON.integer(object["number"]) else {
            return nil
        }
        return PullRequestIdentifier(nameWithOwner: repository, number: number)
    }
}
