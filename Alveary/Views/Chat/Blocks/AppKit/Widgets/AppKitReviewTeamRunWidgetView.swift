import AppKit

/// Persistent progress and terminal detail for an app-owned collective review run.
@MainActor
final class AppKitReviewTeamRunWidgetView: NSView {
    struct Configuration: Equatable {
        let run: ReviewTeamRun
        let typography: TranscriptTypography
    }

    var onHeightInvalidated: (() -> Void)?

    private let stack = NSStackView()
    private var configuration: Configuration?
    private var expandedRunID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var hasContent: Bool {
        !stack.arrangedSubviews.isEmpty
    }

    var naturalWidth: CGFloat {
        stack.arrangedSubviews.reduce(CGFloat.zero) { max($0, ceil($1.fittingSize.width)) }
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        if self.configuration?.run.id != configuration.run.id {
            expandedRunID = nil
        }
        self.configuration = configuration
        rebuild(configuration)
    }
}

private extension AppKitReviewTeamRunWidgetView {
    struct RunAction {
        let title: String
        let icon: String
        let selector: Selector
        var style: AppKitTranscriptApprovalButtonStyle = .secondary
    }

    func rebuild(_ configuration: Configuration) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        addTeam(configuration)
        if let explanation = ReviewTeamRunPresentation.pauseExplanation(configuration.run) {
            stack.addFullWidthArrangedSubview(AppKitTranscriptWidgetLabelFactory.label(
                explanation, level: .caption, color: .labelColor, typography: configuration.typography, wraps: true
            ))
        }
        if let warning = configuration.run.partialCompletionWarning {
            stack.addFullWidthArrangedSubview(AppKitTranscriptWidgetLabelFactory.label(
                warning, level: .caption, color: .labelColor, typography: configuration.typography, wraps: true
            ))
        }
        addNotProposed(configuration)
        addActions(configuration)
    }

    func addTeam(_ configuration: Configuration) {
        for (index, member) in configuration.run.team.enumerated() {
            let status = ReviewTeamRunPresentation.status(for: member, in: configuration.run)
            let memberStack = NSStackView()
            memberStack.translatesAutoresizingMaskIntoConstraints = false
            memberStack.orientation = .vertical
            memberStack.alignment = .leading
            memberStack.spacing = 2
            let header = NSStackView()
            header.orientation = .horizontal
            header.spacing = 8
            header.addArrangedSubview(AppKitTranscriptWidgetLabelFactory.label(
                ReviewTeamRunPresentation.role(member, in: configuration.run),
                level: .caption, color: .labelColor, typography: configuration.typography
            ))
            let details = NSButton(title: "Details", target: self, action: #selector(showReviewerDetails(_:)))
            details.isBordered = false
            details.controlSize = .small
            details.tag = index
            details.setAccessibilityLabel("Show \(ReviewTeamRunPresentation.role(member, in: configuration.run)) prompts and responses")
            header.addArrangedSubview(details)
            memberStack.addFullWidthArrangedSubview(header)
            memberStack.addFullWidthArrangedSubview(AppKitTranscriptWidgetLabelFactory.label(
                "Requested model: \(member.providerID) · \(member.modelOptionID) — \(status.label)",
                level: .caption,
                color: status.failed ? .systemRed : .secondaryLabelColor,
                typography: configuration.typography,
                wraps: true
            ))
            if let detail = status.detail {
                memberStack.addFullWidthArrangedSubview(AppKitTranscriptWidgetLabelFactory.label(
                    detail,
                    level: .caption,
                    color: .secondaryLabelColor,
                    typography: configuration.typography,
                    wraps: true
                ))
            }
            memberStack.setAccessibilityElement(false)
            memberStack.setAccessibilityRole(.group)
            memberStack.setAccessibilityLabel(
                ["Requested model \(member.providerID) \(member.modelOptionID), \(status.label)", status.detail]
                    .compactMap { $0 }
                    .joined(separator: ". ")
            )
            stack.addFullWidthArrangedSubview(memberStack)
        }
    }

    func addNotProposed(_ configuration: Configuration) {
        guard !configuration.run.phase.isWorking, configuration.run.phase != .awaitingDecision else {
            return
        }
        let findings = notProposedFindings(configuration.run)
        guard !findings.isEmpty else {
            return
        }
        let expanded = expandedRunID == configuration.run.id
        if let previous = stack.arrangedSubviews.last {
            stack.setCustomSpacing(12, after: previous)
        }
        stack.addArrangedSubview(notProposedButton(count: findings.count, expanded: expanded, typography: configuration.typography))
        guard expanded else {
            return
        }
        let reviewers = proposalReviewers(configuration.run.team)
        for finding in findings {
            addNotProposedFinding(finding, reviewers: reviewers, configuration: configuration)
        }
    }

    func notProposedButton(count: Int, expanded: Bool, typography: TranscriptTypography) -> NSButton {
        let button = AppKitTranscriptHeaderToggleButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.font = typography.nsFont(.caption, weight: .medium)
        button.title = expanded
            ? "Hide \(count) not proposed"
            : "Show \(count) not proposed"
        button.symbolName = expanded ? "chevron.up" : "chevron.down"
        button.target = self
        button.action = #selector(toggleNotProposed)
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(
            expanded ? "Hide findings not proposed" : "Show findings not proposed"
        )
        return button
    }

    func notProposedFindings(_ run: ReviewTeamRun) -> [ReviewCanonicalFinding] {
        let acceptedIDs = Set(run.accepted.map(\.finding.id))
        return run.canonical?.findings.filter { !acceptedIDs.contains($0.id) } ?? []
    }

    func proposalReviewers(
        _ team: [ReviewWorkerConfiguration]
    ) -> [PullRequestReviewProposalRecord.Reviewer] {
        team.map {
            PullRequestReviewProposalRecord.Reviewer(
                id: $0.id,
                providerID: $0.providerID,
                modelOptionID: $0.modelOptionID
            )
        }
    }

    func addNotProposedFinding(
        _ finding: ReviewCanonicalFinding,
        reviewers: [PullRequestReviewProposalRecord.Reviewer],
        configuration: Configuration
    ) {
        let findingStack = NSStackView()
        findingStack.translatesAutoresizingMaskIntoConstraints = false
        findingStack.orientation = .vertical
        findingStack.alignment = .leading
        findingStack.spacing = 8
        findingStack.addFullWidthArrangedSubview(AppKitTranscriptWidgetLabelFactory.label(
            "\(finding.path):\(finding.line) — \(finding.body)",
            level: .caption,
            color: .secondaryLabelColor,
            typography: configuration.typography,
            wraps: true
        ))
        let evidence = AppKitReviewProposalVoteEvidenceView()
        evidence.onHeightInvalidated = { [weak self] in self?.onHeightInvalidated?() }
        evidence.configure(
            findingID: finding.id,
            votes: configuration.run.team.flatMap { member in
                configuration.run.voteReports[member.id]?.votes.filter { $0.findingID == finding.id } ?? []
            },
            reviewers: reviewers,
            typography: configuration.typography,
            initiallyExpanded: true
        )
        findingStack.addFullWidthArrangedSubview(evidence)
        stack.addFullWidthArrangedSubview(findingStack)
    }

    func addActions(_ configuration: Configuration) {
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.addArrangedSubview(actionButton(RunAction(title: "Run details", icon: "list.bullet", selector: #selector(showRunDetails))))
        if let previous = stack.arrangedSubviews.last {
            stack.setCustomSpacing(AppKitReviewProposalWidgetView.actionRowSeparation, after: previous)
        }
        stack.addArrangedSubview(actions)
        if configuration.run.phase == .awaitingDecision {
            addPausedActions(configuration)
            return
        }
        if configuration.run.canRetryFailedReviewers {
            let retry = actionButton(RunAction(
                title: "Retry failed reviewers", icon: "arrow.clockwise", selector: #selector(retryFailedReviewers)
            ))
            retry.toolTip = "Reuse completed reports and retry only the failed reviewers for this phase."
            actions.addArrangedSubview(retry)
        }
        let action: RunAction?
        if configuration.run.phase.isWorking {
            action = RunAction(title: "Cancel review", icon: "xmark", selector: #selector(cancelReview))
        } else if (configuration.run.phase == .failed || configuration.run.phase == .interrupted)
            && configuration.run.requiresNewRun != true && !configuration.run.canRetryFailedReviewers {
            action = RunAction(title: "Retry review", icon: "arrow.clockwise", selector: #selector(retryReview))
        } else {
            action = nil
        }
        guard let action else {
            return
        }
        actions.addArrangedSubview(actionButton(action))
    }

    func addPausedActions(_ configuration: Configuration) {
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.addArrangedSubview(actionButton(RunAction(title: "Cancel review", icon: "xmark", selector: #selector(cancelReview))))
        if configuration.run.canRetryFailedReviewers {
            actions.addArrangedSubview(actionButton(RunAction(
                title: "Retry failed reviewers", icon: "arrow.clockwise", selector: #selector(retryFailedReviewers)
            )))
        }
        if configuration.run.canContinueWithMajority {
            actions.addArrangedSubview(actionButton(RunAction(
                title: "Continue with majority", icon: "arrow.right", selector: #selector(continueWithMajority), style: .primary
            )))
        }
        stack.addArrangedSubview(actions)
    }

    func actionButton(_ action: RunAction) -> NSButton {
        let button = AppKitTranscriptApprovalButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.controlSize = .small
        button.title = action.title
        button.icon = .system(action.icon)
        button.actionStyle = action.style
        button.target = self
        button.action = action.selector
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(action.title)
        return button
    }

    @objc
    func showRunDetails() {
        showDetails(reviewerID: nil)
    }

    @objc
    func showReviewerDetails(_ sender: NSButton) {
        guard let run = configuration?.run, run.team.indices.contains(sender.tag) else { return }
        showDetails(reviewerID: run.team[sender.tag].id)
    }

    func showDetails(reviewerID: String?) {
        guard let run = configuration?.run else { return }
        var info: [String: Any] = ["run": run]
        if let reviewerID { info["reviewerID"] = reviewerID }
        NotificationCenter.default.post(name: .reviewTeamDetailsRequested, object: self, userInfo: info)
    }

    @objc
    func toggleNotProposed() {
        guard let configuration else {
            return
        }
        expandedRunID = expandedRunID == configuration.run.id ? nil : configuration.run.id
        rebuild(configuration)
        onHeightInvalidated?()
    }

    @objc
    func cancelReview() {
        post(.reviewTeamCancelRequested)
    }

    @objc
    func retryReview() {
        post(.reviewTeamRetryRequested)
    }

    @objc
    func retryFailedReviewers() {
        post(.reviewTeamRetryFailedRequested)
    }

    @objc
    func continueWithMajority() {
        post(.reviewTeamContinueRequested)
    }

    func post(_ name: Notification.Name) {
        guard let run = configuration?.run else {
            return
        }
        NotificationCenter.default.post(
            name: name,
            object: self,
            userInfo: ["conversationID": run.conversationID, "runID": run.id, "generation": run.generation]
        )
    }
}
