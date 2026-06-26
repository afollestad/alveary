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
                        imageAttachments: attachments,
                        bubbleMaxWidth: 560
                    )
                )
                return view
            },
            size: CGSize(width: 640, height: 300),
            named: "appkit_transcript_user_attachment_strip"
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
