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

    func testHiddenPromptPrefixesPlanModeContextBeforeConfiguredPrompt() throws {
        let configuredPrompt = "Minimal handoff prompt."
        let planModePrefix = "You are currently in plan mode.\n\n"
        let planModeInstruction = "Preserve the active plan/proposal, including whether it is pending, rejected, or ready to implement."

        let prompt = SessionHandoffPromptBuilder.hiddenPrompt(
            configuredPrompt: configuredPrompt,
            steeringPrompt: nil,
            isSteeringEnabled: true,
            isPlanModeHandoff: true
        )

        XCTAssertTrue(prompt.hasPrefix(planModePrefix))
        let instructionRange = try XCTUnwrap(prompt.range(of: planModeInstruction))
        let configuredRange = try XCTUnwrap(prompt.range(of: configuredPrompt))
        XCTAssertLessThan(instructionRange.lowerBound, configuredRange.lowerBound)
        XCTAssertTrue(prompt.hasSuffix(configuredPrompt))
    }

    func testHiddenPromptKeepsPlanModeContextBeforeSteeringContract() throws {
        let configuredPrompt = "Minimal handoff prompt."
        let steeringPrompt = "Focus on prompt builder tests."
        let planModePrefix = "You are currently in plan mode.\n\n"
        let planModeInstruction = "Preserve the active plan/proposal, including whether it is pending, rejected, or ready to implement."

        let prompt = SessionHandoffPromptBuilder.hiddenPrompt(
            configuredPrompt: configuredPrompt,
            steeringPrompt: steeringPrompt,
            isSteeringEnabled: true,
            isPlanModeHandoff: true
        )

        XCTAssertTrue(prompt.hasPrefix(planModePrefix))
        let instructionRange = try XCTUnwrap(prompt.range(of: planModeInstruction))
        let configuredRange = try XCTUnwrap(prompt.range(of: configuredPrompt))
        let steeringRange = try XCTUnwrap(prompt.range(of: "## User Handoff Steering"))
        XCTAssertLessThan(instructionRange.lowerBound, configuredRange.lowerBound)
        XCTAssertLessThan(configuredRange.lowerBound, steeringRange.lowerBound)
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

    func testLocalHistoryFallbackOutputIncludesRestoreContext() {
        let output = SessionHandoffPromptBuilder.localHistoryFallbackOutput(
            restoreContext: "Restoring context from local history."
        )

        XCTAssertTrue(output.hasPrefix("The hidden session handoff agent could not resume the previous provider session."))
        XCTAssertTrue(output.hasSuffix("Restoring context from local history."))
    }

    func testPlanModeLocalHistoryFallbackOutputKeepsPlanModeContextFirst() throws {
        let output = SessionHandoffPromptBuilder.localHistoryFallbackOutput(
            restoreContext: "Restoring context from local history.",
            isPlanModeHandoff: true
        )

        XCTAssertTrue(output.hasPrefix(planModeHandoffPrefix))
        let instructionRange = try XCTUnwrap(output.range(of: planModeHandoffInstruction))
        let fallbackRange = try XCTUnwrap(output.range(of: "The hidden session handoff agent could not resume"))
        XCTAssertLessThan(instructionRange.lowerBound, fallbackRange.lowerBound)
    }
}
