import Foundation

/// Fits free-form names — thread names, pull request titles — onto one status-menu row.
enum MenuBarItemTitle {
    /// Long names would stretch the menu across the screen; AppKit does not truncate.
    static let maxCharacters = 44

    static func truncated(_ name: String) -> String {
        let collapsed = name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > maxCharacters else {
            return collapsed
        }
        return collapsed.prefix(maxCharacters).trimmingCharacters(in: .whitespaces) + "…"
    }
}
