import Foundation

enum CanonicalPath {
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

    static func normalizeMentionPath(_ path: String, relativeTo workingDirectory: String?) -> String {
        let expandedPath = NSString(string: path).expandingTildeInPath

        guard expandedPath.hasPrefix("/") else {
            return path
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
