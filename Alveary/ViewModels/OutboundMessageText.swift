import AgentCLIKit
import Foundation

struct OutboundMessageText: Equatable, Sendable {
    let visibleText: String
    let transportText: String?
    let attachments: [LocalImageAttachment]
    let appShots: [AppShotAttachment]
    let providerMetadata: [String: AgentCLIKit.JSONValue]
    let consumedAttachments: [LocalImageAttachment]
    let consumedFileAttachments: [LocalFileAttachment]
    let consumedAppShots: [AppShotAttachment]
    let consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance?

    init(
        visibleText: String,
        transportText: String? = nil,
        attachments: [LocalImageAttachment] = [],
        appShots: [AppShotAttachment] = [],
        providerMetadata: [String: AgentCLIKit.JSONValue] = [:],
        consumedAttachments: [LocalImageAttachment] = [],
        consumedFileAttachments: [LocalFileAttachment] = [],
        consumedAppShots: [AppShotAttachment] = [],
        consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance? = nil
    ) {
        self.visibleText = visibleText
        self.transportText = transportText
        self.attachments = attachments
        self.appShots = appShots
        self.providerMetadata = providerMetadata
        self.consumedAttachments = consumedAttachments
        self.consumedFileAttachments = consumedFileAttachments
        self.consumedAppShots = consumedAppShots
        self.consumedExitPlanModeRevisionGuidance = consumedExitPlanModeRevisionGuidance
    }

    func resolvingImageAttachments(
        _ stagedAttachments: [LocalImageAttachment],
        supportsLocalImageInput: Bool,
        fallbackText: (String, [LocalImageAttachment]) -> String
    ) -> OutboundMessageText {
        guard !stagedAttachments.isEmpty else {
            return self
        }
        if supportsLocalImageInput {
            return OutboundMessageText(
                visibleText: visibleText,
                transportText: transportText,
                attachments: stagedAttachments,
                appShots: appShots,
                providerMetadata: providerMetadata,
                consumedAttachments: stagedAttachments,
                consumedFileAttachments: consumedFileAttachments,
                consumedAppShots: consumedAppShots,
                consumedExitPlanModeRevisionGuidance: consumedExitPlanModeRevisionGuidance
            )
        }

        return OutboundMessageText(
            visibleText: fallbackText(visibleText, stagedAttachments),
            transportText: transportText.map { fallbackText($0, stagedAttachments) },
            appShots: appShots,
            providerMetadata: providerMetadata,
            consumedAttachments: stagedAttachments,
            consumedFileAttachments: consumedFileAttachments,
            consumedAppShots: consumedAppShots,
            consumedExitPlanModeRevisionGuidance: consumedExitPlanModeRevisionGuidance
        )
    }

    func resolvingFileAttachments(
        _ stagedAttachments: [LocalFileAttachment],
        fallbackText: (String, [LocalFileAttachment]) -> String
    ) -> OutboundMessageText {
        guard !stagedAttachments.isEmpty else {
            return self
        }
        return OutboundMessageText(
            visibleText: fallbackText(visibleText, stagedAttachments),
            transportText: transportText.map { fallbackText($0, stagedAttachments) },
            attachments: attachments,
            appShots: appShots,
            providerMetadata: providerMetadata,
            consumedAttachments: consumedAttachments,
            consumedFileAttachments: stagedAttachments,
            consumedAppShots: consumedAppShots,
            consumedExitPlanModeRevisionGuidance: consumedExitPlanModeRevisionGuidance
        )
    }

    func resolvingAppShots(
        _ stagedAppShots: [AppShotAttachment],
        providerID: String
    ) throws -> OutboundMessageText {
        guard !stagedAppShots.isEmpty else {
            return self
        }
        guard let strategy = AppShotProviderStrategy(providerID: providerID) else {
            throw AppShotCaptureError.unsupportedProvider(providerID)
        }
        if strategy == .claude {
            for appShot in stagedAppShots where !FileManager.default.isReadableFile(atPath: appShot.screenshot.fileURL.path) {
                throw AppShotCaptureError.claudeScreenshotUnreadable(appShot.screenshot.fileURL.path)
            }
        }

        let formatted = AppShotTransportFormatter.format(
            userInput: transportText ?? visibleText,
            appShots: stagedAppShots,
            strategy: strategy
        )
        var nextMetadata = providerMetadata
        if strategy == .codex {
            nextMetadata[AgentCLIKit.CodexInputMetadata.isAppshot] = .bool(true)
        }
        return OutboundMessageText(
            visibleText: visibleText,
            transportText: formatted.text,
            attachments: attachments + formatted.localImageAttachments,
            appShots: stagedAppShots,
            providerMetadata: nextMetadata,
            consumedAttachments: consumedAttachments,
            consumedFileAttachments: consumedFileAttachments,
            consumedAppShots: stagedAppShots,
            consumedExitPlanModeRevisionGuidance: consumedExitPlanModeRevisionGuidance
        )
    }
}
