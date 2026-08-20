import XCTest

@testable import Alveary

/// The redirect from Preview.app to the in-app modal, and the one case that still has to leave.
@MainActor
final class DiffImagePreviewPresentationTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiffImagePreviewPresentationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeFile(named name: String, byteCount: Int) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0xAB, count: byteCount).write(to: url)
        return url
    }

    func testAnImageOpensInTheAppModalRatherThanAnotherApp() throws {
        let url = try makeFile(named: "hero.png", byteCount: 2_048)
        let appState = AppState()
        var workspaceOpens: [URL] = []
        let open = DiffImagePreviewPresentation.opener(appState: appState) { workspaceOpens.append($0) }

        open(url, "hero.png")

        let request = try XCTUnwrap(appState.imagePreviewRequest)
        XCTAssertEqual(request.source, .fileURL(url.standardizedFileURL))
        XCTAssertEqual(request.title, "hero.png", "The diff path names it, not the temp file")
        XCTAssertTrue(workspaceOpens.isEmpty, "Nothing should be handed to another app")
    }

    /// Git LFS holds files past what the modal's loader accepts, and the diff renders them inline —
    /// so those must keep opening the way they did before the redirect.
    func testAnImagePastTheModalsCeilingStillOpensInTheWorkspace() throws {
        let url = try makeFile(
            named: "master.png",
            byteCount: AppImagePreviewLoader.maximumSourceBytes + 1
        )
        let appState = AppState()
        var workspaceOpens: [URL] = []
        let open = DiffImagePreviewPresentation.opener(appState: appState) { workspaceOpens.append($0) }

        open(url, "hero.png")

        XCTAssertNil(appState.imagePreviewRequest, "The modal cannot decode it, so it must not be asked to")
        XCTAssertEqual(workspaceOpens, [url])
    }

    func testAnImageExactlyAtTheCeilingStillUsesTheModal() throws {
        let url = try makeFile(named: "edge.png", byteCount: AppImagePreviewLoader.maximumSourceBytes)
        let appState = AppState()
        var workspaceOpens: [URL] = []
        let open = DiffImagePreviewPresentation.opener(appState: appState) { workspaceOpens.append($0) }

        open(url, "hero.png")

        XCTAssertNotNil(appState.imagePreviewRequest)
        XCTAssertTrue(workspaceOpens.isEmpty)
    }

    /// A failed stat must not bounce a readable image to another app; the modal owns the real limit
    /// and reports its own error.
    func testAnUnreadableSizeFallsThroughToTheModal() {
        let url = directory.appendingPathComponent("missing.png")
        XCTAssertTrue(DiffImagePreviewPresentation.canPresentInModal(url))

        let appState = AppState()
        var workspaceOpens: [URL] = []
        let open = DiffImagePreviewPresentation.opener(appState: appState) { workspaceOpens.append($0) }

        open(url, "hero.png")

        XCTAssertNotNil(appState.imagePreviewRequest)
        XCTAssertTrue(workspaceOpens.isEmpty)
    }
}
