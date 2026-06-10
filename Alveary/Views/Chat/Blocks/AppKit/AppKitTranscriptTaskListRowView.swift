@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptTaskListRowView: NSView {
    struct Configuration: Equatable {
        let task: TaskEntry
        let typography: TranscriptTypography
    }

    var onHeightInvalidated: (() -> Void)?

    private let statusSlot = NSView()
    private let titleField = NSTextField(labelWithString: "")
    private var statusView: NSView?
    private var configuration: Configuration?
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

    var naturalContentWidth: CGFloat {
        taskStatusSlotSize + taskTextSpacing + titleNaturalWidth
    }

    var taskID: String {
        configuration?.task.id ?? ""
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        rebuildStatusView()
        updateTitle()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }
}

extension AppKitTranscriptTaskListRowView {
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        statusSlot.translatesAutoresizingMaskIntoConstraints = true
        addSubview(statusSlot)

        titleField.translatesAutoresizingMaskIntoConstraints = true
        titleField.lineBreakMode = .byWordWrapping
        titleField.maximumNumberOfLines = 0
        titleField.cell?.wraps = true
        titleField.cell?.isScrollable = false
        addSubview(titleField)
    }

    private func rebuildStatusView() {
        statusView?.removeFromSuperview()
        guard let configuration else {
            statusView = nil
            return
        }

        let view: NSView
        switch configuration.task.status {
        case .inProgress:
            let indicator = AppKitStatusIndicatorSpinner()
            indicator.translatesAutoresizingMaskIntoConstraints = true
            indicator.setAccessibilityLabel(configuration.task.status.taskListAccessibilityLabel)
            view = indicator
        case .pending:
            view = statusImageView(systemName: "square", color: .secondaryLabelColor, status: configuration.task.status)
        case .completed:
            view = statusImageView(systemName: "checkmark.square.fill", color: .systemGreen, status: configuration.task.status)
        }

        statusSlot.addSubview(view)
        statusView = view
    }

    private func statusImageView(systemName: String, color: NSColor, status: TaskEntry.Status) -> NSImageView {
        let imageView = AppKitDynamicTintImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = true
        imageView.image = NSImage(systemSymbolName: systemName, accessibilityDescription: status.taskListAccessibilityLabel)
        imageView.setDynamicContentTintColor(color)
        let pointSize = configuration?.typography.size(for: .caption) ?? TranscriptTypography().size(for: .caption)
        imageView.symbolConfiguration = .init(pointSize: pointSize, weight: .semibold)
        imageView.setAccessibilityLabel(status.taskListAccessibilityLabel)
        return imageView
    }

    private func updateTitle() {
        guard let configuration else {
            return
        }

        let task = configuration.task
        let text = task.status == .inProgress ? (task.activeForm ?? task.content) : task.content
        let font = configuration.typography.nsFont(.subheadline, weight: task.status == .inProgress ? .semibold : .regular)
        let color: NSColor = task.status == .completed ? .secondaryLabelColor : .labelColor
        let attributes: [NSAttributedString.Key: Any] = {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            if task.status == .completed {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            return attributes
        }()
        titleField.attributedStringValue = NSAttributedString(string: text, attributes: attributes)
    }

    private func layoutContent() {
        statusSlot.frame = NSRect(x: 0, y: 0, width: taskStatusSlotSize, height: taskStatusSlotSize)
        statusView?.frame = statusViewFrame()

        let textX = taskStatusSlotSize + taskTextSpacing
        let textWidth = max(bounds.width - textX, 0)
        titleField.frame = NSRect(x: textX, y: 0, width: textWidth, height: textHeight(for: textWidth))

        let height = measuredHeight()
        statusSlot.frame.origin.y = max((height - taskStatusSlotSize) / 2, 0)
        statusView?.frame = statusViewFrame()
    }

    private func statusViewFrame() -> NSRect {
        guard statusView is AppKitStatusIndicatorSpinner else {
            return statusSlot.bounds
        }
        let inset = (taskStatusSlotSize - taskProgressIndicatorSize) / 2
        return statusSlot.bounds.insetBy(dx: inset, dy: inset)
    }

    private func measuredHeight() -> CGFloat {
        let textX = taskStatusSlotSize + taskTextSpacing
        let textWidth = max(bounds.width - textX, 0)
        return ceil(max(taskStatusSlotSize, textHeight(for: textWidth)))
    }

    private var titleNaturalWidth: CGFloat {
        let attributedSize = titleField.attributedStringValue.size()
        let rect = titleField.attributedStringValue.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude / 2, height: CGFloat.greatestFiniteMagnitude / 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading, .usesDeviceMetrics]
        )
        return ceil(max(attributedSize.width, rect.width, titleField.fittingSize.width))
    }

    private func textHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return titleField.fittingSize.height
        }

        let cellHeight = titleField.cell?.cellSize(
            forBounds: NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
        ).height ?? 0
        let rect = titleField.attributedStringValue.boundingRect(
            with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude / 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading, .usesDeviceMetrics]
        )
        return ceil(max(rect.height, cellHeight))
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
}

private let taskStatusSlotSize: CGFloat = 16
private let taskProgressIndicatorSize: CGFloat = 14
private let taskTextSpacing: CGFloat = 10
