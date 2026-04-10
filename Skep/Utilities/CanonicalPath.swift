import Foundation

enum CanonicalPath {
    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}
