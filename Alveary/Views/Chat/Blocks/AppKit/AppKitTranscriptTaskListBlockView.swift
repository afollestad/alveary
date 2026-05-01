@preconcurrency import AppKit
import Foundation
import QuartzCore

@MainActor
final class AppKitTranscriptTaskListBlockView: NSView {
    struct Configuration: Equatable {
        let tasks: [TaskEntry]
        let bubbleMaxWidth: CGFloat
        let typography: TranscriptTypography

        init(
            tasks: [TaskEntry],
            bubbleMaxWidth: CGFloat = .infinity,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.tasks = tasks
            self.bubbleMaxWidth = bubbleMaxWidth
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?

    var taskRowIDsForTesting: [String] {
        rowViews.map(\.taskID)
    }

    var hasPendingRowAnimationsForTesting: Bool {
        !pendingRowAnimationStartFramesByID.isEmpty
    }

    func activeRowAnimationTargetFrameForTesting(id: String) -> NSRect? {
        activeRowAnimationTargetFramesByID[id]
    }

    var rowSpacingForTesting: CGFloat {
        taskListRowSpacing
    }

    func taskRowForTesting(id: String) -> AppKitTranscriptTaskListRowView? {
        rowViewsByID[id]
    }

    private let bubbleView = AppKitFlippedDynamicColorView()
    private let titleField = NSTextField(labelWithString: "Tasks")
    private var rowViews: [AppKitTranscriptTaskListRowView] = []
    private var rowViewsByID: [String: AppKitTranscriptTaskListRowView] = [:]
    private var configuration: Configuration?
    private var lastMeasuredHeight: CGFloat = -1
    private var pendingRowAnimationStartFramesByID: [String: NSRect] = [:]
    private var activeRowAnimationTargetFramesByID: [String: NSRect] = [:]
    private var rowAnimationToken = UUID()

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
        rowAnimationToken = UUID()
        activeRowAnimationTargetFramesByID = [:]
        let previousConfiguration = self.configuration
        self.configuration = configuration
        rebuildRows(previousConfiguration: previousConfiguration)
        updateAppearance()
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
        updateAppearance()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, !pendingRowAnimationStartFramesByID.isEmpty {
            needsLayout = true
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = chatBlockCornerRadius
        addSubview(bubbleView)

        titleField.translatesAutoresizingMaskIntoConstraints = true
        titleField.lineBreakMode = .byWordWrapping
        titleField.maximumNumberOfLines = 0
        bubbleView.addSubview(titleField)
        updateAppearance()
    }

    private func rebuildRows(previousConfiguration: Configuration?) {
        guard let configuration else {
            rowViews = []
            rowViewsByID = [:]
            pendingRowAnimationStartFramesByID = [:]
            activeRowAnimationTargetFramesByID = [:]
            return
        }

        titleField.font = configuration.typography.nsFont(.headline)
        let previousFramesByID = shouldAnimateRowReorder(previousConfiguration: previousConfiguration) ?
            Dictionary(uniqueKeysWithValues: rowViews.map { ($0.taskID, $0.frame) }.filter { !$0.0.isEmpty && !$0.1.isEmpty }) :
            [:]
        let liveIDs = Set(configuration.tasks.map(\.id))
        for taskID in rowViewsByID.keys.filter({ !liveIDs.contains($0) }) {
            guard let row = rowViewsByID[taskID] else {
                continue
            }
            row.removeFromSuperview()
            rowViewsByID[taskID] = nil
        }

        rowViews = configuration.tasks.taskListPresentationOrder.map { task in
            let row = rowViewsByID[task.id] ?? AppKitTranscriptTaskListRowView()
            row.configure(.init(task: task, typography: configuration.typography))
            row.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
            if row.superview !== bubbleView {
                bubbleView.addSubview(row)
            }
            rowViewsByID[task.id] = row
            return row
        }
        pendingRowAnimationStartFramesByID = previousFramesByID
    }

    private func layoutContent() {
        guard let configuration, bounds.width > 0 else {
            return
        }

        let width = bubbleWidth(for: configuration)
        bubbleView.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
        let contentWidth = max(width - (chatBlockPadding * 2), 0)
        var currentY = chatBlockPadding

        titleField.frame = NSRect(x: chatBlockPadding, y: currentY, width: contentWidth, height: CGFloat.greatestFiniteMagnitude / 2)
        titleField.sizeToFit()
        titleField.frame.size.width = contentWidth
        currentY = titleField.frame.maxY + taskListRowSpacing

        var rowFrameUpdates: [(row: AppKitTranscriptTaskListRowView, finalFrame: NSRect)] = []
        for row in rowViews {
            let frame = NSRect(x: chatBlockPadding, y: currentY, width: contentWidth, height: CGFloat.greatestFiniteMagnitude / 2)
            if let activeTargetFrame = activeRowAnimationTargetFramesByID[row.taskID],
               abs(activeTargetFrame.width - frame.width) <= 0.5 {
                rowFrameUpdates.append((row: row, finalFrame: activeTargetFrame))
                currentY = activeTargetFrame.maxY + taskListRowSpacing
                continue
            }

            row.frame = frame
            row.layoutSubtreeIfNeeded()
            row.frame.size.height = row.intrinsicContentSize.height
            rowFrameUpdates.append((row: row, finalFrame: row.frame))
            currentY = row.frame.maxY + taskListRowSpacing
        }

        if !rowViews.isEmpty {
            currentY -= taskListRowSpacing
        }
        bubbleView.frame.size.height = currentY + chatBlockPadding
        deferPendingRowAnimations(rowFrameUpdates)
    }

    private func bubbleWidth(for configuration: Configuration) -> CGFloat {
        let availableWidth = max(bounds.width, 0)
        let cap = configuration.bubbleMaxWidth.isFinite ? configuration.bubbleMaxWidth : availableWidth
        let naturalWidth = max(titleField.fittingSize.width, rowViews.map(\.naturalContentWidth).max() ?? 0) +
            (chatBlockPadding * 2)
        return min(max(naturalWidth, 0), max(cap, 0), availableWidth)
    }

    private func updateAppearance() {
        bubbleView.setLayerFillColor(.secondaryLabelColor, alpha: 0.08)
    }

    private func measuredHeight() -> CGFloat {
        if bubbleView.frame.height > 0, bubbleView.frame.height < CGFloat.greatestFiniteMagnitude / 4 {
            return ceil(bubbleView.frame.height)
        }
        let rowHeight = rowViews.reduce(CGFloat.zero) { $0 + $1.intrinsicContentSize.height }
        let spacing = rowViews.isEmpty ? 0 : CGFloat(rowViews.count) * taskListRowSpacing
        return ceil((chatBlockPadding * 2) + titleField.fittingSize.height + rowHeight + spacing)
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

    private func shouldAnimateRowReorder(previousConfiguration: Configuration?) -> Bool {
        guard let previousConfiguration,
              rowViews.contains(where: { !$0.frame.isEmpty })
        else {
            return false
        }
        return previousConfiguration.tasks != configuration?.tasks
    }

    private func deferPendingRowAnimations(_ updates: [(row: AppKitTranscriptTaskListRowView, finalFrame: NSRect)]) {
        guard !pendingRowAnimationStartFramesByID.isEmpty else {
            return
        }
        guard window != nil, bounds.width > 0 else {
            return
        }
        let animations = updates.compactMap { update -> TaskListRowFrameAnimation? in
            guard let startFrame = pendingRowAnimationStartFramesByID[update.row.taskID],
                  startFrame.width > 0,
                  startFrame.height > 0,
                  startFrame != update.finalFrame else {
                return nil
            }
            return TaskListRowFrameAnimation(row: update.row, startFrame: startFrame, finalFrame: update.finalFrame)
        }
        pendingRowAnimationStartFramesByID = [:]
        guard !animations.isEmpty else {
            return
        }

        activeRowAnimationTargetFramesByID = Dictionary(uniqueKeysWithValues: animations.map { ($0.row.taskID, $0.finalFrame) })
        animations.forEach { animation in
            animation.row.frame = animation.startFrame
        }

        rowAnimationToken = UUID()
        let token = rowAnimationToken
        DispatchQueue.main.async { [weak self] in
            self?.runDeferredRowAnimations(animations, token: token)
        }
    }

    private func runDeferredRowAnimations(
        _ animations: [TaskListRowFrameAnimation],
        token: UUID
    ) {
        guard rowAnimationToken == token, window != nil else {
            if rowAnimationToken == token {
                finishRowAnimations(animations)
            }
            return
        }
        let requestedAnimations = animations
        let liveRows = Set(rowViews.map(ObjectIdentifier.init))
        let animations = requestedAnimations.filter { liveRows.contains(ObjectIdentifier($0.row)) }
        guard !animations.isEmpty else {
            finishRowAnimations(requestedAnimations)
            return
        }
        // Rows are configured into their new visual state before this runs.
        // Deferring the frame interpolation keeps measurement/layout passes final,
        // then visibly moves checked items into the sorted slot on the next turn.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = appExpansionAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for animation in animations {
                animation.row.animator().frame = animation.finalFrame
            }
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.rowAnimationToken == token else {
                    return
                }
                self.finishRowAnimations(animations)
            }
        }
    }

    private func finishRowAnimations(_ animations: [TaskListRowFrameAnimation]) {
        for animation in animations {
            if activeRowAnimationTargetFramesByID[animation.row.taskID] == animation.finalFrame {
                activeRowAnimationTargetFramesByID[animation.row.taskID] = nil
            }
            animation.row.frame = animation.finalFrame
        }
    }
}

private let taskListRowSpacing: CGFloat = 10

private struct TaskListRowFrameAnimation {
    let row: AppKitTranscriptTaskListRowView
    let startFrame: NSRect
    let finalFrame: NSRect
}
