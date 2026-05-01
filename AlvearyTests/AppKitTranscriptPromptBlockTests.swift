@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptPromptBlockTests: XCTestCase {
    func testPendingPromptShowsQuestionsOptionsAndSubmitStatus() {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(block.renderedText.contains("Agent is asking"))
        XCTAssertTrue(block.renderedText.contains("Pick one"))
        XCTAssertTrue(block.renderedText.contains("Option A"))
        XCTAssertTrue(block.renderedText.contains("Answer 1 more question before submitting."))
        XCTAssertFalse(block.submitButton?.isEnabled ?? true)
    }

    func testPromptQuestionCardOrdersHeaderQuestionThenOptions() throws {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.layoutSubtreeIfNeeded()

        let card = try XCTUnwrap(block.descendants(of: AppKitTranscriptPromptQuestionCardView.self).first)
        let header = try XCTUnwrap(block.visibleTextField("Required"))
        let question = try XCTUnwrap(block.visibleTextField("Pick one"))
        let option = try XCTUnwrap(block.visibleTextField("Option A"))

        XCTAssertLessThan(header.frame(in: card).minY, question.frame(in: card).minY)
        XCTAssertLessThan(question.frame(in: card).minY, option.frame(in: card).minY)
    }

    func testPromptFooterPlacesSubmitBelowQuestionAndStatus() throws {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.layoutSubtreeIfNeeded()

        let questionCard = try XCTUnwrap(block.descendants(of: AppKitTranscriptPromptQuestionCardView.self).first)
        let statusField = try XCTUnwrap(block.visibleTextField("Answer 1 more question before submitting."))
        let submitButton = try XCTUnwrap(block.submitButton)

        XCTAssertGreaterThan(statusField.frame.minY, questionCard.frame.maxY)
        XCTAssertGreaterThan(submitButton.frame.minY, statusField.frame.maxY)
        XCTAssertEqual(submitButton.fittingSize.height, 30)
    }

    func testPendingPromptHugsContentInsteadOfFillingTranscriptWidth() throws {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 720, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.layoutSubtreeIfNeeded()

        let questionCard = try XCTUnwrap(block.descendants(of: AppKitTranscriptPromptQuestionCardView.self).first)
        XCTAssertLessThan(questionCard.frame.width, 520)
    }

    func testOptionControlExposesLabelForAccessibility() throws {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.layoutSubtreeIfNeeded()

        let optionButton = try XCTUnwrap(block.descendants(of: NSButton.self).first { $0.title.isEmpty })
        XCTAssertEqual(optionButton.accessibilityLabel(), "Option A")
        XCTAssertEqual(optionButton.accessibilityHelp(), "Use the smaller row slice.")
    }

    func testSelectionEnablesSubmitAndSubmitsAnswer() async {
        let block = AppKitTranscriptPromptBlockView()
        var submitted: [(question: String, answer: String)] = []
        block.onSubmit = { answers in
            submitted = answers
            return "Q: \(answers[0].question)\nA: \(answers[0].answer)"
        }
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.toggleOption(at: 0, option: promptOption(label: "Option A"))
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(block.submitButton?.isEnabled ?? false)
        await block.submit()
        block.layoutSubtreeIfNeeded()

        XCTAssertEqual(submitted.map(\.answer), ["Option A"])
        XCTAssertTrue(block.renderedText.contains("Submitted responses"))
        XCTAssertTrue(block.renderedText.contains("Option A"))
    }

    func testCustomResponseSerializesTypedTextInsteadOfOtherLabel() async {
        let block = AppKitTranscriptPromptBlockView()
        var submitted: [(question: String, answer: String)] = []
        block.onSubmit = { answers in
            submitted = answers
            return nil
        }
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.toggleOption(at: 0, option: PromptEntry.PromptOption.other)
        block.updateCustomResponse(at: 0, value: "Use AppKit")
        block.layoutSubtreeIfNeeded()

        XCTAssertFalse(block.descendants(of: NSTextField.self).filter { $0.placeholderString == "Enter your response" }.isEmpty)
        await block.submit()

        XCTAssertEqual(submitted.map(\.answer), ["Use AppKit"])
    }

    func testSelectedCustomResponseReplacesOtherLabelWithInputField() throws {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.toggleOption(at: 0, option: PromptEntry.PromptOption.other)
        block.layoutSubtreeIfNeeded()

        let visibleFields = block.visibleTextFields.map(\.stringValue)
        XCTAssertFalse(visibleFields.contains("Other"))
        XCTAssertFalse(visibleFields.contains("Write your own response."))
        XCTAssertNotNil(block.visibleTextFields.first { $0.placeholderString == "Enter your response" })
    }

    func testSelectingOtherDoesNotChangeOptionRowHeight() throws {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.layoutSubtreeIfNeeded()
        let card = try XCTUnwrap(block.descendants(of: AppKitTranscriptPromptQuestionCardView.self).first)
        let originalHeight = try XCTUnwrap(card.optionHeightForTesting(label: "Other"))

        block.toggleOption(at: 0, option: .other)
        block.layoutSubtreeIfNeeded()
        let updatedCard = try XCTUnwrap(block.descendants(of: AppKitTranscriptPromptQuestionCardView.self).first)
        let updatedHeight = try XCTUnwrap(updatedCard.optionHeightForTesting(label: "Other"))

        XCTAssertEqual(updatedHeight, originalHeight, accuracy: 0.5)
    }

    func testTypingCustomResponseDoesNotInvalidateStableHeight() throws {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.toggleOption(at: 0, option: .other)
        block.layoutSubtreeIfNeeded()
        var invalidationCount = 0
        block.onHeightInvalidated = {
            invalidationCount += 1
        }
        let field = try XCTUnwrap(block.visibleTextFields.first { $0.placeholderString == "Enter your response" })

        field.stringValue = "Keep this stable"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))

        XCTAssertEqual(invalidationCount, 0)
    }

    func testOptionRowsExposePressedStateAndWholeRowHitArea() throws {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.layoutSubtreeIfNeeded()
        let card = try XCTUnwrap(block.descendants(of: AppKitTranscriptPromptQuestionCardView.self).first)
        let rowFrame = try XCTUnwrap(card.firstOptionFrameForTesting)

        XCTAssertEqual(card.firstOptionGlyphTextGapForTesting, 8)
        XCTAssertEqual(rowFrame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(rowFrame.width, card.bounds.width, accuracy: 0.5)
        XCTAssertTrue(card.firstOptionHitTestUsesWholeRowForTesting)
        XCTAssertFalse(card.firstOptionOverlayFocusableForTesting)
        XCTAssertNil(card.firstOptionPressedFillForTesting)

        card.setFirstOptionPressedForTesting(true)

        XCTAssertNotNil(card.firstOptionPressedFillForTesting)

        card.clickFirstOptionRowForTesting()

        XCTAssertTrue(block.submitButton?.isEnabled ?? false)
    }

    func testCancelledOptionRowClickDoesNotCommitSelection() throws {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.layoutSubtreeIfNeeded()
        let card = try XCTUnwrap(block.descendants(of: AppKitTranscriptPromptQuestionCardView.self).first)

        card.cancelFirstOptionRowClickForTesting()

        XCTAssertFalse(block.submitButton?.isEnabled ?? true)
    }

    func testNativeOptionControlActivationCommitsSelection() throws {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.layoutSubtreeIfNeeded()
        let card = try XCTUnwrap(block.descendants(of: AppKitTranscriptPromptQuestionCardView.self).first)

        card.activateFirstNativeOptionControlForTesting()

        XCTAssertTrue(block.submitButton?.isEnabled ?? false)
    }

    func testSelectedCustomResponseFieldKeepsTextInputHitTarget() throws {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.toggleOption(at: 0, option: .other)
        block.layoutSubtreeIfNeeded()
        let card = try XCTUnwrap(block.descendants(of: AppKitTranscriptPromptQuestionCardView.self).first)

        XCTAssertTrue(card.customFieldHitTargetForTesting)
    }

    func testSubmittingDisablesSubmitUntilCallbackCompletes() async {
        let block = AppKitTranscriptPromptBlockView()
        var continuation: CheckedContinuation<String?, Never>?
        block.onSubmit = { _ in
            await withCheckedContinuation { continuation = $0 }
        }
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.toggleOption(at: 0, option: promptOption(label: "Option A"))
        block.layoutSubtreeIfNeeded()

        let submitTask = Task { await block.submit() }
        await Task.yield()
        XCTAssertFalse(block.submitButton?.isEnabled ?? true)

        continuation?.resume(returning: nil)
        await submitTask.value
        XCTAssertTrue(block.submitButton?.isEnabled ?? false)
    }

    func testStaleSubmitCompletionDoesNotApplyAfterPromptReconfigure() async {
        let block = AppKitTranscriptPromptBlockView()
        var continuation: CheckedContinuation<String?, Never>?
        block.onSubmit = { _ in
            await withCheckedContinuation { continuation = $0 }
        }
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.toggleOption(at: 0, option: promptOption(label: "Option A"))
        block.layoutSubtreeIfNeeded()

        let submitTask = Task { await block.submit() }
        await Task.yield()
        block.configure(.init(prompt: multiQuestionPrompt(), isBusy: false))
        block.layoutSubtreeIfNeeded()

        continuation?.resume(returning: "Q: Pick one\nA: Stale response")
        await submitTask.value
        block.layoutSubtreeIfNeeded()

        XCTAssertFalse(block.renderedText.contains("Submitted responses"))
        XCTAssertFalse(block.renderedText.contains("Stale response"))
        XCTAssertTrue(block.renderedText.contains("Choose checks"))
    }

    func testSamePromptReconfigurePreservesLocalSelectionState() {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        let prompt = prompt()
        block.configure(.init(prompt: prompt, isBusy: false))
        block.toggleOption(at: 0, option: PromptEntry.PromptOption.other)
        block.updateCustomResponse(at: 0, value: "Keep this answer")
        block.layoutSubtreeIfNeeded()

        block.configure(.init(prompt: prompt, isBusy: true))
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(block.renderedText.contains("Keep this answer"))
        XCTAssertFalse(block.submitButton?.isEnabled ?? true)
    }

    func testSubmittedSummaryRendersStructuredResponses() {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                prompt: prompt(submittedSummary: "Q: Pick one\nA: Option A\n\nQ: Explain why\nA: It keeps the slice small."),
                isBusy: false
            )
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(block.renderedText.contains("Submitted responses"))
        XCTAssertTrue(block.renderedText.contains("Explain why"))
        XCTAssertTrue(block.renderedText.contains("It keeps the slice small."))
        XCTAssertTrue(block.descendants(of: NSButton.self).allSatisfy(\.isHidden))
    }

    func testSubmittedFallbackSummaryKeepsFullHeight() {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 320, height: 1_000)
        block.configure(
            .init(
                prompt: prompt(submittedSummary: "The model accepted an older prompt response format without structured Q and A labels."),
                isBusy: false
            )
        )
        block.layoutSubtreeIfNeeded()

        let summaryField = block.descendants(of: NSTextField.self).first {
            $0.stringValue.hasPrefix("The model accepted")
        }
        XCTAssertNotNil(summaryField)
        XCTAssertLessThanOrEqual(summaryField?.frame.maxY ?? 0, block.intrinsicContentSize.height - promptBlockPadding)
    }

    func testSubmittedResponseLongQuestionWrapsInsteadOfClipping() throws {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 360, height: 1_000)
        let question = "If you could only use one editor forever, which would it be?"
        block.configure(
            .init(
                prompt: prompt(submittedSummary: "Q: \(question)\nA: Neovim"),
                isBusy: false
            )
        )
        block.layoutSubtreeIfNeeded()

        let questionField = try XCTUnwrap(block.visibleTextField(question))
        let answerField = try XCTUnwrap(block.visibleTextField("Neovim"))

        let singleLineHeight = questionField.font.map { NSLayoutManager().defaultLineHeight(for: $0) } ?? 0
        XCTAssertGreaterThan(questionField.frame.height, singleLineHeight)
        XCTAssertGreaterThan(answerField.frame.minY, questionField.frame.maxY)
        XCTAssertLessThanOrEqual(answerField.frame.maxY, block.intrinsicContentSize.height - promptBlockPadding)
    }

    func testSubmittedResponseLongQuestionExpandsBeforeWrapping() throws {
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        let question = "If you could only use one editor forever, which would it be?"
        block.configure(
            .init(
                prompt: prompt(submittedSummary: "Q: \(question)\nA: Neovim"),
                isBusy: false
            )
        )
        block.layoutSubtreeIfNeeded()

        let questionField = try XCTUnwrap(block.visibleTextField(question))
        let singleLineHeight = questionField.font.map { NSLayoutManager().defaultLineHeight(for: $0) } ?? 0

        XCTAssertLessThanOrEqual(questionField.frame.height, singleLineHeight + 1)
    }

    func testQuestionGrowthInvalidatesHeight() {
        let block = AppKitTranscriptPromptBlockView()
        var invalidated = false
        block.onHeightInvalidated = {
            invalidated = true
        }
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt(), isBusy: false))
        block.layoutSubtreeIfNeeded()
        let singleQuestionHeight = block.intrinsicContentSize.height
        invalidated = false

        block.configure(.init(prompt: multiQuestionPrompt(), isBusy: false))
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(invalidated)
        XCTAssertGreaterThan(block.intrinsicContentSize.height, singleQuestionHeight)
    }

    func testIdenticalPromptReconfigureDoesNotRebuildOrInvalidateHeight() {
        let block = AppKitTranscriptPromptBlockView()
        var invalidationCount = 0
        block.onHeightInvalidated = {
            invalidationCount += 1
        }
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        let configuration = AppKitTranscriptPromptBlockView.Configuration(prompt: prompt(), isBusy: false)
        block.configure(configuration)
        block.layoutSubtreeIfNeeded()
        let firstCard = block.descendants(of: AppKitTranscriptPromptQuestionCardView.self).first
        invalidationCount = 0

        block.configure(configuration)
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(block.descendants(of: AppKitTranscriptPromptQuestionCardView.self).first === firstCard)
        XCTAssertEqual(invalidationCount, 0)
    }

    func testBusyPromptDisablesSubmitEvenWhenAnswered() {
        let prompt = prompt()
        let block = AppKitTranscriptPromptBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(prompt: prompt, isBusy: true, selections: [0: ["Option A"]]))
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(block.renderedText.contains("Wait for the current send or turn to finish"))
        XCTAssertFalse(block.submitButton?.isEnabled ?? true)
    }
}

private func prompt(submittedSummary: String? = nil) -> PromptEntry {
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

private func multiQuestionPrompt() -> PromptEntry {
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

private func promptOption(label: String, description: String = "") -> PromptEntry.PromptOption {
    PromptEntry.PromptOption(label: label, description: description)
}

private extension NSView {
    var renderedText: String {
        descendants(of: NSTextField.self).map(\.stringValue).joined(separator: "\n")
            + "\n"
            + descendants(of: NSButton.self).map(\.title).joined(separator: "\n")
    }

    var submitButton: NSButton? {
        descendants(of: NSButton.self).first { $0.title == "Submit" }
    }

    var visibleTextFields: [NSTextField] {
        descendants(of: NSTextField.self).filter { !$0.isEffectivelyHidden }
    }

    func visibleTextField(_ text: String) -> NSTextField? {
        visibleTextFields.first { $0.stringValue == text }
    }

    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }

    var isEffectivelyHidden: Bool {
        if isHidden {
            return true
        }
        return superview?.isEffectivelyHidden ?? false
    }

    func frame(in ancestor: NSView) -> NSRect {
        ancestor.convert(bounds, from: self)
    }
}
