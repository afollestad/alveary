import AppKit

@MainActor
final class ComposerReasoningSpeedMenuViewController: NSViewController {
    private var selectedSpeedMode: AgentSpeedMode
    private let onSpeedSelected: (AgentSpeedMode) -> Void
    private let onHoverChanged: (Bool) -> Void
    private let onCancel: () -> Void
    private var speedView: ComposerReasoningSpeedMenuView?

    init(
        selectedSpeedMode: AgentSpeedMode,
        onSpeedSelected: @escaping (AgentSpeedMode) -> Void,
        onHoverChanged: @escaping (Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.selectedSpeedMode = selectedSpeedMode
        self.onSpeedSelected = onSpeedSelected
        self.onHoverChanged = onHoverChanged
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = ComposerReasoningMenuMetrics.speedContentSize()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let speedView = ComposerReasoningSpeedMenuView(
            selectedSpeedMode: selectedSpeedMode,
            onSpeedSelected: onSpeedSelected,
            onHoverChanged: onHoverChanged,
            onCancel: onCancel
        )
        self.speedView = speedView
        view = speedView
    }

    func update(selectedSpeedMode: AgentSpeedMode) {
        self.selectedSpeedMode = selectedSpeedMode
        speedView?.update(selectedSpeedMode: selectedSpeedMode)
    }
}

@MainActor
private final class ComposerReasoningSpeedMenuView: AppKitComposerPopoverSurfaceView {
    private var selectedSpeedMode: AgentSpeedMode
    private let onSpeedSelected: (AgentSpeedMode) -> Void
    private let onHoverChanged: (Bool) -> Void
    private let onCancel: () -> Void
    private var rowViews: [ComposerReasoningMenuRowView] = []
    private var trackingArea: NSTrackingArea?

    init(
        selectedSpeedMode: AgentSpeedMode,
        onSpeedSelected: @escaping (AgentSpeedMode) -> Void,
        onHoverChanged: @escaping (Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.selectedSpeedMode = selectedSpeedMode
        self.onSpeedSelected = onSpeedSelected
        self.onHoverChanged = onHoverChanged
        self.onCancel = onCancel
        super.init(frame: NSRect(origin: .zero, size: ComposerReasoningMenuMetrics.speedContentSize()))
        rebuildRows()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(selectedSpeedMode: AgentSpeedMode) {
        self.selectedSpeedMode = selectedSpeedMode
        rebuildRows()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var nextY = ComposerReasoningMenuMetrics.verticalInset
        for row in rowViews {
            row.frame = NSRect(
                x: ComposerReasoningMenuMetrics.horizontalInset,
                y: nextY,
                width: bounds.width - ComposerReasoningMenuMetrics.horizontalInset * 2,
                height: ComposerReasoningMenuMetrics.rowHeight
            )
            nextY += ComposerReasoningMenuMetrics.rowHeight
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged(false)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
            return
        }
        super.keyDown(with: event)
    }

    private func rebuildRows() {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = AgentSpeedMode.allCases.map { speedMode in
            speedRow(for: speedMode)
        }
    }

    private func speedRow(for speedMode: AgentSpeedMode) -> ComposerReasoningMenuRowView {
        let row = ComposerReasoningMenuRowView()
        let isSelected = speedMode == selectedSpeedMode
        row.configure(.init(
            title: speedMode.title,
            iconName: speedMode == .fast ? "bolt" : nil,
            trailingIconName: isSelected ? "checkmark" : nil,
            accessibilityLabel: speedMode.title,
            isSelected: isSelected,
            isEnabled: true,
            action: { [weak self] in
                self?.onSpeedSelected(speedMode)
            },
            hoverAction: nil,
            cancelAction: onCancel
        ))
        addSubview(row)
        return row
    }
}
