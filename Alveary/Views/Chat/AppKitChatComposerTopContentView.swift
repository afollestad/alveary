import AgentCLIKit
import AppKit

enum AppKitChatComposerTopContentSeverity {
    case warning
    case error
    case info
}

/// Native owner for the composer content that sits above the editor.
///
/// The production AppKit composer panel uses this view for last-turn errors,
/// session-continuity notices, and staged-context banners so those rows measure
/// and hit-test in the same coordinate space as the editor and action row.
@MainActor
final class AppKitChatComposerTopContentView: NSView {
    struct Configuration {
        var items: [Item]
        var ticksGoalElapsedTime: Bool

        init(items: [Item], ticksGoalElapsedTime: Bool = true) {
            self.items = items
            self.ticksGoalElapsedTime = ticksGoalElapsedTime
        }

        static var empty: Configuration {
            Configuration(items: [])
        }
    }

    enum Item {
        case goalStatus(GoalStatusConfiguration)
        case inlineBanner(InlineBannerConfiguration)
        case stagedContext(StagedContextConfiguration)
    }

    struct GoalStatusConfiguration {
        let snapshot: AgentGoalSnapshot
        let actionError: String?
        let onPause: (() -> Void)?
        let onResume: (() -> Void)?
        let onDelete: (() -> Void)?
        let onRestartTerminal: (() -> Void)?
        let isRestartTerminalEnabled: Bool
        let restartTerminalDisabledTooltip: String?
        let onDismissTerminal: (() -> Void)?

        init(
            snapshot: AgentGoalSnapshot,
            actionError: String?,
            onPause: (() -> Void)?,
            onResume: (() -> Void)?,
            onDelete: (() -> Void)?,
            onRestartTerminal: (() -> Void)? = nil,
            isRestartTerminalEnabled: Bool = true,
            restartTerminalDisabledTooltip: String? = nil,
            onDismissTerminal: (() -> Void)?
        ) {
            self.snapshot = snapshot
            self.actionError = actionError
            self.onPause = onPause
            self.onResume = onResume
            self.onDelete = onDelete
            self.onRestartTerminal = onRestartTerminal
            self.isRestartTerminalEnabled = isRestartTerminalEnabled
            self.restartTerminalDisabledTooltip = restartTerminalDisabledTooltip
            self.onDismissTerminal = onDismissTerminal
        }
    }

    struct InlineBannerConfiguration {
        let message: String
        let severity: AppKitChatComposerTopContentSeverity
        let actionTitle: String?
        let onAction: (() -> Void)?
        let onDismiss: (() -> Void)?
    }

    struct StagedContextConfiguration {
        let context: String
        let onDismiss: () -> Void
    }

    private var itemViews: [AppKitChatComposerTopContentItemView] = []
    private let goalElapsedClock: GoalElapsedDisplayClock
    private var configuration: Configuration = .empty
    private var currentGoalSnapshot: AgentGoalSnapshot?
    private var goalElapsedTimer: Timer?

    override init(frame frameRect: NSRect) {
        goalElapsedClock = GoalElapsedDisplayClock()
        super.init(frame: frameRect)
    }

    init(
        frame frameRect: NSRect = .zero,
        goalElapsedTimeProvider: @escaping GoalElapsedDisplayClock.TimeProvider
    ) {
        goalElapsedClock = GoalElapsedDisplayClock(now: goalElapsedTimeProvider)
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        goalElapsedClock = GoalElapsedDisplayClock()
        super.init(coder: coder)
    }

    deinit {
        MainActor.assumeIsolated {
            stopGoalElapsedTimer()
        }
    }

    var hasContent: Bool {
        !itemViews.isEmpty
    }

    var isGoalElapsedTimerRunningForTesting: Bool {
        goalElapsedTimer != nil
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(for: bounds.width))
    }

    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(for: bounds.width))
    }

    func configure(_ configuration: Configuration) {
        self.configuration = configuration
        currentGoalSnapshot = configuration.goalSnapshot
        let displayElapsedSeconds = goalElapsedClock.synchronize(with: currentGoalSnapshot)
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = configuration.items.map { item in
            let view = AppKitChatComposerTopContentItemView()
            view.configure(item, goalDisplayElapsedSeconds: item.isGoalStatus ? displayElapsedSeconds : nil)
            addSubview(view)
            return view
        }
        isHidden = itemViews.isEmpty
        invalidateIntrinsicContentSize()
        needsLayout = true
        updateGoalElapsedTimer()
    }

    override func layout() {
        super.layout()
        var currentY: CGFloat = 0
        for (index, itemView) in itemViews.enumerated() {
            if index > 0 {
                currentY += Self.itemSpacing
            }
            let height = itemView.measuredHeight(for: bounds.width)
            itemView.frame = NSRect(x: 0, y: currentY, width: bounds.width, height: height)
            currentY += height
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        itemViews.forEach { $0.updateAppearance() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateGoalElapsedTimer()
    }

    private func measuredHeight(for width: CGFloat) -> CGFloat {
        guard !itemViews.isEmpty else {
            return 0
        }
        let itemHeight = itemViews.reduce(CGFloat(0)) { partial, itemView in
            partial + itemView.measuredHeight(for: width)
        }
        return ceil(itemHeight + CGFloat(max(itemViews.count - 1, 0)) * Self.itemSpacing)
    }

    private func updateGoalElapsedTimer() {
        guard configuration.ticksGoalElapsedTime,
              currentGoalSnapshot?.status == .active,
              window != nil else {
            stopGoalElapsedTimer()
            return
        }
        guard goalElapsedTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshGoalElapsedMetadata()
            }
        }
        goalElapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopGoalElapsedTimer() {
        goalElapsedTimer?.invalidate()
        goalElapsedTimer = nil
    }

    private func refreshGoalElapsedMetadata() {
        guard configuration.ticksGoalElapsedTime,
              let currentGoalSnapshot,
              currentGoalSnapshot.status == .active else {
            stopGoalElapsedTimer()
            return
        }
        let displayElapsedSeconds = goalElapsedClock.tickElapsed(for: currentGoalSnapshot)
        itemViews.forEach { $0.refreshGoalMetadata(displayElapsedSeconds: displayElapsedSeconds) }
    }

    func refreshGoalElapsedMetadataForTesting() {
        refreshGoalElapsedMetadata()
    }

    private static let itemSpacing: CGFloat = 8
}

private extension AppKitChatComposerTopContentView.Configuration {
    var goalSnapshot: AgentGoalSnapshot? {
        items.compactMap(\.goalSnapshot).first
    }
}

private extension AppKitChatComposerTopContentView.Item {
    var goalSnapshot: AgentGoalSnapshot? {
        guard case .goalStatus(let configuration) = self else {
            return nil
        }
        return configuration.snapshot
    }

    var isGoalStatus: Bool {
        goalSnapshot != nil
    }
}
