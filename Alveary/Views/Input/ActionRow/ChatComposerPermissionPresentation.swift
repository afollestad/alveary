import Foundation

extension ChatComposerActionRowView {
    struct PermissionOptionPresentation: Equatable {
        let value: String
        let title: String
        let description: String
        let symbolName: String
        let isWarning: Bool

        init(
            value: String,
            title: String,
            description: String = "",
            symbolName: String = "hand.raised",
            isWarning: Bool = false
        ) {
            self.value = value
            self.title = title
            self.description = description
            self.symbolName = symbolName
            self.isWarning = isWarning
        }
    }
}

enum ChatComposerPermissionPresentation {
    private static let bypassPermissionsDescription = "Bypass all permission checks. Use only in sandboxed environments."
    private static let sandboxedNeverDescription =
        "Run commands without asking, in a sandbox that can write workspace and temp files but has no network access."

    /// `runsSandboxed` is a thread launched with shell network isolation: Codex then pins a network-less
    /// workspace-write sandbox whatever the approval mode, so its "Full access" label would claim what the thread
    /// cannot do.
    static func options(
        harnessID: String,
        permissionModes: [PermissionModeOption],
        runsSandboxed: Bool = false
    ) -> [ChatComposerActionRowView.PermissionOptionPresentation] {
        permissionModes.map { option in
            if runsSandboxed, let sandboxed = sandboxedWording(harnessID: harnessID, value: option.value) {
                return ChatComposerActionRowView.PermissionOptionPresentation(
                    value: option.value,
                    title: sandboxed.title,
                    description: sandboxed.description,
                    symbolName: "lock.shield"
                )
            }
            return ChatComposerActionRowView.PermissionOptionPresentation(
                value: option.value,
                title: title(for: option),
                description: description(for: option),
                symbolName: symbolName(harnessID: harnessID, value: option.value),
                isWarning: isWarning(harnessID: harnessID, value: option.value)
            )
        }
    }

    /// Wording for a mode whose harness label assumes an unsandboxed shell, or nil when that label still holds.
    /// Shared with Settings so the review route's picker and a review thread's composer describe the same launch.
    static func sandboxedWording(harnessID: String, value: String) -> (title: String, description: String)? {
        guard harnessID == "codex", value == "never" else {
            return nil
        }
        return ("Never ask", sandboxedNeverDescription)
    }

    static func symbolName(harnessID: String, value: String) -> String {
        switch (harnessID, value) {
        case ("claude", "default"), ("codex", "untrusted"):
            return "hand.raised"
        case ("claude", "acceptEdits"), ("codex", "on-request"):
            return "lock.shield"
        case ("claude", "auto"), ("claude", "bypassPermissions"), ("codex", "never"), ("opencode", "fullAccess"):
            return "exclamationmark.shield"
        default:
            return "hand.raised"
        }
    }

    static func isWarning(harnessID: String, value: String) -> Bool {
        (harnessID == "claude" && value == "bypassPermissions")
            || (harnessID == "codex" && value == "never")
            || (harnessID == "opencode" && value == "fullAccess")
    }

    private static func title(for option: PermissionModeOption) -> String {
        ChatComposerTextSupport.permissionModeLabel(for: option)
    }

    private static func description(for option: PermissionModeOption) -> String {
        // Harness discovery supplies its own bypass copy; Alveary always shows
        // this shorter warning instead.
        if option.value == "bypassPermissions" {
            return bypassPermissionsDescription
        }
        let description = option.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty {
            return description
        }
        switch option.value {
        case "default":
            return "Ask before file edits and restricted tool actions."
        case "acceptEdits":
            return "Automatically allow file edits, but ask for other sensitive actions."
        case "auto":
            return "Automatically approve most actions with safety checks."
        case "untrusted":
            return "Always ask to edit external files and use the internet."
        case "on-request":
            return "Only ask for actions detected as potentially unsafe."
        case "never":
            return "Unrestricted access to the internet and any file on your computer."
        default:
            return ""
        }
    }
}
