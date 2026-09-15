import AgentCLIKit
import Foundation

struct OutboundMessageText: Equatable, Sendable {
    let visibleText: String
    let transportText: String?
    let attachments: [LocalImageAttachment]
    let appShots: [AppShotAttachment]
    let harnessMetadata: [String: AgentCLIKit.JSONValue]
    let consumedAttachments: [LocalImageAttachment]
    let consumedFileAttachments: [LocalFileAttachment]
    let consumedAppShots: [AppShotAttachment]
    let consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance?
    /// Set only on a prompt another thread's agent sent through `send_prompt_to_thread`; it
    /// lands on the persisted user row rather than in either text.
    let relayedFrom: RelayedPromptAttribution?

    init(
        visibleText: String,
        transportText: String? = nil,
        attachments: [LocalImageAttachment] = [],
        appShots: [AppShotAttachment] = [],
        harnessMetadata: [String: AgentCLIKit.JSONValue] = [:],
        consumedAttachments: [LocalImageAttachment] = [],
        consumedFileAttachments: [LocalFileAttachment] = [],
        consumedAppShots: [AppShotAttachment] = [],
        consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance? = nil,
        relayedFrom: RelayedPromptAttribution? = nil
    ) {
        self.visibleText = visibleText
        self.transportText = transportText
        self.attachments = attachments
        self.appShots = appShots
        self.harnessMetadata = harnessMetadata
        self.consumedAttachments = consumedAttachments
        self.consumedFileAttachments = consumedFileAttachments
        self.consumedAppShots = consumedAppShots
        self.consumedExitPlanModeRevisionGuidance = consumedExitPlanModeRevisionGuidance
        self.relayedFrom = relayedFrom
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
                harnessMetadata: harnessMetadata,
                consumedAttachments: stagedAttachments,
                consumedFileAttachments: consumedFileAttachments,
                consumedAppShots: consumedAppShots,
                consumedExitPlanModeRevisionGuidance: consumedExitPlanModeRevisionGuidance,
                relayedFrom: relayedFrom
            )
        }

        return OutboundMessageText(
            visibleText: fallbackText(visibleText, stagedAttachments),
            transportText: transportText.map { fallbackText($0, stagedAttachments) },
            appShots: appShots,
            harnessMetadata: harnessMetadata,
            consumedAttachments: stagedAttachments,
            consumedFileAttachments: consumedFileAttachments,
            consumedAppShots: consumedAppShots,
            consumedExitPlanModeRevisionGuidance: consumedExitPlanModeRevisionGuidance,
            relayedFrom: relayedFrom
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
            harnessMetadata: harnessMetadata,
            consumedAttachments: consumedAttachments,
            consumedFileAttachments: stagedAttachments,
            consumedAppShots: consumedAppShots,
            consumedExitPlanModeRevisionGuidance: consumedExitPlanModeRevisionGuidance,
            relayedFrom: relayedFrom
        )
    }

    func resolvingAppShots(
        _ stagedAppShots: [AppShotAttachment],
        harnessID: String
    ) throws -> OutboundMessageText {
        guard !stagedAppShots.isEmpty else {
            return self
        }
        guard let strategy = AppShotHarnessStrategy(harnessID: harnessID) else {
            throw AppShotCaptureError.unsupportedHarness(harnessID)
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
        var nextMetadata = harnessMetadata
        if strategy == .codex {
            nextMetadata[AgentCLIKit.CodexInputMetadata.isAppshot] = .bool(true)
        }
        return OutboundMessageText(
            visibleText: visibleText,
            transportText: formatted.text,
            attachments: attachments + formatted.localImageAttachments,
            appShots: stagedAppShots,
            harnessMetadata: nextMetadata,
            consumedAttachments: consumedAttachments,
            consumedFileAttachments: consumedFileAttachments,
            consumedAppShots: stagedAppShots,
            consumedExitPlanModeRevisionGuidance: consumedExitPlanModeRevisionGuidance,
            relayedFrom: relayedFrom
        )
    }
}

/// Which thread a relayed prompt came from: the sender's main-conversation id — the same handle
/// `list_threads` reports — and its name at send time, kept so the transcript can still name a
/// thread that was renamed or archived since.
struct RelayedPromptAttribution: Equatable, Sendable {
    let conversationID: String
    let threadName: String
}
