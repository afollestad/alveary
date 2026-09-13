import XCTest

@testable import Alveary

@MainActor
final class PromptSubmissionGate {
    private var continuation: CheckedContinuation<String?, Never>?
    private var released = false
    private var response: String?
    private var entered = false

    func wait() async -> String? {
        if released { return response }
        return await withCheckedContinuation {
            continuation = $0
            entered = true
        }
    }

    func waitForEntry(file: StaticString = #filePath, line: UInt = #line) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !entered, clock.now < deadline { await Task.yield() }
        XCTAssertTrue(entered, "Expected the original submit callback to start", file: file, line: line)
    }

    func release(_ response: String?) {
        self.response = response
        released = true
        continuation?.resume(returning: response)
        continuation = nil
    }
}

@MainActor
extension AppKitTranscriptPromptBlockTests {
    func prompt(submittedSummary: String? = nil) -> PromptEntry {
        PromptEntry(
            id: "prompt-1",
            questions: [
                .init(
                    question: "Pick one",
                    header: "Required",
                    options: [
                        promptOption(label: "Option A", description: "Use the smaller row slice."),
                        promptOption(label: "Option B", description: "Take the broader route.")
                    ],
                    multiSelect: false
                )
            ],
            submittedSummary: submittedSummary
        )
    }

    func multiQuestionPrompt() -> PromptEntry {
        PromptEntry(
            id: "prompt-2",
            questions: prompt().questions + [
                .init(
                    question: "Choose checks",
                    header: nil,
                    options: [
                        promptOption(label: "Build"),
                        promptOption(label: "Focused tests")
                    ],
                    multiSelect: true
                )
            ],
            submittedSummary: nil
        )
    }

    func promptOption(label: String, description: String = "") -> PromptEntry.PromptOption {
        PromptEntry.PromptOption(label: label, description: description)
    }
}
