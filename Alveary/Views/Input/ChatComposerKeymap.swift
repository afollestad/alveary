import AppKit
import SwiftUI

/// SwiftUI compatibility wrapper for the native composer keymap view.
///
/// The production composer presents `AppKitChatComposerKeymapView` through
/// `AppKitChatComposerKeymapPresenter`; this wrapper exists only for SwiftUI
/// snapshot coverage of the same native view.
struct ChatComposerKeymapSheet: NSViewRepresentable {
    let supportsMidTurnSteering: Bool
    let defaultEnterBehavior: ThreadEnterDefaultBehavior

    @Environment(\.dismiss) private var dismiss

    init(
        supportsMidTurnSteering: Bool,
        defaultEnterBehavior: ThreadEnterDefaultBehavior = AppSettings.defaultEnterBehavior
    ) {
        self.supportsMidTurnSteering = supportsMidTurnSteering
        self.defaultEnterBehavior = defaultEnterBehavior
    }

    func makeNSView(context: Context) -> AppKitChatComposerKeymapView {
        let view = AppKitChatComposerKeymapView()
        view.configure(
            .init(
                supportsMidTurnSteering: supportsMidTurnSteering,
                defaultEnterBehavior: defaultEnterBehavior
            ),
            onClose: dismiss.callAsFunction
        )
        return view
    }

    func updateNSView(_ view: AppKitChatComposerKeymapView, context: Context) {
        view.configure(
            .init(
                supportsMidTurnSteering: supportsMidTurnSteering,
                defaultEnterBehavior: defaultEnterBehavior
            ),
            onClose: dismiss.callAsFunction
        )
    }
}

/// Presents the native composer keymap view without adding a SwiftUI sheet to
/// the active chat surface.
@MainActor
enum AppKitChatComposerKeymapPresenter {
    // Sheets need a strong owner outside the window hierarchy until AppKit
    // delivers the sheet-completion callback.
    private static var currentPanel: NSPanel?

    static func present(
        supportsMidTurnSteering: Bool,
        defaultEnterBehavior: ThreadEnterDefaultBehavior,
        parentWindow: NSWindow? = NSApp.keyWindow ?? NSApp.mainWindow
    ) {
        if let currentPanel, currentPanel.isVisible {
            currentPanel.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = AppKitChatComposerKeymapView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        let panel = makePanel(contentView: contentView)
        currentPanel = panel

        contentView.configure(
            .init(
                supportsMidTurnSteering: supportsMidTurnSteering,
                defaultEnterBehavior: defaultEnterBehavior
            ),
            onClose: { [weak panel, weak parentWindow] in close(panel, parentWindow: parentWindow) }
        )
        resize(panel: panel, contentView: contentView)

        show(panel, parentWindow: parentWindow)
    }

    private static func makePanel(contentView: NSView) -> NSPanel {
        let panel = NSPanel(
            contentRect: contentView.bounds,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Keyboard shortcuts"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .documentWindow
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = contentView
        return panel
    }

    private static func show(_ panel: NSPanel, parentWindow: NSWindow?) {
        if let parentWindow {
            parentWindow.beginSheet(panel) { _ in
                if currentPanel === panel {
                    currentPanel = nil
                }
            }
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private static func resize(panel: NSPanel, contentView: AppKitChatComposerKeymapView) {
        let size = contentView.preferredModalSize
        contentView.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
    }

    private static func close(_ panel: NSPanel?, parentWindow: NSWindow?) {
        guard let panel else {
            return
        }
        if let parentWindow, panel.sheetParent === parentWindow {
            parentWindow.endSheet(panel)
        } else {
            if currentPanel === panel {
                currentPanel = nil
            }
            panel.close()
        }
    }
}

/// Native keymap sheet content for composer keyboard shortcuts.
///
/// Keeping this view in AppKit prevents the production composer action row from
/// needing a SwiftUI sheet boundary just to display static keyboard help.
@MainActor
final class AppKitChatComposerKeymapView: NSView {
    struct Configuration: Equatable {
        let supportsMidTurnSteering: Bool
        let defaultEnterBehavior: ThreadEnterDefaultBehavior
    }

    private let titleField = NSTextField(labelWithString: "Keyboard shortcuts")
    private let descriptionField = NSTextField(labelWithString: "Use these shortcuts while typing in the chat composer.")
    private let closeButton = ComposerIconButton(symbolName: "xmark")
    private var rows: [AppKitChatComposerKeymapRowView] = []
    private var configuration: Configuration?
    private var onClose: () -> Void = {}

    var preferredModalSize: NSSize {
        NSSize(width: Self.modalWidth, height: max(Self.minimumModalHeight, measuredContentHeight(for: Self.modalWidth)))
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        preferredModalSize
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(_ configuration: Configuration, onClose: @escaping () -> Void = {}) {
        self.configuration = configuration
        self.onClose = onClose
        closeButton.actionHandler = onClose
        rebuildRows()
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        rows.forEach { $0.needsDisplay = true }
    }

    override func layout() {
        super.layout()
        // NSTextField and ComposerIconButton draw with different internal
        // offsets than the SwiftUI controls they replaced; these placements
        // keep the native sheet visually aligned with the old baseline.
        let closeSize = closeButton.intrinsicContentSize
        closeButton.frame = NSRect(
            x: bounds.maxX - Self.inset - closeSize.width,
            y: Self.closeButtonY,
            width: closeSize.width,
            height: closeSize.height
        )

        let headerWidth = max(0, closeButton.frame.minX - Self.inset - 16)
        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        titleField.frame = NSRect(x: Self.inset - 2, y: Self.titleY, width: headerWidth, height: titleHeight)

        let descriptionHeight = ceil(descriptionField.intrinsicContentSize.height)
        descriptionField.frame = NSRect(
            x: Self.inset - 2,
            y: titleField.frame.maxY + Self.titleDescriptionSpacing,
            width: max(0, bounds.width - Self.inset * 2),
            height: descriptionHeight
        )

        var nextY = descriptionField.frame.maxY + Self.headerRowsSpacing
        let rowWidth = max(0, bounds.width - Self.inset * 2)
        for row in rows {
            let rowHeight = row.preferredHeight(for: rowWidth)
            row.frame = NSRect(x: Self.inset, y: nextY, width: rowWidth, height: rowHeight)
            nextY += rowHeight + Self.rowSpacing
        }
    }

    private func setup() {
        wantsLayer = true
        let titleFont = NSFont.preferredFont(forTextStyle: .largeTitle)
        titleField.font = .systemFont(ofSize: titleFont.pointSize, weight: .semibold)
        titleField.textColor = .keymapPrimaryText
        descriptionField.font = .preferredFont(forTextStyle: .body)
        descriptionField.textColor = .keymapSecondaryText
        descriptionField.lineBreakMode = .byTruncatingTail
        closeButton.setAccessibilityLabel("Close keyboard shortcuts")
        closeButton.actionHandler = { [weak self] in self?.onClose() }

        addSubview(titleField)
        addSubview(descriptionField)
        addSubview(closeButton)
    }

    private func rebuildRows() {
        rows.forEach { $0.removeFromSuperview() }
        rows = keymapRows.map { row in
            let rowView = AppKitChatComposerKeymapRowView()
            rowView.configure(keys: row.keys, description: row.description)
            addSubview(rowView)
            return rowView
        }
    }

    private func measuredContentHeight(for width: CGFloat) -> CGFloat {
        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        let descriptionHeight = ceil(descriptionField.intrinsicContentSize.height)
        let headerHeight = Self.titleY
            + titleHeight
            + Self.titleDescriptionSpacing
            + descriptionHeight
            + Self.headerRowsSpacing
        let rowWidth = max(0, width - Self.inset * 2)
        let rowsHeight = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + row.preferredHeight(for: rowWidth)
        }
        let spacingHeight = CGFloat(max(0, rows.count - 1)) * Self.rowSpacing
        return ceil(headerHeight + rowsHeight + spacingHeight + Self.bottomPadding)
    }

    private var keymapRows: [(keys: String, description: String)] {
        guard let configuration else {
            return []
        }

        var rows: [(keys: String, description: String)] = [
            ("Enter", enterDescription(for: configuration)),
            ("Shift + Enter", "Insert a newline.")
        ]

        if configuration.supportsMidTurnSteering {
            rows.append(("Option + Enter", optionEnterDescription(for: configuration)))
        }

        rows.append(("Esc, then Esc", "During an active turn, double-tap escape to interrupt (stop) the turn."))
        return rows
    }

    private func enterDescription(for configuration: Configuration) -> String {
        guard configuration.supportsMidTurnSteering else {
            return "Send the message."
        }

        switch configuration.defaultEnterBehavior {
        case .queue:
            return "Send the message, or queue it while the agent is busy."
        case .steer:
            return "Send the message, or steer the current turn while the agent is busy."
        }
    }

    private func optionEnterDescription(for configuration: Configuration) -> String {
        switch configuration.defaultEnterBehavior {
        case .queue:
            return "Steer the current turn immediately while the agent is working."
        case .steer:
            return "Queue for the next turn while the agent is working."
        }
    }

    private static let modalWidth: CGFloat = 520
    private static let minimumModalHeight: CGFloat = 320
    private static let inset: CGFloat = 24
    private static let titleY: CGFloat = 24
    private static let closeButtonY: CGFloat = 36
    private static let titleDescriptionSpacing: CGFloat = 7
    private static let headerRowsSpacing: CGFloat = 20
    private static let rowSpacing: CGFloat = 12
    private static let bottomPadding: CGFloat = 24
}

private final class AppKitChatComposerKeymapRowView: NSView {
    private let keysField = NSTextField(labelWithString: "")
    private let descriptionField = NSTextField(labelWithString: "")

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(keys: String, description: String) {
        keysField.stringValue = keys
        descriptionField.stringValue = description
        setAccessibilityLabel("\(keys), \(description)")
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    func preferredHeight(for width: CGFloat) -> CGFloat {
        let contentHeight = max(
            ceil(keysField.intrinsicContentSize.height),
            measuredDescriptionHeight(for: width)
        )
        return max(Self.minimumHeight, ceil(contentHeight + Self.verticalPadding * 2))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        // NSTextField's drawing inset is wider than SwiftUI Text, so the
        // frames shift left to keep text starts aligned with the old sheet.
        let descriptionWidth = descriptionWidth(for: bounds.width)
        let contentHeight = max(
            ceil(keysField.intrinsicContentSize.height),
            measuredDescriptionHeight(for: bounds.width)
        )
        let textY = max(0, floor((bounds.height - contentHeight) / 2))
        keysField.frame = NSRect(
            x: Self.horizontalPadding - 2,
            y: textY,
            width: Self.keyWidth,
            height: contentHeight
        )
        descriptionField.frame = NSRect(
            x: Self.horizontalPadding + Self.keyWidth + Self.spacing - 2,
            y: textY,
            width: descriptionWidth,
            height: contentHeight
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        appKitComposerSecondaryColor(in: self, opacity: 0.08).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
    }

    private func setup() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        keysField.font = .monospacedSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize,
            weight: .semibold
        )
        keysField.textColor = .keymapPrimaryText
        keysField.lineBreakMode = .byTruncatingTail
        keysField.setAccessibilityElement(false)

        descriptionField.font = .preferredFont(forTextStyle: .body)
        descriptionField.textColor = .keymapSecondaryText
        descriptionField.lineBreakMode = .byWordWrapping
        descriptionField.maximumNumberOfLines = 0
        descriptionField.cell?.wraps = true
        descriptionField.cell?.isScrollable = false
        descriptionField.cell?.usesSingleLineMode = false
        descriptionField.setAccessibilityElement(false)

        addSubview(keysField)
        addSubview(descriptionField)
    }

    private func measuredDescriptionHeight(for width: CGFloat) -> CGFloat {
        let availableWidth = descriptionWidth(for: width)
        guard availableWidth > 0 else {
            return ceil(descriptionField.fittingSize.height)
        }
        let bounds = NSRect(
            x: 0,
            y: 0,
            width: availableWidth,
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        let cellHeight = descriptionField.cell?.cellSize(forBounds: bounds).height ?? 0
        let rect = descriptionField.attributedStringValue.boundingRect(
            with: bounds.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .usesDeviceMetrics]
        )
        return ceil(max(cellHeight, rect.height))
    }

    private func descriptionWidth(for width: CGFloat) -> CGFloat {
        max(0, width - Self.horizontalPadding * 2 - Self.keyWidth - Self.spacing)
    }

    private static let minimumHeight: CGFloat = 44
    private static let horizontalPadding: CGFloat = 16
    private static let verticalPadding: CGFloat = 10
    private static let keyWidth: CGFloat = 150
    private static let spacing: CGFloat = 16
}

private extension NSColor {
    static var keymapPrimaryText: NSColor {
        keymapTextColor(lightWhite: 0.11, darkWhite: 0.86)
    }

    static var keymapSecondaryText: NSColor {
        keymapTextColor(lightWhite: 0.43, darkWhite: 0.62)
    }

    // NSTextField's semantic label colors do not snapshot-match SwiftUI
    // `.primary`/`.secondary`, so the native keymap uses calibrated parity
    // colors while still switching for dark appearances.
    private static func keymapTextColor(lightWhite: CGFloat, darkWhite: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            let white = match == .darkAqua ? darkWhite : lightWhite
            return NSColor(calibratedWhite: white, alpha: 1)
        }
    }
}
