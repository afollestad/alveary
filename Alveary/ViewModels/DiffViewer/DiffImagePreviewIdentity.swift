import CryptoKit
import Foundation

enum DiffImagePreviewIdentity {
    private static let maximumFilenameLength = 180

    static func fileName(
        for version: DiffImageVersion,
        contentHash: String?,
        extension fileExtension: String
    ) -> String {
        var parts = [
            version.identityPrefix,
            version.fileIdentity,
            version.side.rawValue
        ]

        if let contentHash {
            parts.append(contentHash)
        }

        let rawIdentity = parts.joined(separator: "-")
        let sanitizedIdentity = sanitize(rawIdentity)
        let digest = stableHash(rawIdentity, length: 12)
        let suffix = ".\(sanitize(fileExtension).prefixString(24))"
        let digestSeparatorLength = 1
        let availablePrefixLength = maximumFilenameLength - suffix.count - digest.count - digestSeparatorLength
        let prefix = sanitizedIdentity.count <= availablePrefixLength
            ? sanitizedIdentity
            : String(sanitizedIdentity.prefix(max(availablePrefixLength, 16)))

        let fileName: String
        if prefix.isEmpty {
            fileName = "\(digest)\(suffix)"
        } else {
            fileName = "\(prefix)-\(digest)\(suffix)"
        }

        if fileName.count > maximumFilenameLength {
            return "\(digest)\(suffix)"
        }

        return fileName
    }

    static func contentHash(for data: Data, length: Int = 12) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined().prefixString(length)
    }

    static func stableHash(_ value: String, length: Int = 12) -> String {
        contentHash(for: Data(value.utf8), length: length)
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        var result = ""
        var lastWasSeparator = false

        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("-")
                lastWasSeparator = true
            }
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-")).nilIfEmpty ?? "image"
    }
}

private extension StringProtocol {
    func prefixString(_ count: Int) -> String {
        String(prefix(count))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
