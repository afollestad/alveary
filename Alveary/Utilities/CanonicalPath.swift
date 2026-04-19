import Foundation

enum CanonicalPath {
    // Start from `urlPathAllowed` (letters, digits, `-._~!$&'()*+,;=:@/`), then strip
    // every mention-regex terminator so it cannot appear unescaped in stored text.
    // Also subtract `.whitespacesAndNewlines` to cover non-ASCII whitespace like
    // `U+202F` that `urlPathAllowed` doesn't include but the regex would still
    // terminate on.
    private static let mentionStorageAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ")'")
        allowed.subtract(.whitespacesAndNewlines)
        return allowed
    }()

    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    static func abbreviateHomeDirectory(_ path: String) -> String {
        NSString(string: path).abbreviatingWithTildeInPath
    }

    static func displayMentionPath(_ path: String, relativeTo workingDirectory: String?) -> String {
        abbreviateHomeDirectory(normalizeMentionPath(path, relativeTo: workingDirectory))
    }

    // Composer storage percent-encodes every character that would otherwise terminate
    // the file-mention regex (`[^\s\)\]\}>"']+`), so a dropped path like
    // `/Users/me/Screenshot 2026.png` can hold together as `@/Users/me/Screenshot%202026.png`
    // and chip as a single unit. macOS screenshot filenames use a narrow no-break
    // space (`U+202F`) which `.whitespacesAndNewlines` covers. Call before prefixing
    // with `@` at insertion sites; pair with `decodeStoredMentionPath(_:)` when reading
    // the stored form for outbound send.
    static func encodeStoredMentionPath(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: mentionStorageAllowedCharacters) ?? path
    }

    static func decodeStoredMentionPath(_ path: String) -> String {
        path.removingPercentEncoding ?? path
    }

    static func normalizeMentionPath(_ path: String, relativeTo workingDirectory: String?) -> String {
        let decodedPath = decodeStoredMentionPath(path)
        let expandedPath = NSString(string: decodedPath).expandingTildeInPath

        guard expandedPath.hasPrefix("/") else {
            return decodedPath
        }

        let normalizedPath = normalize(expandedPath)
        guard let workingDirectory else {
            return normalizedPath
        }

        let normalizedWorkingDirectory = normalize(workingDirectory)
        guard normalizedPath != normalizedWorkingDirectory else {
            return normalizedPath
        }

        let directoryPrefix = normalizedWorkingDirectory.hasSuffix("/")
            ? normalizedWorkingDirectory
            : normalizedWorkingDirectory + "/"

        guard normalizedPath.hasPrefix(directoryPrefix) else {
            return normalizedPath
        }

        return String(normalizedPath.dropFirst(directoryPrefix.count))
    }
}
