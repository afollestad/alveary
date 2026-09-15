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
    private var reviewers: [AppKitReviewTeamReviewerRowView] = []
    private var findingViews: [String: AppKitReviewTeamNotProposedFindingView] = [:]
    private var actionsView: AppKitReviewTeamRunActionsView?

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

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        prepareLayout(width: newSize.width)
        super.setFrameSize(newSize)
    }

    /// The shell supplies its final content width before Auto Layout reads the stack height.
    func prepareLayout(width: CGFloat) {
        let statusWidth = reviewers.map(\.preferredStatusWidth).max() ?? 0
        for reviewer in reviewers {
            reviewer.prepareLayout(width: max(0, width), statusWidth: statusWidth)
        }
        actionsView?.prepareLayout(width: max(0, width))
        for finding in findingViews.values { finding.prepareLayout(width: max(0, width)) }
    }

    var hasContent: Bool {
        !stack.arrangedSubviews.isEmpty
    }

    var naturalWidth: CGFloat {
        stack.arrangedSubviews.reduce(CGFloat.zero) { width, view in
            guard !(view is AppKitHostToolWidgetDividerView) else { return width }
            let naturalWidth = (view as? AppKitReviewTeamNotProposedFindingView)?.naturalWidth ?? ceil(view.fittingSize.width)
            return max(width, naturalWidth)
        }
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        if self.configuration?.run.id != configuration.run.id {
            expandedRunID = nil
            findingViews = [:]
            reviewers = []
        }
        self.configuration = configuration
        rebuild(configuration)
        prepareLayout(width: bounds.width)
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
        let focusedControl = AppKitReviewTeamFocus.capture(in: self)
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        addTeam(configuration)
        if let explanation = ReviewTeamRunCardPresentation.pauseExplanation(configuration.run) {
            stack.addFullWidthArrangedSubview(AppKitTranscriptWidgetLabelFactory.label(
                explanation, level: .caption, color: .labelColor, typography: configuration.typography, wraps: true
            ))
        }
        if let warning = ReviewTeamRunCardPresentation.partialCompletionWarning(configuration.run) {
            stack.addFullWidthArrangedSubview(AppKitTranscriptWidgetLabelFactory.label(
                warning, level: .caption, color: .labelColor, typography: configuration.typography, wraps: true
            ))
        }
        addNotProposed(configuration)
        addActions(configuration)
        AppKitReviewTeamFocus.restore(focusedControl, in: self)
    }

    func addTeam(_ configuration: Configuration) {
        reviewers = configuration.run.team.enumerated().map { index, member in
            let row = AppKitReviewTeamReviewerRowView(
                member: member,
                model: ReviewTeamRunCardPresentation.modelLabel(providerID: member.providerID, modelOptionID: member.modelOptionID),
                role: member.id == "lead" ? "Lead" : "Peer \(index)",
                status: ReviewTeamRunPresentation.status(for: member, in: configuration.run),
                typography: configuration.typography
            )
            row.identifier = NSUserInterfaceItemIdentifier("reviewer:\(member.id)")
            row.onActivate = { [weak self] in self?.showDetails(reviewerID: member.id) }
            stack.addFullWidthArrangedSubview(row)
            if index < configuration.run.team.count - 1 { stack.setCustomSpacing(0, after: row) }
            return row
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
        let lineHeight = NSLayoutManager().defaultLineHeight(for: typography.nsFont(.caption))
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: ceil(lineHeight) + 6).isActive = true
        button.title = expanded
            ? "Hide \(count) not proposed"
            : "Show \(count) not proposed"
        button.identifier = NSUserInterfaceItemIdentifier("review-not-proposed")
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
        let view = findingViews[finding.id] ?? AppKitReviewTeamNotProposedFindingView(findingID: finding.id)
        findingViews[finding.id] = view
        view.onHeightInvalidated = { [weak self] in self?.onHeightInvalidated?() }
        view.configure(
            finding: finding,
            votes: configuration.run.team.flatMap { member in
                configuration.run.voteReports[member.id]?.votes.filter { $0.findingID == finding.id } ?? []
            },
            reviewers: reviewers,
            typography: configuration.typography
        )
        stack.addFullWidthArrangedSubview(AppKitHostToolWidgetDividerView())
        stack.addFullWidthArrangedSubview(view)
    }

    func addActions(_ configuration: Configuration) {
        let details = AppKitTranscriptHeaderToggleButton()
        details.title = "Run details"
        details.identifier = NSUserInterfaceItemIdentifier("review-run-details")
        details.symbolName = "list.bullet"
        details.font = configuration.typography.nsFont(.caption, weight: .medium)
        details.isBordered = false
        details.target = self
        details.action = #selector(showRunDetails)
        details.setAccessibilityLabel("Run details")
        details.setAccessibilityRole(.button)
        var buttons: [NSButton] = [details]
        let run = configuration.run
        if run.phase.isWorking || run.phase == .awaitingDecision {
            buttons.append(actionButton(RunAction(title: "Cancel review", icon: "xmark", selector: #selector(cancelReview))))
        }
        if run.canRetryFailedReviewers {
            let retry = actionButton(RunAction(
                title: "Retry failed reviewers", icon: "arrow.clockwise", selector: #selector(retryFailedReviewers)
            ))
            retry.toolTip = "Reuse completed reports and retry only the failed reviewers for this phase."
            buttons.append(retry)
        } else if (run.phase == .failed || run.phase == .interrupted) && run.requiresNewRun != true {
            buttons.append(actionButton(RunAction(title: "Retry review", icon: "arrow.clockwise", selector: #selector(retryReview))))
        }
        if run.canContinueWithMajority {
            buttons.append(actionButton(RunAction(
                title: "Continue with majority", icon: "arrow.right", selector: #selector(continueWithMajority), style: .primary
            )))
        }
        let actions = AppKitReviewTeamRunActionsView(buttons: buttons, compactTitles: [
            "Cancel review": "Cancel", "Retry failed reviewers": "Retry failed", "Retry review": "Retry",
            "Continue with majority": "Use majority"
        ])
        actionsView = actions
        if let previous = stack.arrangedSubviews.last {
            stack.setCustomSpacing(12, after: previous)
        }
        stack.addFullWidthArrangedSubview(actions)
    }

    func actionButton(_ action: RunAction) -> NSButton {
        let button = AppKitTranscriptApprovalButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.controlSize = .small
        button.font = configuration?.typography.nsFont(.caption, weight: .medium)
        button.title = action.title
        button.identifier = NSUserInterfaceItemIdentifier("review-action:\(action.title)")
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
        prepareLayout(width: bounds.width)
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
