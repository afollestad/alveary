import Foundation

struct AppShotAttachment: Equatable, Identifiable, Sendable {
    let id: String
    let appName: String
    let bundleIdentifier: String
    let windowTitle: String
    let screenshot: LocalImageAttachment
    let axTreeText: String
    let focusedElementSummary: String
    let attachmentStoreRoot: URL

    init(
        id: String = UUID().uuidString,
        appName: String,
        bundleIdentifier: String,
        windowTitle: String,
        screenshot: LocalImageAttachment,
        axTreeText: String,
        focusedElementSummary: String,
        attachmentStoreRoot: URL
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.screenshot = screenshot
        self.axTreeText = axTreeText
        self.focusedElementSummary = focusedElementSummary
        self.attachmentStoreRoot = attachmentStoreRoot
    }
}

struct PersistedAppShotAttachment: Codable, Equatable, Sendable {
    let screenshot: LocalImageAttachment
    let appName: String
    let bundleIdentifier: String
    let windowTitle: String
    let axTreeText: String?

    enum CodingKeys: String, CodingKey {
        case screenshot
        case appName
        case bundleIdentifier
        case windowTitle
        case axTreeText
    }

    init(
        screenshot: LocalImageAttachment,
        appName: String,
        bundleIdentifier: String,
        windowTitle: String,
        axTreeText: String? = nil
    ) {
        self.screenshot = screenshot
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.axTreeText = axTreeText
    }

    init(appShot: AppShotAttachment) {
        self.init(
            screenshot: appShot.screenshot,
            appName: appShot.appName,
            bundleIdentifier: appShot.bundleIdentifier,
            windowTitle: appShot.windowTitle,
            axTreeText: appShot.axTreeText
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        screenshot = try container.decode(LocalImageAttachment.self, forKey: .screenshot)
        appName = try container.decode(String.self, forKey: .appName)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        windowTitle = try container.decode(String.self, forKey: .windowTitle)
        axTreeText = try container.decodeIfPresent(String.self, forKey: .axTreeText)
    }

    var displayTitle: String {
        let candidates = [windowTitle, appName, "App shot"]
        return candidates.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "App shot"
    }

    var nonEmptyAXTreeText: String? {
        axTreeText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? axTreeText : nil
    }
}

struct TranscriptImageAttachment: Equatable, Sendable {
    let image: LocalImageAttachment
    let appShot: PersistedAppShotAttachment?

    init(image: LocalImageAttachment, appShot: PersistedAppShotAttachment? = nil) {
        self.image = image
        self.appShot = appShot
    }

    init(localImageAttachment: LocalImageAttachment) {
        self.init(image: localImageAttachment)
    }

    init(appShot: PersistedAppShotAttachment) {
        self.init(image: appShot.screenshot, appShot: appShot)
    }

    var isAppShot: Bool {
        appShot != nil
    }
}

enum AppShotProviderStrategy: Equatable, Sendable {
    case codex
    case claude

    init?(providerID: String) {
        switch providerID {
        case "codex":
            self = .codex
        case "claude":
            self = .claude
        default:
            return nil
        }
    }

    var requestLabel: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        }
    }

    var usesLocalImageAttachment: Bool {
        self == .codex
    }
}

struct AppShotTransportFormattingResult: Equatable, Sendable {
    let text: String
    let localImageAttachments: [LocalImageAttachment]
}

enum AppShotTransportFormatter {
    static func format(
        userInput: String,
        appShots: [AppShotAttachment],
        strategy: AppShotProviderStrategy
    ) -> AppShotTransportFormattingResult {
        let appShotBlocks = appShots.map(formatAppShotBlock(_:)).joined(separator: "\n\n")
        var requestBody = ""
        if strategy == .claude {
            requestBody = appShots
                .map { $0.screenshot.markdownImageLink(altText: "Appshot screenshot") }
                .joined(separator: "\n")
            if !requestBody.isEmpty && !userInput.isEmpty {
                requestBody += "\n\n"
            }
        }
        requestBody += userInput

        let text = """
        # Applications mentioned by the user:

        \(appShotBlocks)

        ## My request for \(strategy.requestLabel):
        \(requestBody)
        """

        return AppShotTransportFormattingResult(
            text: text,
            localImageAttachments: strategy.usesLocalImageAttachment ? appShots.map(\.screenshot) : []
        )
    }

    static func debugPreview(
        userInput: String,
        appShots: [AppShotAttachment],
        strategy: AppShotProviderStrategy
    ) -> String {
        let formatted = format(userInput: userInput, appShots: appShots, strategy: strategy)
        let providerMode = strategy == .codex ? "Codex localImage" : "Claude markdown screenshot link"
        let paths = appShots.map { $0.screenshot.fileURL.path }.joined(separator: "\n")
        let roots = Set(appShots.map { $0.attachmentStoreRoot.path }).sorted().joined(separator: "\n")
        return """
        Provider mode: \(providerMode)
        Screenshot path:
        \(paths)

        Attachment store path:
        \(roots)

        Generated body:
        \(formatted.text)
        """
    }

    private static func formatAppShotBlock(_ appShot: AppShotAttachment) -> String {
        let appName = xmlAttributeEscaped(appShot.appName)
        let bundleIdentifier = xmlAttributeEscaped(appShot.bundleIdentifier)
        let windowTitle = xmlAttributeEscaped(appShot.windowTitle)
        let imagePath = xmlAttributeEscaped(appShot.screenshot.fileURL.path)
        return """
        <appshot app="\(appName)" bundle-identifier="\(bundleIdentifier)" window-title="\(windowTitle)" image="\(imagePath)">
        Window: "\(bodyEscaped(appShot.windowTitle))", App: \(bodyEscaped(appShot.appName)).
        \(bodyEscaped(appShot.axTreeText))

        The focused UI element is \(bodyEscaped(appShot.focusedElementSummary))
        </appshot>
        """
    }

    private static func xmlAttributeEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func bodyEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private extension LocalImageAttachment {
    func markdownImageLink(altText: String) -> String {
        "![\(altText.replacingOccurrences(of: "]", with: "\\]"))](<\(fileURL.path.replacingOccurrences(of: ">", with: "%3E"))>)"
    }
}
