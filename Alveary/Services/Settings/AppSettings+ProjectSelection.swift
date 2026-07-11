import Foundation

extension AppSettings {
    mutating func normalizeLastActiveProjectPath() {
        guard let path = lastActiveProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            lastActiveProjectPath = nil
            return
        }
        lastActiveProjectPath = CanonicalPath.normalize(path)
    }
}
