import Foundation

/// Adds launch context without exposing captured review content through persisted errors or debug descriptions.
struct ReviewWorkerIOFailure: Error, Sendable, Equatable, LocalizedError, CustomStringConvertible, CustomDebugStringConvertible {
    enum Stage: String, Sendable {
        case capabilityCheck = "Capability check"
        case execution = "Review execution"
    }

    let stage: Stage
    let failure: ShellIOFailure
    let codexCompletion: ReviewWorkerCodexCompletion.Assessment?

    var errorDescription: String? { description }
    var debugDescription: String { description }

    var description: String {
        var parts = ["\(stage.rawValue) failed (captured stdout: \(failure.result.stdoutData.count) bytes)."]
        if let diagnostic = codexCompletion?.diagnostic { parts.append(diagnostic) }
        parts.append(failure.description)
        return parts.joined(separator: " ")
    }
}
