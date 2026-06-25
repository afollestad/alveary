@preconcurrency import AppKit
import CoreGraphics
import Foundation
import QuartzCore

@MainActor
final class AppShotPermissionDragGrantAssistant {
    static let shared = AppShotPermissionDragGrantAssistant()

    private var overlayController: AppShotPermissionOverlayController?
    private var trackingTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var requestedPermission: AppShotPermission?
    private var didPresentOverlay = false

    private init() {}

    func present(permission: AppShotPermission, sourceFrameInScreen: CGRect?) {
        if permission.isAllowed {
            dismiss()
            return
        }

        dismiss()
        guard AppShotPermissionRequester.openSettings(for: permission) else {
            return
        }

        requestedPermission = permission
        overlayController = AppShotPermissionOverlayController(
            permission: permission,
            sourceFrameInScreen: sourceFrameInScreen
        ) { [weak self] in
            self?.dismiss()
        }
        didPresentOverlay = false
        startTrackingSystemSettings()
    }

    func dismiss() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        requestedPermission = nil
        overlayController?.close()
        overlayController = nil
        didPresentOverlay = false
    }

    private func startTrackingSystemSettings() {
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshOverlayPosition()
            }
        }

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshOverlayPosition()
            }
        }
        refreshOverlayPosition()
    }

    private func refreshOverlayPosition() {
        guard let requestedPermission else {
            dismiss()
            return
        }
        if requestedPermission.isAllowed {
            dismiss()
            return
        }

        guard let snapshot = AppShotSystemSettingsWindowLocator.frontmostWindow() else {
            overlayController?.hide()
            return
        }

        if didPresentOverlay {
            overlayController?.updatePosition(settingsFrame: snapshot.frame, visibleFrame: snapshot.visibleFrame)
        } else {
            overlayController?.present(settingsFrame: snapshot.frame, visibleFrame: snapshot.visibleFrame)
            didPresentOverlay = true
        }
    }
}

@MainActor
private final class AppShotPermissionOverlayController: NSWindowController {
    private let windowSize = NSSize(width: 500, height: 104)
    private let sourceFrameInScreen: CGRect?

    init(
        permission: AppShotPermission,
        sourceFrameInScreen: CGRect?,
        onClose: @escaping () -> Void
    ) {
        self.sourceFrameInScreen = sourceFrameInScreen
        let window = AppShotPermissionOverlayPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configureWindow(window)
        window.contentView = AppShotPermissionOverlayContentView(permission: permission, onClose: onClose)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func close() {
        window?.orderOut(nil)
        super.close()
    }

    func present(settingsFrame: CGRect, visibleFrame: CGRect) {
        guard let window else {
            return
        }

        let targetFrame = NSRect(origin: origin(for: settingsFrame, visibleFrame: visibleFrame), size: windowSize)
        if let sourceFrameInScreen, !sourceFrameInScreen.isEmpty {
            window.alphaValue = 0.92
            window.setFrame(sourceFrameInScreen, display: false)
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.alphaValue = 1
            window.setFrame(targetFrame, display: false)
            window.orderFrontRegardless()
        }
    }

    func updatePosition(settingsFrame: CGRect, visibleFrame: CGRect) {
        guard let window else {
            return
        }
        window.setFrameOrigin(origin(for: settingsFrame, visibleFrame: visibleFrame))
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func configureWindow(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.animationBehavior = .none
    }

    private func origin(for settingsFrame: CGRect, visibleFrame: CGRect) -> NSPoint {
        let sidebarWidth: CGFloat = 170
        let contentMinX = settingsFrame.minX + sidebarWidth
        let contentWidth = max(settingsFrame.width - sidebarWidth, windowSize.width)
        let preferredX = contentMinX + ((contentWidth - windowSize.width) / 2)
        let preferredY = settingsFrame.minY + 14
        let minX = visibleFrame.minX + 8
        let maxX = visibleFrame.maxX - windowSize.width - 8
        let minY = visibleFrame.minY + 8
        let maxY = visibleFrame.maxY - windowSize.height - 8

        return NSPoint(
            x: min(max(preferredX, minX), maxX),
            y: min(max(preferredY, minY), maxY)
        )
    }
}

private final class AppShotPermissionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class AppShotPermissionOverlayContentView: NSView {
    private let onClose: () -> Void

    init(permission: AppShotPermission, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(frame: NSRect(x: 0, y: 0, width: 500, height: 104))
        setup(permission: permission)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setup(permission: AppShotPermission) {
        let materialView = makeMaterialView()
        addSubview(materialView)

        let arrowView = makeArrowView()
        materialView.addSubview(arrowView)

        let titleLabel = makeTitleLabel(permission: permission)
        materialView.addSubview(titleLabel)

        let closeButton = makeCloseButton()
        materialView.addSubview(closeButton)

        let dragSource = AppShotAppBundleDragSourceView()
        materialView.addSubview(dragSource)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 500),
            heightAnchor.constraint(equalToConstant: 104),

            materialView.leadingAnchor.constraint(equalTo: leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: trailingAnchor),
            materialView.topAnchor.constraint(equalTo: topAnchor),
            materialView.bottomAnchor.constraint(equalTo: bottomAnchor),

            arrowView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 22),
            arrowView.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 13),
            arrowView.widthAnchor.constraint(equalToConstant: 25),
            arrowView.heightAnchor.constraint(equalToConstant: 25),

            closeButton.trailingAnchor.constraint(equalTo: materialView.trailingAnchor, constant: -15),
            closeButton.centerYAnchor.constraint(equalTo: arrowView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: arrowView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: arrowView.centerYAnchor),

            dragSource.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 58),
            dragSource.trailingAnchor.constraint(equalTo: materialView.trailingAnchor, constant: -24),
            dragSource.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 48),
            dragSource.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func makeMaterialView() -> NSVisualEffectView {
        let materialView = NSVisualEffectView()
        materialView.translatesAutoresizingMaskIntoConstraints = false
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 16
        materialView.layer?.masksToBounds = true
        materialView.layer?.borderWidth = 0.5
        materialView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
        return materialView
    }

    private func makeArrowView() -> NSImageView {
        let arrowView = NSImageView()
        arrowView.translatesAutoresizingMaskIntoConstraints = false
        arrowView.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)
        arrowView.symbolConfiguration = .init(pointSize: 25, weight: .bold)
        arrowView.contentTintColor = NSColor.controlAccentColor
        return arrowView
    }

    private func makeTitleLabel(permission: AppShotPermission) -> NSTextField {
        let titleLabel = NSTextField(labelWithString: "Remove any existing Alveary row, then drag this app to allow \(permission.title)")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = NSColor.labelColor.withAlphaComponent(0.86)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        return titleLabel
    }

    private func makeCloseButton() -> NSButton {
        let closeButton = NSButton()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.contentTintColor = NSColor.secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        if let cell = closeButton.cell as? NSButtonCell {
            cell.imagePosition = .imageOnly
        }
        return closeButton
    }

    @objc private func closePressed() {
        onClose()
    }
}
