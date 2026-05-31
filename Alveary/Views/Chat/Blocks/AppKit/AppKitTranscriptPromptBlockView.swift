@preconcurrency import AppKit
import Foundation

/// AppKit transcript block for `AskUserQuestion`, including live question cards
/// and the submitted-response summary shown after answers are sent.
@MainActor
final class AppKitTranscriptPromptBlockView: NSView {
    struct Configuration: Equatable {
        let prompt: PromptEntry
        let isBusy: Bool
        let selections: [Int: Set<String>]
        let customResponses: [Int: String]
        let bubbleMaxWidth: CGFloat
        let typography: TranscriptTypography

        init(
            prompt: PromptEntry,
            isBusy: Bool,
            selections: [Int: Set<String>] = [:],
            customResponses: [Int: String] = [:],
            bubbleMaxWidth: CGFloat = .infinity,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.prompt = prompt
            self.isBusy = isBusy
            self.selections = selections
            self.customResponses = customResponses
            self.bubbleMaxWidth = bubbleMaxWidth
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?
    var onSubmit: (([(question: String, answer: String)]) async -> String?)?

    private let bubbleView = AppKitFlippedDynamicColorView()
    private let titleField = NSTextField(labelWithString: "")
    private let statusField = NSTextField(labelWithString: "")
    private let submitButton = AppKitPromptSubmitButton()
    private var questionViews: [AppKitTranscriptPromptQuestionCardView] = []
    private var submittedFields: [NSTextField] = []
    private var configuration: Configuration?
    private var selections: [Int: Set<String>] = [:]
    private var customResponses: [Int: String] = [:]
    private var localSubmittedSummary: String?
    private var isSubmitting = false
    private var submissionGeneration = 0
    private var lastMeasuredHeight: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight())
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        let shouldResetLocalState = self.configuration?.prompt.id != configuration.prompt.id
        self.configuration = configuration
        if shouldResetLocalState {
            // Cached AppKit rows can be reused for a different prompt while an async submit is in flight.
            // Bump the generation so stale completions cannot render their summary onto the new prompt.
            submissionGeneration += 1
            isSubmitting = false
            localSubmittedSummary = nil
            selections = configuration.selections
            customResponses = configuration.customResponses
        }
        rebuild()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBubbleAppearance()
    }

    func toggleOption(at index: Int, option: PromptEntry.PromptOption) {
        guard let questions = configuration?.prompt.questions,
              questions.indices.contains(index) else {
            return
        }
        let question = questions[index]
        var current = selections[index] ?? []
        if question.multiSelect {
            if current.contains(option.id) {
                current.remove(option.id)
            } else {
                current.insert(option.id)
            }
        } else {
            current = [option.id]
        }
        selections[index] = current
        if !updateQuestionViewSelectionState(at: index) {
            rebuild()
        }
        updateSubmitState()
        finishLocalPromptStateChange()
    }

    func updateCustomResponse(at index: Int, value: String) {
        customResponses[index] = value
        updateSubmitState()
        finishLocalPromptStateChange()
    }

    func submit() async {
        guard isSubmitEnabled else {
            return
        }
        let answers = promptAnswers()
        let submittedPromptID = configuration?.prompt.id
        submissionGeneration += 1
        let generation = submissionGeneration
        isSubmitting = true
        updateSubmitState()
        let submittedSummary = await onSubmit?(answers)
        guard generation == submissionGeneration, configuration?.prompt.id == submittedPromptID else {
            return
        }
        localSubmittedSummary = submittedSummary
        isSubmitting = false
        rebuild()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = promptBlockCornerRadius
        addSubview(bubbleView)
        [titleField, statusField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = true
            $0.lineBreakMode = .byWordWrapping
            $0.maximumNumberOfLines = 0
            bubbleView.addSubview($0)
        }
        submitButton.translatesAutoresizingMaskIntoConstraints = true
        submitButton.title = "Submit"
        submitButton.target = self
        submitButton.action = #selector(handleSubmit)
        bubbleView.addSubview(submitButton)
        updateBubbleAppearance()
    }

    private func rebuild() {
        questionViews.forEach { $0.removeFromSuperview() }
        submittedFields.forEach { $0.removeFromSuperview() }
        questionViews = []
        submittedFields = []
        guard let configuration else {
            return
        }
        if let effectiveSummary {
            rebuildSubmitted(summary: effectiveSummary, typography: configuration.typography)
        } else {
            rebuildQuestions(configuration)
        }
    }

    private func rebuildQuestions(_ configuration: Configuration) {
        titleField.stringValue = "Agent is asking"
        titleField.font = configuration.typography.nsFont(.headline, weight: .semibold)
        titleField.isHidden = false
        for (index, question) in configuration.prompt.questions.enumerated() {
            let view = AppKitTranscriptPromptQuestionCardView()
            view.onToggleOption = { [weak self] index, option in self?.toggleOption(at: index, option: option) }
            view.onCustomResponseChanged = { [weak self] index, value in self?.updateCustomResponse(at: index, value: value) }
            view.configure(
                .init(
                    index: index,
                    question: question,
                    selections: selections[index] ?? [],
                    customResponse: customResponses[index] ?? "",
                    typography: configuration.typography
                )
            )
            view.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
            bubbleView.addSubview(view)
            questionViews.append(view)
        }
        updateSubmitState()
    }

    private func layoutContent() {
        guard let configuration else {
            return
        }
        let width = bubbleWidth(for: configuration)
        bubbleView.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
        let contentWidth = max(width - (promptBlockPadding * 2), 0)
        var currentY = promptBlockPadding
        layoutTitle(width: contentWidth, currentY: &currentY)
        if effectiveSummary == nil {
            layoutQuestions(width: contentWidth, currentY: &currentY)
            layoutFooter(width: contentWidth, currentY: &currentY)
        } else {
            layoutSubmitted(width: contentWidth, currentY: &currentY)
        }
        bubbleView.frame.size.height = ceil(currentY + promptBlockPadding)
    }

    private func layoutTitle(width: CGFloat, currentY: inout CGFloat) {
        titleField.frame = wrappedTextFrame(for: titleField, originX: promptBlockPadding, originY: currentY, width: width)
        currentY = titleField.frame.maxY + 16
    }

    private func layoutQuestions(width: CGFloat, currentY: inout CGFloat) {
        let cardWidth = synchronizedQuestionCardWidth(maxWidth: width)
        for questionView in questionViews {
            questionView.frame = NSRect(x: promptBlockPadding, y: currentY, width: cardWidth, height: CGFloat.greatestFiniteMagnitude / 2)
            questionView.layoutSubtreeIfNeeded()
            questionView.frame.size.height = questionView.intrinsicContentSize.height
            currentY = questionView.frame.maxY + 16
        }
        if !questionViews.isEmpty {
            currentY -= 16
        }
    }

    private func layoutFooter(width: CGFloat, currentY: inout CGFloat) {
        currentY += 16
        let cardWidth = synchronizedQuestionCardWidth(maxWidth: width)
        if !statusField.isHidden {
            statusField.frame = wrappedTextFrame(for: statusField, originX: promptBlockPadding, originY: currentY, width: cardWidth)
            currentY = statusField.frame.maxY + 8
        }
        submitButton.sizeToFit()
        let submitSize = submitButton.fittingSize
        submitButton.frame = NSRect(
            x: promptBlockPadding + max(cardWidth - submitSize.width, 0),
            y: currentY,
            width: submitSize.width,
            height: submitSize.height
        )
        currentY = submitButton.frame.maxY
    }

    private func bubbleWidth(for configuration: Configuration) -> CGFloat {
        let availableWidth = max(bounds.width, 0)
        let cap = configuration.bubbleMaxWidth.isFinite ? configuration.bubbleMaxWidth : availableWidth
        let maxWidth = min(max(cap, 0), availableWidth)
        let contentWidth = idealContentWidth(for: configuration, maxWidth: max(maxWidth - (promptBlockPadding * 2), 0))
        return min(contentWidth + (promptBlockPadding * 2), maxWidth)
    }

    private func synchronizedQuestionCardWidth(maxWidth: CGFloat) -> CGFloat {
        guard let configuration else {
            return min(appKitPromptMinimumWidth, maxWidth)
        }
        return appKitPromptIdealQuestionCardWidth(for: configuration.prompt.questions, typography: configuration.typography, maxWidth: maxWidth)
    }

    private func idealContentWidth(for configuration: Configuration, maxWidth: CGFloat) -> CGFloat {
        let titleWidth = titleField.fittingSize.width
        if let effectiveSummary {
            let submittedWidth = submittedPromptWidth(summary: effectiveSummary, typography: configuration.typography)
            return min(max(appKitPromptMinimumWidth, titleWidth, submittedWidth), maxWidth)
        }
        let questionWidth = appKitPromptIdealQuestionCardWidth(
            for: configuration.prompt.questions,
            typography: configuration.typography,
            maxWidth: maxWidth
        )
        return min(max(appKitPromptMinimumWidth, titleWidth, questionWidth), maxWidth)
    }

    private var effectiveSummary: String? {
        configuration?.prompt.submittedSummary ?? localSubmittedSummary
    }

    private var isSubmitEnabled: Bool {
        guard let configuration else {
            return false
        }
        return !configuration.isBusy && !isSubmitting && configuration.prompt.questions.enumerated().allSatisfy { index, question in
            isQuestionAnswered(question, at: index)
        }
    }

    private func updateSubmitState() {
        guard let configuration else {
            return
        }
        submitButton.isHidden = false
        submitButton.isEnabled = isSubmitEnabled
        let unansweredCount = configuration.prompt.questions.enumerated().filter { index, question in
            !isQuestionAnswered(question, at: index)
        }.count
        if configuration.isBusy {
            statusField.stringValue = "Wait for the current send or turn to finish before sending your selection."
        } else if unansweredCount > 0 {
            let noun = unansweredCount == 1 ? "question" : "questions"
            statusField.stringValue = "Answer \(unansweredCount) more \(noun) before submitting."
        } else {
            statusField.stringValue = ""
        }
        statusField.isHidden = statusField.stringValue.isEmpty
        statusField.font = configuration.typography.nsFont(.caption)
        statusField.textColor = .secondaryLabelColor
    }

    private func updateQuestionViewSelectionState(at index: Int) -> Bool {
        guard questionViews.indices.contains(index) else {
            return false
        }
        return questionViews[index].updateSelectionState(
            selections: selections[index] ?? [],
            customResponse: customResponses[index] ?? ""
        )
    }

    private func finishLocalPromptStateChange() {
        needsLayout = true
    }

    private func isQuestionAnswered(_ question: PromptEntry.PromptQuestion, at index: Int) -> Bool {
        let selected = selections[index] ?? []
        guard question.multiSelect ? !selected.isEmpty : selected.count == 1 else {
            return false
        }
        if selected.contains(PromptEntry.PromptOption.customResponseID) {
            return trimmedCustomResponse(at: index) != nil
        }
        return true
    }

    private func promptAnswers() -> [(question: String, answer: String)] {
        guard let configuration else {
            return []
        }
        return configuration.prompt.questions.enumerated().compactMap { index, question in
            guard let selected = selections[index], !selected.isEmpty else {
                return nil
            }
            let answers = question.renderedOptions.compactMap { option -> String? in
                guard selected.contains(option.id) else {
                    return nil
                }
                return option.isCustomResponse ? trimmedCustomResponse(at: index) : option.label
            }
            return (question.question, answers.joined(separator: ", "))
        }
    }

    private func trimmedCustomResponse(at index: Int) -> String? {
        let trimmed = (customResponses[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func measuredHeight() -> CGFloat {
        if bubbleView.frame.height > 0, bubbleView.frame.height < CGFloat.greatestFiniteMagnitude / 4 {
            return ceil(bubbleView.frame.height)
        }
        return ceil(titleField.fittingSize.height + questionViews.reduce(CGFloat.zero) { $0 + $1.intrinsicContentSize.height } + 80)
    }

    private func updateBubbleAppearance() {
        bubbleView.setLayerFillColor(.secondaryLabelColor, alpha: 0.08)
    }

    private func invalidateTranscriptHeight(force: Bool) {
        let newHeight = measuredHeight()
        guard force || abs(newHeight - lastMeasuredHeight) > 0.5 else {
            return
        }
        lastMeasuredHeight = newHeight
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }

    private func childHeightInvalidated() {
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    @objc private func handleSubmit() {
        Task { [weak self] in
            await self?.submit()
        }
    }
}

private extension AppKitTranscriptPromptBlockView {
    func rebuildSubmitted(summary: String, typography: TranscriptTypography) {
        titleField.stringValue = "Submitted responses"
        titleField.font = typography.nsFont(.headline, weight: .semibold)
        titleField.isHidden = false
        statusField.isHidden = true
        submitButton.isHidden = true
        let responses = SubmittedPromptResponse.parse(from: summary)
        if responses.isEmpty {
            addSubmittedField(summary, font: typography.nsFont(.body), color: .secondaryLabelColor)
        } else {
            for response in responses {
                addSubmittedField(response.question, font: typography.nsFont(.subheadline, weight: .semibold), color: .secondaryLabelColor)
                addSubmittedField(response.answer, font: typography.nsFont(.body), color: .labelColor)
            }
        }
    }

    func addSubmittedField(_ text: String, font: NSFont, color: NSColor) {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = true
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.font = font
        field.textColor = color
        bubbleView.addSubview(field)
        submittedFields.append(field)
    }

    func layoutSubmitted(width: CGFloat, currentY: inout CGFloat) {
        for (index, field) in submittedFields.enumerated() {
            field.frame = wrappedTextFrame(for: field, originX: promptBlockPadding, originY: currentY, width: width)
            let isAnswer = index % 2 == 1
            let isLastField = index == submittedFields.indices.last
            let spacing = isLastField ? 0 : (isAnswer ? promptSubmittedPairSpacing : 2)
            currentY = field.frame.maxY + spacing
        }
    }

    func submittedPromptWidth(summary: String, typography: TranscriptTypography) -> CGFloat {
        let responses = SubmittedPromptResponse.parse(from: summary)
        if responses.isEmpty {
            return appKitPromptStringWidth(summary, font: typography.nsFont(.body))
        }
        return responses.reduce(CGFloat.zero) { partialResult, response in
            max(
                partialResult,
                appKitPromptStringWidth(response.question, font: typography.nsFont(.subheadline, weight: .semibold)),
                appKitPromptStringWidth(response.answer, font: typography.nsFont(.body))
            )
        }
    }

    func wrappedTextFrame(for field: NSTextField, originX: CGFloat, originY: CGFloat, width: CGFloat) -> NSRect {
        NSRect(x: originX, y: originY, width: width, height: wrappedTextHeight(for: field, width: width))
    }

    func wrappedTextHeight(for field: NSTextField, width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return ceil(field.fittingSize.height)
        }
        return appKitPromptWrappedTextHeight(for: field, width: width)
    }
}

let appKitPromptMinimumWidth: CGFloat = 260
