import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

@MainActor
func assertMacSnapshot<V: View>(
    _ view: V,
    size: CGSize,
    named: String? = nil,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) {
    let isRecordingSnapshots = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"

    let rootView = view
        .transaction { $0.animation = nil }
        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .current)
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.colorScheme, .light)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))

    let controller = NSHostingController(rootView: rootView)
    controller.view.frame = CGRect(origin: .zero, size: size)
    controller.view.appearance = NSAppearance(named: .aqua)
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.backgroundColor = .windowBackgroundColor
    window.contentViewController = controller
    window.layoutIfNeeded()
    window.displayIfNeeded()
    controller.view.layoutSubtreeIfNeeded()
    controller.view.displayIfNeeded()

    assertSnapshot(
        of: controller,
        as: .image,
        named: named,
        record: isRecordingSnapshots ? true : nil,
        file: file,
        testName: testName,
        line: line
    )
}

extension SnapshotTests {
    static func modifiedDiff(path: String) -> String {
        let leadingContext = (1...5).map { "    private let leadingContext\($0) = \($0)" }
        let middleContext = (6...20).map { "        let intermediateContext\($0) = \($0)" }
        let trailingContext = (21...24).map { "    private let trailingContext\($0) = \($0)" }

        var lines = [
            "diff --git a/\(path) b/\(path)",
            "--- a/\(path)",
            "+++ b/\(path)",
            "@@ -10,34 +10,36 @@ struct ChatInputField: View {",
            " struct ChatInputField: View {"
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
