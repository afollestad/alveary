@preconcurrency import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    /// Covers the circular remove control on every composer attachment type.
    ///
    /// The transcript app-shot baselines render read-only cards, so nothing else pins the remove
    /// button's size or its circular background.
    func testComposerAttachmentStripRemoveButtons() {
        assertMacSnapshot(
            ComposerAttachmentStripSnapshot(),
            size: CGSize(width: 620, height: 300),
            named: "composer_attachment_strip_remove_buttons",
            colorScheme: .dark
        )
    }
}

private struct ComposerAttachmentStripSnapshot: NSViewRepresentable {
    func makeNSView(context: Context) -> ComposerAttachmentStripSnapshotContainer {
        ComposerAttachmentStripSnapshotContainer()
    }

    func updateNSView(_ nsView: ComposerAttachmentStripSnapshotContainer, context: Context) {
        nsView.needsLayout = true
    }
}

private final class ComposerAttachmentStripSnapshotContainer: NSView {
    private let strip = AppKitComposerAttachmentStripView()

    init() {
        super.init(frame: .zero)
        addSubview(strip)
        var attachments: [ComposerAttachment] = []
        if let image = ComposerAttachmentStripSnapshotFixtures.imageAttachment() {
            attachments.append(.image(image))
        }
        attachments.append(.file(ComposerAttachmentStripSnapshotFixtures.fileAttachment()))
        attachments.append(.appShot(ComposerAttachmentStripSnapshotFixtures.appShotAttachment()))
        strip.configure(attachments)
        // Remove buttons only appear once a removal handler is attached.
        strip.onRemoveAttachment = { _ in }
        strip.onOpenAttachment = { _ in }
        let icon = ComposerAttachmentStripSnapshotFixtures.appIcon()
        strip.appShotCardViews.forEach { $0.appIconResolver = StaticComposerAppIconResolver(icon: icon) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Anchors the strip to the top of the snapshot so its first row is not clipped.
    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        strip.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: strip.measuredHeight(width: bounds.width)
        )
    }
}

@MainActor
private enum ComposerAttachmentStripSnapshotFixtures {
    static func imageAttachment() -> LocalImageAttachment? {
        guard let url = writeImage(named: "strip-image.png", color: NSColor(calibratedRed: 0.19, green: 0.44, blue: 0.80, alpha: 1)) else {
            return nil
        }
        return LocalImageAttachment(
            id: "snapshot-strip-image",
            fileURL: url,
            label: "strip-image.png",
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    static func fileAttachment() -> LocalFileAttachment {
        LocalFileAttachment(
            id: "snapshot-strip-file",
            fileURL: URL(fileURLWithPath: "/tmp/AlvearySnapshotAttachments/project-audit.pdf"),
            label: "project-audit.pdf",
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    static func appShotAttachment() -> AppShotAttachment {
        let url = writeImage(
            named: "strip-app-shot.png",
            color: NSColor(calibratedRed: 0.17, green: 0.31, blue: 0.38, alpha: 1)
        )
        let screenshot = LocalImageAttachment(
            id: "snapshot-strip-app-shot-screenshot",
            fileURL: url ?? URL(fileURLWithPath: "/tmp/AlvearySnapshotAttachments/missing.png"),
            label: "strip-app-shot.png",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        return AppShotAttachment(
            id: "snapshot-strip-app-shot",
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "Preview - Document.pdf",
            screenshot: screenshot,
            axTreeText: "",
            focusedElementSummary: "",
            attachmentStoreRoot: URL(fileURLWithPath: "/tmp/AlvearySnapshotAttachments")
        )
    }

    static func appIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()
        NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 20, height: 20), xRadius: 5, yRadius: 5).fill()
        NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.82, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 5, y: 4, width: 10, height: 12), xRadius: 2, yRadius: 2).fill()
        image.unlockFocus()
        return image
    }

    private static func writeImage(named name: String, color: NSColor) -> URL? {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AlvearySnapshotStripAttachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name, isDirectory: false)

        let size = NSSize(width: 152, height: 96)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.white.withAlphaComponent(0.35).setFill()
        NSRect(x: 18, y: 20, width: 116, height: 12).fill()
        NSRect(x: 18, y: 42, width: 84, height: 10).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffData),
              let pngData = representation.representation(using: .png, properties: [:]) else {
            return nil
        }
        guard (try? pngData.write(to: url, options: [.atomic])) != nil else {
            return nil
        }
        return url
    }
}

@MainActor
private final class StaticComposerAppIconResolver: AppKitAppIconResolving {
    private let icon: NSImage

    init(icon: NSImage) {
        self.icon = icon
    }

    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        icon
    }
}
