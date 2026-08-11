/// Canned unified-diff strings for diff viewer snapshot coverage. Kept as `SnapshotTests`
/// statics so companion files keep calling them as `Self.modifiedDiff(...)`; they build plain
/// strings and need no imports beyond the standard library.
extension SnapshotTests {
    static func modifiedDiff(path: String) -> String {
        let leadingContext = (1...5).map { "    private let leadingContext\($0) = \($0)" }
        let middleContext = (6...20).map { "        let intermediateContext\($0) = \($0)" }
        let trailingContext = (21...24).map { "    private let trailingContext\($0) = \($0)" }

        var lines = [
            "diff --git a/\(path) b/\(path)",
            "--- a/\(path)",
            "+++ b/\(path)",
            "@@ -10,34 +10,36 @@ struct ChatView: View {",
            " struct ChatView: View {"
        ]
        lines.append(contentsOf: leadingContext.map { " \($0)" })
        lines.append(contentsOf: [
            "-    private let maxAutocompleteResults = 40",
            "+    private let maxAutocompleteResults = 50",
            "+    private let autocompleteDebounceNanoseconds: UInt64 = 75_000_000",
            "+    private let diffPreviewFont = Font.system(.caption, design: .monospaced)"
        ])
        lines.append(contentsOf: middleContext.map { " \($0)" })
        lines.append(contentsOf: [
            "-        Button(\"Send\", action: onSubmit)",
            "+        Button(\"Send\", action: onSubmit)",
            "+            .keyboardShortcut(.return, modifiers: [.command])"
        ])
        lines.append(contentsOf: trailingContext.map { " \($0)" })
        lines.append(" }")
        return lines.joined(separator: "\n")
    }

    static func newFileDiff(path: String) -> String {
        let lines = [
            "Nullam quis risus eget urna mollis ornare",
            "",
            "Integer posuere erat a ante venenatis dapibus",
            "",
            "Donec sed odio dui. Morbi leo risus, porta ac consectetur ac"
        ]

        return """
        diff --git a/\(path) b/\(path)
        new file mode 100644
        --- /dev/null
        +++ b/\(path)
        @@ -0,0 +1,\(lines.count) @@
        \(lines.map { "+\($0)" }.joined(separator: "\n"))
        """
    }

    static func deletedFileDiff(path: String) -> String {
        let lines = [
            "Aenean lacinia bibendum nulla sed consectetur",
            "",
            "Cras justo odio, dapibus ac facilisis in",
            "",
            "Vestibulum id ligula porta felis euismod semper"
        ]

        return """
        diff --git a/\(path) b/\(path)
        deleted file mode 100644
        --- a/\(path)
        +++ /dev/null
        @@ -1,\(lines.count) +0,0 @@
        \(lines.map { "-\($0)" }.joined(separator: "\n"))
        """
    }

    static func renamedDiff(oldPath: String, newPath: String) -> String {
        """
        diff --git a/\(oldPath) b/\(newPath)
        similarity index 100%
        rename from \(oldPath)
        rename to \(newPath)
        """
    }

    static func rawFallbackDiff(path: String) -> String {
        let longLine = String(repeating: "stream-json-output-segment-", count: 12)

        return """
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ b/\(path)
        +\(longLine)
        +func testCancellationWhileStreamingOutputDoesNotCrash() async throws {
        +    let runner = DefaultShellRunner()
        +    let task = Task {
        +        try await runner.run(executable: "/usr/bin/perl", args: ["-e", "...streaming output..."])
        +    }
        """
    }
}
