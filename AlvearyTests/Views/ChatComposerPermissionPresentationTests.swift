import XCTest

@testable import Alveary

final class ChatComposerPermissionPresentationTests: XCTestCase {
    private let codexModes = [
        PermissionModeOption(value: "untrusted", label: "Ask for approval", description: "Always ask."),
        PermissionModeOption(
            value: "never",
            label: "Full access",
            description: "Unrestricted access to the internet and any file on your computer."
        )
    ]

    /// An isolated review thread runs Codex in a network-less sandbox whatever its approval mode, so its picker must
    /// not promise full access.
    func testSandboxedCodexThreadsDescribeNeverAsSandboxedRatherThanFullAccess() throws {
        let sandboxed = ChatComposerPermissionPresentation.options(
            harnessID: "codex", permissionModes: codexModes, runsSandboxed: true
        )
        let never = try XCTUnwrap(sandboxed.first { $0.value == "never" })
        XCTAssertEqual(never.title, "Never ask")
        XCTAssertTrue(never.description.contains("no network access"))
        XCTAssertFalse(never.isWarning)
        XCTAssertEqual(sandboxed.first { $0.value == "untrusted" }?.title, "Ask for approval")

        let ordinary = ChatComposerPermissionPresentation.options(harnessID: "codex", permissionModes: codexModes)
        XCTAssertEqual(ordinary.first { $0.value == "never" }?.title, "Full access")
        XCTAssertEqual(ordinary.first { $0.value == "never" }?.isWarning, true)
    }
}
