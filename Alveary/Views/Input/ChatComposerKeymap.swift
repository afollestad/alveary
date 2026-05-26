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

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 520, height: 320)
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
        let inset: CGFloat = 24
        // NSTextField and ComposerIconButton draw with different internal
        // offsets than the SwiftUI controls they replaced; these placements
        // keep the native sheet visually aligned with the old baseline.
        let closeSize = closeButton.intrinsicContentSize
        closeButton.frame = NSRect(
            x: bounds.maxX - inset - closeSize.width,
            y: 36,
            width: closeSize.width,
            height: closeSize.height
        )

        let headerWidth = max(0, closeButton.frame.minX - inset - 16)
        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        titleField.frame = NSRect(x: inset - 2, y: 24, width: headerWidth, height: titleHeight)

        let descriptionHeight = ceil(descriptionField.intrinsicContentSize.height)
        descriptionField.frame = NSRect(
            x: inset - 2,
            y: titleField.frame.maxY + 7,
            width: max(0, bounds.width - inset * 2),
            height: descriptionHeight
        )

        var nextY = descriptionField.frame.maxY + 20
        let rowWidth = max(0, bounds.width - inset * 2)
        // Match the former SwiftUI sheet footprint: four rows must fit inside
        // the fixed 320pt keyboard-shortcuts panel and snapshot.
        let rowHeight: CGFloat = 44
        let rowSpacing: CGFloat = 12
        for row in rows {
            row.frame = NSRect(x: inset, y: nextY, width: rowWidth, height: rowHeight)
            nextY += rowHeight + rowSpacing
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
        needsLayout = true
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let horizontalPadding: CGFloat = 16
        let keyWidth: CGFloat = 150
        let spacing: CGFloat = 16
        // NSTextField's drawing inset is wider than SwiftUI Text, so the
        // frames shift left to keep text starts aligned with the old sheet.
        let contentHeight = max(
            ceil(keysField.intrinsicContentSize.height),
            ceil(descriptionField.intrinsicContentSize.height)
        )
        let textY = floor((bounds.height - contentHeight) / 2)
        keysField.frame = NSRect(
            x: horizontalPadding - 2,
            y: textY,
            width: keyWidth,
            height: contentHeight
        )
        descriptionField.frame = NSRect(
            x: horizontalPadding + keyWidth + spacing - 2,
            y: textY,
            width: max(0, bounds.width - horizontalPadding * 2 - keyWidth - spacing),
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
        descriptionField.lineBreakMode = .byTruncatingTail
        descriptionField.setAccessibilityElement(false)

        addSubview(keysField)
        addSubview(descriptionField)
    }
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
