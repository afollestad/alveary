import XCTest

@testable import Alveary

final class SessionHandoffPromptBuilderTests: XCTestCase {
    func testHiddenPromptReturnsConfiguredPromptWhenSteeringIsDisabled() {
        let configuredPrompt = "Minimal handoff prompt."

        let prompt = SessionHandoffPromptBuilder.hiddenPrompt(
            configuredPrompt: configuredPrompt,
            steeringPrompt: "Focus on tests.",
            isSteeringEnabled: false
        )

        XCTAssertEqual(prompt, configuredPrompt)
    }

    func testHiddenPromptReturnsConfiguredPromptWhenSteeringIsEmpty() {
        let configuredPrompt = "Minimal handoff prompt."

        let prompt = SessionHandoffPromptBuilder.hiddenPrompt(
            configuredPrompt: configuredPrompt,
            steeringPrompt: " \n\t ",
            isSteeringEnabled: true
        )

        XCTAssertEqual(prompt, configuredPrompt)
    }

    func testHiddenPromptAppendsNonCustomizableSteeringContract() {
        let configuredPrompt = "Minimal handoff prompt."
        let steeringPrompt = "Focus on prompt builder tests."

        let prompt = SessionHandoffPromptBuilder.hiddenPrompt(
            configuredPrompt: configuredPrompt,
            steeringPrompt: steeringPrompt,
            isSteeringEnabled: true
        )

        XCTAssertTrue(prompt.hasPrefix(configuredPrompt))
        XCTAssertTrue(prompt.contains("## User Handoff Steering"))
        XCTAssertTrue(prompt.contains("Treat it\nas the primary relevance filter"))
        XCTAssertTrue(prompt.hasSuffix(steeringPrompt))
    }

    func testOutgoingMessageReturnsHandoffOutputWhenSteeringIsDisabled() {
        let output = "Generated handoff output."

        let message = SessionHandoffPromptBuilder.outgoingMessage(
            handoffOutput: output,
            steeringPrompt: "Focus on tests.",
            isSteeringEnabled: false
        )

        XCTAssertEqual(message, output)
    }

    func testOutgoingMessageStripsOuterMarkdownFence() {
        let message = SessionHandoffPromptBuilder.outgoingMessage(
            handoffOutput: "```markdown\nPrimary goal:\n- Continue the work.\n```",
            steeringPrompt: nil,
            isSteeringEnabled: false
        )

        XCTAssertEqual(message, "Primary goal:\n- Continue the work.")
    }

    func testOutgoingMessageKeepsInnerMarkdownFence() {
        let output = "Primary goal:\n```swift\nlet value = true\n```\nContinue."

        let message = SessionHandoffPromptBuilder.outgoingMessage(
            handoffOutput: output,
            steeringPrompt: nil,
            isSteeringEnabled: false
        )

        XCTAssertEqual(message, output)
    }

    func testOutgoingMessageReturnsHandoffOutputWhenSteeringIsEmpty() {
        let output = "Generated handoff output."

        let message = SessionHandoffPromptBuilder.outgoingMessage(
            handoffOutput: output,
            steeringPrompt: " \n\t ",
            isSteeringEnabled: true
        )

        XCTAssertEqual(message, output)
    }

    func testOutgoingMessageAppendsRawSteeringUnderUserPrompt() {
        let output = "Generated handoff output."
        let steeringPrompt = "Focus on prompt builder tests.\nKeep raw formatting."

        let message = SessionHandoffPromptBuilder.outgoingMessage(
            handoffOutput: output,
            steeringPrompt: steeringPrompt,
            isSteeringEnabled: true
        )

        XCTAssertEqual(message, output + "\n\n## User Prompt\n" + steeringPrompt)
    }
}
