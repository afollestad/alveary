import Foundation

extension ChatTranscriptView {
    // Foundation's markdown parser preserves schemeless links like `[text](Alveary/DI/AGENTS.md)`
    // or `[text](~/Desktop/file.png)` as relative URLs (scheme == nil). The transcript opener
    // eventually hands URLs to `NSWorkspace.shared.open(_:)`, which silently no-ops without
    // a `file://` scheme — so the link does nothing. Handle both shapes here:
    // `~`/`~user` prefixes expand via `NSString.expandingTildeInPath` (URLs don't know about
    // shell home-directory shortcuts), and other relative paths resolve against the thread's
    // working directory. Absolute URLs (https, file, mailto, etc.) pass through unchanged.
    static func resolveMarkdownLinkURL(_ url: URL, workingDirectory: String?) -> URL {
        guard url.scheme == nil else {
            return url
        }
        let relativePath = url.relativeString
        // Fragment-only references (`[top](#section)`) have no path to resolve. Naively
        // feeding them into the workingDirectory branch produces `file:///.../cwd/#section`,
        // which opens the cwd in Finder. Pass through unchanged so NSWorkspace no-ops.
        if relativePath.hasPrefix("#") {
            return url
        }
        if relativePath.hasPrefix("~") {
            // The markdown parser percent-encodes path characters (e.g. spaces → `%20`).
            // `expandingTildeInPath` operates literally, so decode first or filenames with
            // spaces land on disk as `foo%20bar` and the file lookup misses.
            let decoded = relativePath.removingPercentEncoding ?? relativePath
            let expanded = (decoded as NSString).expandingTildeInPath
            guard expanded != decoded else {
                return url
            }
            return URL(fileURLWithPath: expanded)
        }
        guard let workingDirectory, !workingDirectory.isEmpty else {
            return url
        }
        let baseURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        return URL(string: relativePath, relativeTo: baseURL)?.absoluteURL ?? url
    }
}
