import AgentCLIKit

@testable import Alveary

func makeAgentReasoningPresentation(
    harnesses: [AgentReasoningPresentation.Harness] = [.testClaude, .testCodex],
    pins: AgentReasoningPins = .init(harnessID: "claude", model: "claude-opus-5-5", effort: "medium"),
    effective: AgentReasoningPresentation.Resolved = .init(harness: .testClaude, model: "claude-opus-5-5", effort: "medium"),
    inheritance: AgentReasoningPresentation.Inheritance? = nil
) -> AgentReasoningPresentation {
    AgentReasoningPresentation(harnesses: harnesses, pins: pins, effective: effective, inheritance: inheritance)
}

/// Inherits Codex's GPT-6-Astra at Medium.
func makeAgentReasoningInheritance(isOffered: Bool) -> AgentReasoningPresentation.Inheritance {
    .init(
        title: "Threads default",
        target: .init(harness: .testCodex, model: "gpt-6-astra", effort: "medium"),
        isOffered: isOffered
    )
}

extension AgentReasoningPresentation.Harness {
    static var testClaude: Self {
        .init(id: "claude", title: "Claude", modelOptions: [
            testModelOption(.claude, "claude-opus-5-5", "Opus 5.5", efforts: ["low", "medium", "high", "max"], defaultEffort: "high"),
            testModelOption(.claude, "claude-haiku", "Haiku", efforts: ["low", "medium"], defaultEffort: "low")
        ])
    }

    static var testCodex: Self {
        .init(id: "codex", title: "Codex", modelOptions: [
            testModelOption(.codex, "gpt-6-astra", "GPT-6-Astra", efforts: ["low", "medium", "high"], defaultEffort: "medium")
        ])
    }

    static var testOpenCode: Self {
        .init(id: "opencode", title: "OpenCode", modelOptions: [
            testModelOption(.opencode, "provider/model", "Model", efforts: ["deep"], defaultEffort: nil),
            testModelOption(.opencode, "provider/other", "Other", efforts: ["quick"], defaultEffort: nil)
        ])
    }

    static var testEmptyOpenCode: Self {
        .init(id: "opencode", title: "OpenCode", modelOptions: [])
    }
}

private func testModelOption(
    _ harness: AgentHarnessID,
    _ id: String,
    _ label: String,
    efforts: [String],
    defaultEffort: String?
) -> AgentModelOption {
    let options = efforts.map { AgentHarnessOption(value: $0, label: $0.capitalized, description: "") }
    return AgentModelOption(
        harnessId: harness,
        id: id,
        model: id,
        label: label,
        supportedEffortOptions: options,
        defaultEffortOption: options.first { $0.value == defaultEffort }
    )
}
