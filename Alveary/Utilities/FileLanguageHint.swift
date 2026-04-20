import Foundation

/// Maps a file path's extension to a Markdown fenced-code-block language hint suitable
/// for syntax-highlighted rendering. Centralised so tool-row previews, diff views, and
/// any future code surface pull from one table instead of re-rolling their own switch.
enum FileLanguageHint {
    static func language(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        return languageByExtension[ext] ?? ""
    }

    private static let languageByExtension: [String: String] = [
        "swift": "swift",
        "py": "python",
        "rb": "ruby",
        "go": "go",
        "rs": "rust",
        "kt": "kotlin", "kts": "kotlin",
        "java": "java",
        "m": "objectivec", "mm": "objectivec",
        "c": "c", "h": "c",
        "cpp": "cpp", "cc": "cpp", "hpp": "cpp", "hxx": "cpp",
        "js": "javascript", "mjs": "javascript", "cjs": "javascript",
        "ts": "typescript",
        "jsx": "jsx",
        "tsx": "tsx",
        "json": "json",
        "yaml": "yaml", "yml": "yaml",
        "toml": "toml",
        "sh": "bash", "bash": "bash", "zsh": "bash",
        "fish": "fish",
        "html": "html", "htm": "html",
        "css": "css",
        "scss": "scss", "sass": "scss",
        "xml": "xml", "plist": "xml",
        "md": "markdown", "markdown": "markdown",
        "sql": "sql",
        "php": "php",
        "lua": "lua",
        "ex": "elixir", "exs": "elixir",
        "erl": "erlang",
        "hs": "haskell",
        "scala": "scala",
        "dart": "dart"
    ]
}
