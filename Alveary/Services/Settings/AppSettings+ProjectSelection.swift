import Foundation

extension AppSettings {
    mutating func normalizeLastActiveProjectPath() {
        lastActiveProjectID = lastActiveProjectID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if lastActiveProjectID?.isEmpty == true { lastActiveProjectID = nil }
        guard let path = lastActiveProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            lastActiveProjectPath = nil
            return
        }
        // Stored selections refer to the migrated literal path, even if its symlink target changed.
        lastActiveProjectPath = path
    }
}
