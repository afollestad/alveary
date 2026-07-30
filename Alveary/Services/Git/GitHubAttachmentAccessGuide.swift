import AppKit
import Foundation

/// Remedies for `gh image` failing to read a GitHub browser session.
///
/// Safari keeps its cookie store in TCC-protected locations, and the spawned
/// extension inherits Alveary's privacy grants — so a Safari-only sign-in needs
/// Alveary to hold Full Disk Access. macOS provides no prompt API for that
/// service; the only route is the System Settings pane, mirroring
/// `AppShotPermissionRequester`'s deep-link approach.
enum GitHubAttachmentAccessGuide {
    /// Whether Safari's cookie store is readable — the same read `gh image`
    /// performs. A denied attempt is still useful: TCC registers Alveary in the
    /// Full Disk Access pane's app list, so granting becomes a single toggle.
    static func canReadSafariCookieStore() -> Bool {
        safariCookieStoreURLs.contains { url in
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                return false
            }
            try? handle.close()
            return true
        }
    }

    /// Opens System Settings to Privacy & Security → Full Disk Access.
    @MainActor
    @discardableResult
    static func openFullDiskAccessSettings() -> Bool {
        for url in settingsURLs where NSWorkspace.shared.open(url) {
            return true
        }
        return false
    }

    /// Safari cookie-store locations, container path first — current Safari
    /// writes there; the legacy path covers older profiles.
    private static var safariCookieStoreURLs: [URL] {
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        return [
            library.appending(path: "Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"),
            library.appending(path: "Cookies/Cookies.binarycookies")
        ]
    }

    /// Newer Settings deep link first, legacy anchor as fallback — the same
    /// dual-URL pattern as `AppShotPermissionRequester`.
    private static var settingsURLs: [URL] {
        [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]
        .compactMap(URL.init(string:))
    }
}
