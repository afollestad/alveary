import AppKit

/// Expanded detail for `list_scheduled_tasks`: one compact row per definition, with an
/// Edit action.
///
/// Rows come from Alveary's own scheduled tasks rather than the tool payload, so the row
/// always shows current state — and so it still works for providers that surface only the
/// tool's text fallback instead of its structured content.
@MainActor
final class AppKitScheduledTaskListDetailView: NSView {
    var onEditScheduledTask: ((String) -> Void)?

    /// A grid keeps the state, title, schedule, and action columns aligned across rows,
    /// which a per-row stack cannot do.
    private let grid = NSGridView(views: [])
    /// Reuses the transcript's nested-row connector so the list reads as a hierarchy
    /// under its tool row, matching grouped tools and parallel sub-agents.
    private let connectorView = AppKitTranscriptElbowConnectorView()
    private var lastConfiguration: Configuration?
    private var definitionIDsByButton: [ObjectIdentifier: String] = [:]

    fileprivate struct Configuration: Equatable {
        let rows: [ScheduledTaskListRow]
        let typography: TranscriptTypography
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        grid.translatesAutoresizingMaskIntoConstraints = true
        grid.rowSpacing = 6
        grid.columnSpacing = 12
        grid.xPlacement = .leading
        // The dot has no baseline to align to, so rows center their cells instead.
        grid.rowAlignment = .none
        grid.yPlacement = .center
        grid.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(connectorView)
        addSubview(grid)
        // The tool detail container hands each child a full-width frame with an unbounded
        // height and reads the height back, so the stack must not stretch to fill it.
    }

    override func layout() {
        let metrics = transcriptInlineToolRowMetrics(for: lastConfiguration?.typography ?? TranscriptTypography())
        grid.frame = NSRect(
            x: metrics.detailLeadingInset,
            y: transcriptToolNestedTopSpacing,
            width: ceil(grid.fittingSize.width),
            height: ceil(grid.fittingSize.height)
        )
        grid.layoutSubtreeIfNeeded()
        connectorView.metrics = metrics
        // The container sizes this view from `intrinsicContentSize` after layout, so
        // `bounds` is still the probe height here and would clip the connector.
        connectorView.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: transcriptToolNestedTopSpacing + grid.frame.height
        )
        connectorView.centers = rowCenters()
        super.layout()
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: transcriptToolNestedTopSpacing + ceil(grid.fittingSize.height)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(rows: [ScheduledTaskListRow], typography: TranscriptTypography) {
        let configuration = Configuration(rows: rows, typography: typography)
        guard lastConfiguration != configuration else {
            return
        }
        lastConfiguration = configuration
        rebuild(configuration)
        // Size the grid before the next constraint pass: it translates its autoresizing
        // mask, so a still-zero frame pins its height to 0 while the fresh rows demand
        // spacing and centering, and the engine logs a conflict before `layout()` runs.
        grid.setFrameSize(NSSize(
            width: ceil(grid.fittingSize.width),
            height: ceil(grid.fittingSize.height)
        ))
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    @objc
    private func handleEdit(_ sender: NSButton) {
        guard let definitionID = definitionIDsByButton[ObjectIdentifier(sender)] else {
            return
        }
        onEditScheduledTask?(definitionID)
    }
}

private extension AppKitScheduledTaskListDetailView {
    /// Vertical center of each row's title cell, in this view's coordinates, so the
    /// connector's elbows meet the rows they belong to.
    ///
    /// `NSGridView` is not flipped while this view is, so the centers have to be
    /// converted rather than offset — offsetting inverts the row order and leaves the
    /// connector's trunk stopping at the first row.
    func rowCenters() -> [CGFloat] {
        (0..<grid.numberOfRows).compactMap { index in
            guard let contentView = grid.cell(atColumnIndex: 1, rowIndex: index).contentView else {
                return nil
            }
            return convert(contentView.bounds, from: contentView).midY
        }
    }

    func rebuild(_ configuration: Configuration) {
        while grid.numberOfRows > 0 {
            grid.removeRow(at: 0)
        }
        definitionIDsByButton = [:]

        guard !configuration.rows.isEmpty else {
            grid.addRow(with: emptyStateRow(typography: configuration.typography))
            return
        }

        for row in configuration.rows {
            grid.addRow(with: taskRow(row, typography: configuration.typography))
        }
    }

    /// Without this the expanded detail is blank when nothing is scheduled, which reads as a
    /// broken row rather than an answer. The leading placeholder keeps the label in the title
    /// column, where `rowCenters()` looks for the connector's elbow.
    func emptyStateRow(typography: TranscriptTypography) -> [NSView] {
        let label = AppKitTranscriptWidgetLabelFactory.label(
            "No scheduled tasks",
            level: .caption,
            color: .secondaryLabelColor,
            typography: typography
        )
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return [NSGridCell.emptyContentView, label]
    }

    func taskRow(
        _ row: ScheduledTaskListRow,
        typography: TranscriptTypography
    ) -> [NSView] {
        let dot = AppKitTranscriptWidgetStatusDotView()
        dot.configure(tint: AppKitTranscriptWidgetPalette.statusColor(for: row.state))

        let titleLabel = AppKitTranscriptWidgetLabelFactory.label(
            row.title,
            level: .caption,
            color: .labelColor,
            typography: typography
        )
        // The dot encodes state as color only, so the state has to reach VoiceOver here.
        titleLabel.setAccessibilityLabel("\(row.title), \(row.state.rawValue)")

        let scheduleLabel = AppKitTranscriptWidgetLabelFactory.label(
            row.scheduleSummary,
            level: .caption,
            color: .secondaryLabelColor,
            typography: typography
        )
        // The shared label factory lets text compress; grid columns must instead size to
        // their longest row, so these keep their natural width.
        for label in [titleLabel, scheduleLabel] {
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        return [dot, titleLabel, scheduleLabel, editButton(for: row)]
    }

    func editButton(for row: ScheduledTaskListRow) -> AppKitTranscriptApprovalButton {
        let button = AppKitTranscriptApprovalButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.controlSize = .small
        button.title = "Edit"
        button.actionStyle = .secondary
        button.target = self
        button.action = #selector(handleEdit(_:))
        button.setAccessibilityLabel("Edit \(row.title)")
        definitionIDsByButton[ObjectIdentifier(button)] = row.id
        return button
    }
}
