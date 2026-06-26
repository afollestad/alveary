import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testAppKitTranscriptUserAttachmentStrip() {
        let attachments = Self.makeSnapshotImageAttachments()
        guard attachments.count == 4 else {
            XCTFail("Expected generated snapshot image attachments")
            return
        }

        assertMacSnapshot(
            TranscriptImageSnapshotHost {
                let view = AppKitTranscriptTextBubbleRowView()
                view.configure(
                    .init(
                        role: .user,
                        markdown: "Use these screenshots as context.",
                        imageAttachments: attachments.map(TranscriptImageAttachment.init(localImageAttachment:)),
                        bubbleMaxWidth: 560
                    )
                )
                return view
            },
            size: CGSize(width: 640, height: 300),
            named: "appkit_transcript_user_attachment_strip"
        )
    }

    func testAppKitTranscriptUserAppShotAttachment() {
        let appShot = Self.makeSnapshotAppShotAttachment()
        let icon = Self.makeSnapshotIcon()

        assertMacSnapshot(
            TranscriptImageSnapshotHost {
                let view = AppKitTranscriptTextBubbleRowView()
                view.setAppShotIconResolverForTesting(StaticAppIconResolver(icon: icon))
                view.configure(
                    .init(
                        role: .user,
                        markdown: "What changed in this window?",
                        imageAttachments: [TranscriptImageAttachment(appShot: appShot)],
                        bubbleMaxWidth: 560
                    )
                )
                return view
            },
            size: CGSize(width: 640, height: 320),
            named: "appkit_transcript_user_appshot_attachment"
        )
    }

    func testAppKitTranscriptUserAppShotAttachmentDark() {
        let appShot = Self.makeSnapshotAppShotAttachment()
        let icon = Self.makeSnapshotIcon()

        assertMacSnapshot(
            TranscriptImageSnapshotHost {
                let view = AppKitTranscriptTextBubbleRowView()
                view.setAppShotIconResolverForTesting(StaticAppIconResolver(icon: icon))
                view.configure(
                    .init(
                        role: .user,
                        markdown: "What changed in this window?",
                        imageAttachments: [TranscriptImageAttachment(appShot: appShot)],
                        bubbleMaxWidth: 560
                    )
                )
                return view
            },
            size: CGSize(width: 640, height: 320),
            named: "appkit_transcript_user_appshot_attachment_dark",
            colorScheme: .dark
        )
    }

    private static func makeSnapshotImageAttachments() -> [LocalImageAttachment] {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AlvearySnapshotImageAttachments", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return []
        }

        let colors: [NSColor] = [
            NSColor(calibratedRed: 0.19, green: 0.44, blue: 0.80, alpha: 1),
            NSColor(calibratedRed: 0.18, green: 0.62, blue: 0.42, alpha: 1),
            NSColor(calibratedRed: 0.78, green: 0.32, blue: 0.32, alpha: 1),
            NSColor(calibratedRed: 0.54, green: 0.38, blue: 0.82, alpha: 1)
        ]
        return colors.enumerated().compactMap { index, color in
            let url = directory.appendingPathComponent("attachment-\(index).png", isDirectory: false)
            guard writeSnapshotImage(to: url, color: color) else {
                return nil
            }
            return LocalImageAttachment(
                id: "snapshot-attachment-\(index)",
                fileURL: url,
                label: "attachment-\(index).png",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
    }

    private static func writeSnapshotImage(to url: URL, color: NSColor) -> Bool {
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
            return false
        }
        do {
            try pngData.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private static func makeSnapshotAppShotAttachment() -> PersistedAppShotAttachment {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AlvearySnapshotAppShotAttachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("preview-window.png", isDirectory: false)
        _ = writeSnapshotImage(to: url, color: NSColor(calibratedRed: 0.17, green: 0.31, blue: 0.38, alpha: 1))
        let screenshot = LocalImageAttachment(
            id: "snapshot-appshot",
            fileURL: url,
            label: "preview-window.png",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        return PersistedAppShotAttachment(
            screenshot: screenshot,
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "Preview - Document.pdf"
        )
    }

    private static func makeSnapshotIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()
        NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 20, height: 20), xRadius: 5, yRadius: 5).fill()
        NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.82, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 5, y: 4, width: 10, height: 12), xRadius: 2, yRadius: 2).fill()
        image.unlockFocus()
        return image
    }
}

@MainActor
private final class StaticAppIconResolver: AppKitTranscriptAppIconResolving {
    private let icon: NSImage

    init(icon: NSImage) {
        self.icon = icon
    }

    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        icon
    }
}

private struct TranscriptImageSnapshotHost<Content: NSView>: NSViewRepresentable {
    let makeContent: () -> Content

    func makeNSView(context: Context) -> TranscriptImageSnapshotContainer {
        TranscriptImageSnapshotContainer(contentView: makeContent())
    }

    func updateNSView(_ nsView: TranscriptImageSnapshotContainer, context: Context) {
        nsView.needsLayout = true
    }
}

private final class TranscriptImageSnapshotContainer: NSView {
    private let contentView: NSView

    init(contentView: NSView) {
        self.contentView = contentView
        super.init(frame: .zero)
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        contentView.frame = bounds
        contentView.layoutSubtreeIfNeeded()
    }
}
