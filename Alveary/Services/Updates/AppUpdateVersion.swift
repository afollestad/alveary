import Foundation

struct AppUpdateVersion: Comparable, Equatable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.dropFirstIfVersionPrefix()
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]),
              major >= 0,
              minor >= 0,
              patch >= 0 else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: AppUpdateVersion, rhs: AppUpdateVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}

private extension String {
    func dropFirstIfVersionPrefix() -> Substring {
        let value = self[...]
        guard let first = value.first,
              first == "v" || first == "V" else {
            return value
        }
        return value.dropFirst()
    }
}
