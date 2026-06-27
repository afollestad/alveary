@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptTextBubbleRowTests {
    func testUserMessageAttachmentsRenderAsRightAlignedStripAboveBubble() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        row.configure(
            .init(
                role: .user,
                markdown: "Describe this",
                imageAttachments: transcriptImageAttachments(count: 2)
            )
        )
        row.layoutSubtreeIfNeeded()

        let stripFrame = row.imageAttachmentStripFrameForTesting
        let tileFrames = row.imageAttachmentTileFramesForTesting
        XCTAssertEqual(stripFrame.width, expectedImageStripWidth(columns: 2), accuracy: 0.5)
        XCTAssertEqual(stripFrame.height, BlockInputComposerStyle.imagePreviewThumbnailSize.height, accuracy: 0.5)
        XCTAssertEqual(stripFrame.maxX, row.bounds.maxX, accuracy: 0.5)
        XCTAssertEqual(row.bubbleFrameForTesting.maxX, row.bounds.maxX, accuracy: 0.5)
        XCTAssertGreaterThan(row.bubbleFrameForTesting.minY, stripFrame.maxY)
        XCTAssertEqual(tileFrames.count, 2)
        XCTAssertEqual(tileFrames[1].minX - tileFrames[0].maxX, BlockInputComposerStyle.imagePreviewInterItemSpacing, accuracy: 0.5)
    }

    func testAttachmentStripBorderUsesLocalSubtleToken() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.appearance = NSAppearance(named: .darkAqua)
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        row.configure(
            .init(
                role: .user,
                markdown: "Describe this",
                imageAttachments: transcriptImageAttachments(count: 1)
            )
        )
        row.layoutSubtreeIfNeeded()

        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let resolved = NSColor.secondaryLabelColor.resolved(for: appearance)
        let expectedColor = resolved.withAlphaComponent(resolved.alphaComponent * 0.10).cgColor
        XCTAssertEqual(row.attachmentTileBorderColorsForTesting.first ?? nil, expectedColor)
    }

    func testAttachmentStripUsesLightSurfaceFillInLightMode() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let row = AppKitTranscriptTextBubbleRowView()
        row.appearance = appearance
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        row.configure(
            .init(
                role: .user,
                markdown: "Describe this",
                imageAttachments: transcriptImageAttachments(count: 1)
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            row.attachmentTileFillColorsForTesting.first ?? nil,
            NSColor(calibratedWhite: 0.965, alpha: 1).resolved(for: appearance).cgColor
        )
    }

    func testAttachmentStripImagesAspectFillWideImages() throws {
        let imageURL = try temporaryPNGURL(named: "wide-transcript-attachment.png", size: NSSize(width: 240, height: 120))
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        row.configure(
            .init(
                role: .user,
                markdown: "Describe this",
                imageAttachments: [TranscriptImageAttachment(localImageAttachment: localImageAttachment(fileURL: imageURL))]
            )
        )
        row.layoutSubtreeIfNeeded()

        let thumbnailSize = BlockInputComposerStyle.imagePreviewThumbnailSize
        let imageFrame = try XCTUnwrap(row.imageAttachmentTileImageFramesForTesting.first ?? nil)
        XCTAssertEqual(imageFrame.height, thumbnailSize.height, accuracy: 0.5)
        XCTAssertGreaterThan(imageFrame.width, thumbnailSize.width)
        XCTAssertLessThan(imageFrame.minX, 0)
        XCTAssertGreaterThan(imageFrame.maxX, thumbnailSize.width)
        XCTAssertEqual(row.imageAttachmentTileHitTargetsForTesting.first, true)
    }

    func testAttachmentStripOpenCallbackReceivesAttachment() {
        let attachments = localImageAttachments(count: 2)
        let row = AppKitTranscriptTextBubbleRowView()
        var openedAttachment: TranscriptImageAttachment?
        row.onOpenImageAttachment = { openedAttachment = $0 }
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        row.configure(
            .init(
                role: .user,
                markdown: "Describe this",
                imageAttachments: attachments.map(TranscriptImageAttachment.init(localImageAttachment:))
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.openImageAttachmentForTesting(at: 0))
        XCTAssertEqual(openedAttachment, TranscriptImageAttachment(localImageAttachment: attachments[0]))
    }

    func testAssistantMessageAttachmentsRenderAsLeftAlignedWrappingStrip() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 600)
        row.configure(
            .init(
                role: .assistant,
                markdown: "Generated these images",
                imageAttachments: transcriptImageAttachments(count: 5),
                bubbleMaxWidth: expectedImageStripWidth(columns: 2)
            )
        )
        row.layoutSubtreeIfNeeded()

        let stripFrame = row.imageAttachmentStripFrameForTesting
        let tileFrames = row.imageAttachmentTileFramesForTesting
        XCTAssertEqual(stripFrame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(stripFrame.width, expectedImageStripWidth(columns: 2), accuracy: 0.5)
        XCTAssertEqual(stripFrame.height, expectedImageStripHeight(rows: 3), accuracy: 0.5)
        XCTAssertEqual(tileFrames[2].minX, 0, accuracy: 0.5)
        XCTAssertEqual(tileFrames[2].minY - tileFrames[0].maxY, BlockInputComposerStyle.imagePreviewInterItemSpacing, accuracy: 0.5)
        XCTAssertGreaterThan(row.bubbleFrameForTesting.minY, stripFrame.maxY)
    }

    func testAttachmentOnlyMessageRendersStripWithoutBubble() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        row.configure(
            .init(
                role: .assistant,
                markdown: "",
                imageAttachments: transcriptImageAttachments(count: 3),
                bubbleMaxWidth: expectedImageStripWidth(columns: 2)
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.isBubbleHiddenForTesting)
        XCTAssertEqual(row.bubbleFrameForTesting, .zero)
        XCTAssertEqual(row.imageAttachmentStripFrameForTesting.height, expectedImageStripHeight(rows: 2), accuracy: 0.5)
        XCTAssertEqual(row.intrinsicContentSize.height, expectedImageStripHeight(rows: 2), accuracy: 0.5)
    }

    func testAttachmentOnlyUserMessagePlacesRetryFooterBelowStrip() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.onRetry = {}
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        row.configure(
            .init(
                role: .user,
                markdown: "",
                imageAttachments: transcriptImageAttachments(count: 1),
                showsRetry: true
            )
        )
        row.layoutSubtreeIfNeeded()

        let button = try XCTUnwrap(row.descendants(of: NSButton.self).first { $0.title == "Retry" })
        let status = try XCTUnwrap(row.descendants(of: NSTextField.self).first { $0.stringValue == "Not sent" })
        XCTAssertFalse(button.isHidden)
        XCTAssertFalse(status.isHidden)
        XCTAssertGreaterThan(button.frame.minY, row.imageAttachmentStripFrameForTesting.maxY)
        XCTAssertGreaterThanOrEqual(row.intrinsicContentSize.height, button.frame.maxY)
    }

    func testUserMessageAppShotRendersAspectRatioCardAboveBubble() throws {
        let imageURL = try temporaryPNGURL(named: "wide-appshot.png", size: NSSize(width: 400, height: 200))
        let appShot = persistedAppShotAttachment(fileURL: imageURL, windowTitle: "Preview - Document.pdf")
        let icon = NSImage(size: NSSize(width: 20, height: 20))
        let row = AppKitTranscriptTextBubbleRowView()
        row.setAppShotIconResolverForTesting(StaticTranscriptAppIconResolver(icon: icon))
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        row.configure(
            .init(
                role: .user,
                markdown: "Describe this",
                imageAttachments: [TranscriptImageAttachment(appShot: appShot)]
            )
        )
        row.layoutSubtreeIfNeeded()

        let stripFrame = row.imageAttachmentStripFrameForTesting
        let cardFrame = try XCTUnwrap(row.appShotCardFramesForTesting.first)
        XCTAssertEqual(stripFrame.maxX, row.bounds.maxX, accuracy: 0.5)
        XCTAssertEqual(cardFrame.width, 220, accuracy: 0.5)
        XCTAssertEqual(cardFrame.height, 110, accuracy: 0.5)
        let iconFrame = try XCTUnwrap(row.appShotCardIconFramesForTesting.first)
        let titleFrame = try XCTUnwrap(row.appShotCardTitleFramesForTesting.first)
        let imageViewFrame = try XCTUnwrap(row.appShotCardImageViewFramesForTesting.first)
        XCTAssertEqual(imageViewFrame, CGRect(origin: .zero, size: cardFrame.size))
        XCTAssertEqual(iconFrame.midX, cardFrame.width / 2, accuracy: 0.5)
        XCTAssertEqual(titleFrame.midX, cardFrame.width / 2, accuracy: 0.5)
        XCTAssertEqual(iconFrame.size.width, 28, accuracy: 0.5)
        XCTAssertEqual(iconFrame.size.height, 28, accuracy: 0.5)
        XCTAssertEqual(titleFrame.minY - iconFrame.maxY, 4, accuracy: 0.5)
        XCTAssertEqual(row.appShotCardLabelsForTesting.first ?? nil, "App shot, Preview, Preview - Document.pdf")
        let resolvedIcon = try XCTUnwrap(row.appShotCardIconsForTesting.first ?? nil)
        XCTAssertTrue(resolvedIcon === icon)
        XCTAssertEqual(row.appShotCardHitTargetsForTesting.first, true)
        XCTAssertGreaterThan(row.bubbleFrameForTesting.minY, stripFrame.maxY)
    }

    func testUserMessageTallAppShotCapsHeightAndPreservesAspectRatio() throws {
        let imageURL = try temporaryPNGURL(named: "tall-appshot.png", size: NSSize(width: 200, height: 400))
        let appShot = persistedAppShotAttachment(fileURL: imageURL, windowTitle: "Tall Window")
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        row.configure(
            .init(
                role: .user,
                markdown: "Describe this",
                imageAttachments: [TranscriptImageAttachment(appShot: appShot)]
            )
        )
        row.layoutSubtreeIfNeeded()

        let stripFrame = row.imageAttachmentStripFrameForTesting
        let cardFrame = try XCTUnwrap(row.appShotCardFramesForTesting.first)
        XCTAssertEqual(stripFrame.maxX, row.bounds.maxX, accuracy: 0.5)
        XCTAssertEqual(cardFrame.width / cardFrame.height, 0.5, accuracy: 0.01)
        XCTAssertEqual(cardFrame.width, 80, accuracy: 0.5)
        XCTAssertEqual(cardFrame.height, AppKitAppShotAttachmentCardView.transcriptMaximumSize.height, accuracy: 0.5)
        XCTAssertGreaterThan(row.bubbleFrameForTesting.minY, stripFrame.maxY)
    }

    func testAssistantAppShotRendersLeftAlignedAndUsesUnreadableFallbackSize() throws {
        let appShot = persistedAppShotAttachment(
            fileURL: URL(fileURLWithPath: "/tmp/missing-appshot.png"),
            windowTitle: "Missing"
        )
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        row.configure(
            .init(
                role: .assistant,
                markdown: "Generated",
                imageAttachments: [TranscriptImageAttachment(appShot: appShot)]
            )
        )
        row.layoutSubtreeIfNeeded()

        let stripFrame = row.imageAttachmentStripFrameForTesting
        let cardFrame = try XCTUnwrap(row.appShotCardFramesForTesting.first)
        XCTAssertEqual(stripFrame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(cardFrame.width, 220, accuracy: 0.5)
        XCTAssertEqual(cardFrame.height, 140, accuracy: 0.5)
    }

    func testMixedPlainAndAppShotAttachmentsRenderPlainGridBeforeCards() throws {
        let imageURL = try temporaryPNGURL(named: "mixed-appshot.png", size: NSSize(width: 320, height: 180))
        let appShot = persistedAppShotAttachment(fileURL: imageURL)
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        row.configure(
            .init(
                role: .user,
                markdown: "Describe this",
                imageAttachments: [
                    TranscriptImageAttachment(localImageAttachment: localImageAttachments(count: 1)[0]),
                    TranscriptImageAttachment(appShot: appShot)
                ]
            )
        )
        row.layoutSubtreeIfNeeded()

        let tileFrame = try XCTUnwrap(row.imageAttachmentTileFramesForTesting.first)
        let cardFrame = try XCTUnwrap(row.appShotCardFramesForTesting.first)
        XCTAssertEqual(tileFrame.minY, 0, accuracy: 0.5)
        XCTAssertEqual(
            cardFrame.minY - tileFrame.maxY,
            AppKitTranscriptImageAttachmentStripView.appShotSectionSpacing,
            accuracy: 0.5
        )
        XCTAssertEqual(tileFrame.maxX, row.imageAttachmentStripFrameForTesting.width, accuracy: 0.5)
    }

    func testAppShotCardOpenCallbackReceivesScreenshotAttachment() throws {
        let imageURL = try temporaryPNGURL(named: "open-appshot.png", size: NSSize(width: 320, height: 180))
        let appShot = persistedAppShotAttachment(fileURL: imageURL)
        let row = AppKitTranscriptTextBubbleRowView()
        var openedAttachment: TranscriptImageAttachment?
        row.onOpenImageAttachment = { openedAttachment = $0 }
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        row.configure(
            .init(
                role: .user,
                markdown: "Describe this",
                imageAttachments: [TranscriptImageAttachment(appShot: appShot)]
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.openImageAttachmentForTesting(at: 0))
        XCTAssertEqual(openedAttachment, TranscriptImageAttachment(appShot: appShot))
    }

    func testAssistantBubbleRendersHTMLImageTagAsImageBlock() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 600)
        row.configure(
            .init(
                id: "assistant-image",
                role: .assistant,
                markdown: #"<img src="file:///tmp/photo.jpg" alt="Photo" width="262" height="174" />"#,
                bubbleMaxWidth: 420
            )
        )
        row.layoutSubtreeIfNeeded()

        let imageView = try XCTUnwrap(row.descendants(of: AppKitMarkdownImageBlockView.self).first)
        XCTAssertEqual(imageView.displaySizeForTesting, CGSize(width: 262, height: 174))
        XCTAssertFalse(row.descendants(of: AppKitMarkdownTextView.self).map(\.string).contains { $0.contains("<img") })
        XCTAssertEqual(row.intrinsicContentSize.height, 174 + (chatBubbleVerticalPadding * 2), accuracy: 1)
    }

    func testAssistantBubbleCapsWideImagesToContentWidth() throws {
        let bubbleMaxWidth: CGFloat = 420
        let expectedImageWidth = bubbleMaxWidth - (chatBubbleHorizontalPadding * 2)
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        row.configure(
            .init(
                id: "assistant-wide-image",
                role: .assistant,
                markdown: #"<img src="file:///tmp/photo.jpg" alt="Wide photo" width="1200" height="600" />"#,
                bubbleMaxWidth: bubbleMaxWidth
            )
        )
        row.layoutSubtreeIfNeeded()

        let imageView = try XCTUnwrap(row.descendants(of: AppKitMarkdownImageBlockView.self).first)
        XCTAssertEqual(row.bubbleFrameForTesting.width, bubbleMaxWidth, accuracy: 0.5)
        XCTAssertEqual(imageView.displaySizeForTesting.width, expectedImageWidth, accuracy: 0.5)
        XCTAssertLessThanOrEqual(imageView.displaySizeForTesting.width, row.markdownClipFrameForTesting.width + 0.5)
    }

    func testUserBubbleImageStaysLeadingAlignedNextToWiderText() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 760, height: 800)
        row.configure(
            .init(
                id: "user-text-and-image",
                role: .user,
                markdown: """
                A long enough first paragraph that the bubble grows wider than the pasted image below it.

                <img src="file:///tmp/photo.jpg" alt="Photo" width="426" height="128" />
                """
            )
        )
        row.layoutSubtreeIfNeeded()

        let imageView = try XCTUnwrap(row.descendants(of: AppKitMarkdownImageBlockView.self).first)
        let markdownView = try XCTUnwrap(row.markdownView)
        let imageContentView = try XCTUnwrap(imageView.subviews.first)
        let imageContentFrame = imageContentView.convert(imageContentView.bounds, to: markdownView)
        XCTAssertEqual(imageView.displaySizeForTesting, CGSize(width: 426, height: 128))
        XCTAssertGreaterThan(markdownView.bounds.width, imageView.displaySizeForTesting.width)
        XCTAssertEqual(imageContentFrame.minX, 0, accuracy: 0.5)
    }

    func testImageBaseURLDoesNotResolveFragmentOnlyLinks() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 600)
        row.configure(
            .init(
                id: "assistant-image-link",
                role: .assistant,
                markdown: """
                See [top](#section).

                ![Diagram](images/diagram.png)
                """,
                bubbleMaxWidth: 420,
                markdownBaseURL: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
            )
        )
        row.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(row.descendants(of: AppKitMarkdownTextView.self).first)
        let link = try XCTUnwrap(linkAttribute(in: textView, matching: "top") as? URL)
        XCTAssertNil(link.scheme)
        XCTAssertEqual(link.relativeString, "#section")
    }
}

private func localImageAttachments(count: Int) -> [LocalImageAttachment] {
    (0..<count).map { index in
        LocalImageAttachment(
            id: "attachment-\(index)",
            fileURL: URL(fileURLWithPath: "/tmp/attachment-\(index).png"),
            label: "attachment-\(index).png",
            createdAt: Date(timeIntervalSince1970: TimeInterval(index))
        )
    }
}

private func transcriptImageAttachments(count: Int) -> [TranscriptImageAttachment] {
    localImageAttachments(count: count).map(TranscriptImageAttachment.init(localImageAttachment:))
}

private func localImageAttachment(fileURL: URL) -> LocalImageAttachment {
    LocalImageAttachment(
        id: fileURL.lastPathComponent,
        fileURL: fileURL,
        label: fileURL.lastPathComponent,
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

private func persistedAppShotAttachment(
    fileURL: URL,
    appName: String = "Preview",
    bundleIdentifier: String = "com.apple.Preview",
    windowTitle: String = "Preview",
    axTreeText: String? = nil
) -> PersistedAppShotAttachment {
    PersistedAppShotAttachment(
        screenshot: localImageAttachment(fileURL: fileURL),
        appName: appName,
        bundleIdentifier: bundleIdentifier,
        windowTitle: windowTitle,
        axTreeText: axTreeText
    )
}

@MainActor
private final class StaticTranscriptAppIconResolver: AppKitAppIconResolving {
    private let icon: NSImage

    init(icon: NSImage) {
        self.icon = icon
    }

    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        icon
    }
}

private func temporaryPNGURL(named filename: String, size: NSSize) throws -> URL {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()

    let tiffData = try XCTUnwrap(image.tiffRepresentation)
    let representation = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
    let pngData = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    try pngData.write(to: url, options: [.atomic])
    return url
}

private func expectedImageStripWidth(columns: Int) -> CGFloat {
    CGFloat(columns) * BlockInputComposerStyle.imagePreviewThumbnailSize.width +
        CGFloat(max(columns - 1, 0)) * BlockInputComposerStyle.imagePreviewInterItemSpacing
}

private func expectedImageStripHeight(rows: Int) -> CGFloat {
    CGFloat(rows) * BlockInputComposerStyle.imagePreviewThumbnailSize.height +
        CGFloat(max(rows - 1, 0)) * BlockInputComposerStyle.imagePreviewInterItemSpacing
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}

@MainActor
private func linkAttribute(in textView: AppKitMarkdownTextView, matching text: String) -> Any? {
    let range = (textView.string as NSString).range(of: text)
    guard range.location != NSNotFound else {
        return nil
    }
    return textView.textStorage?.attribute(.link, at: range.location, effectiveRange: nil)
}
