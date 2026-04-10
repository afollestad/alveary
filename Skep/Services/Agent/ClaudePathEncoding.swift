import Foundation

enum ClaudePathEncoding {
    static func projectDirectoryName(forCanonicalCwd canonicalCwd: String) -> String {
        canonicalCwd.unicodeScalars.map { scalar in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" {
                String(scalar)
            } else {
                "-"
            }
        }
        .joined()
    }
}
