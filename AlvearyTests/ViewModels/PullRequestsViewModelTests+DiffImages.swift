import AppKit
import XCTest

@testable import Alveary

/// The Changes tab's image rows are rebuilt from both pane load legs, which race. These pin what a
/// session shows at each point in that race.
@MainActor
extension PullRequestsViewModelTests {
    private static let identifier = PullRequestIdentifier(owner: "octo", repo: "demo", number: 7)
    private static let lfsOID = "e908b5e52be4ecc4d05c38ad7afa27021fbb7472ff2d8eae58ae95fd0aca806a"

    private static var mixedDiff: String {
        """
        diff --git a/assets/hero.png b/assets/hero.png
        new file mode 100644
        index 0000000..abbe130
        --- /dev/null
        +++ b/assets/hero.png
        @@ -0,0 +1,3 @@
        +version https://git-lfs.github.com/spec/v1
        +oid sha256:\(lfsOID)
        +size 166854
        diff --git a/assets/logo.png b/assets/logo.png
        index abbe130..cd91f22 100644
        Binary files a/assets/logo.png and b/assets/logo.png differ
        """
    }

    private static func session(withDiff: Bool, withDetail: Bool) -> PullRequestPaneSession {
        var session = PullRequestPaneSession(generation: UUID())
        if withDiff {
            session.diffFiles = DiffParser.parse(mixedDiff)
        }
        if withDetail {
            var detail = makePullRequestDetail(id: identifier)
            detail.headRefOid = "head123"
            detail.baseRefOid = "base123"
            session.detail = detail
        }
        return session
    }

    func testBothLegsLandedRendersEveryImage() {
        var session = Self.session(withDiff: true, withDetail: true)

        PullRequestsViewModel.refreshDiffImagePreviews(&session, identifier: Self.identifier)

        XCTAssertEqual(Set(session.diffImagePreviews.keys), ["0:assets/hero.png", "1:assets/logo.png"])
    }

    /// The LFS object is content-addressed, so it renders while the detail leg is still in flight;
    /// the ordinary blob has to wait for the commit oids that leg carries.
    func testDiffAheadOfDetailStillRendersTheLFSImage() {
        var session = Self.session(withDiff: true, withDetail: false)

        PullRequestsViewModel.refreshDiffImagePreviews(&session, identifier: Self.identifier)

        XCTAssertEqual(Set(session.diffImagePreviews.keys), ["0:assets/hero.png"])
    }

    func testDetailArrivingAfterTheDiffBackfillsTheOrdinaryImage() {
        var session = Self.session(withDiff: true, withDetail: false)
        PullRequestsViewModel.refreshDiffImagePreviews(&session, identifier: Self.identifier)
        XCTAssertEqual(session.diffImagePreviews.count, 1)

        var detail = makePullRequestDetail(id: Self.identifier)
        detail.headRefOid = "head123"
        detail.baseRefOid = "base123"
        session.detail = detail
        PullRequestsViewModel.refreshDiffImagePreviews(&session, identifier: Self.identifier)

        XCTAssertEqual(session.diffImagePreviews.count, 2)
    }

    /// Detail usually wins the race; with no files yet there is nothing to key previews against.
    func testDetailAheadOfTheDiffLeavesNoPreviews() {
        var session = Self.session(withDiff: false, withDetail: true)

        PullRequestsViewModel.refreshDiffImagePreviews(&session, identifier: Self.identifier)

        XCTAssertTrue(session.diffImagePreviews.isEmpty)
    }

    /// A reload that clears the parsed diff must not leave the previous pull request's images behind.
    func testClearingTheDiffClearsPreviousPreviews() {
        var session = Self.session(withDiff: true, withDetail: true)
        PullRequestsViewModel.refreshDiffImagePreviews(&session, identifier: Self.identifier)
        XCTAssertFalse(session.diffImagePreviews.isEmpty)

        session.diffFiles = nil
        PullRequestsViewModel.refreshDiffImagePreviews(&session, identifier: Self.identifier)

        XCTAssertTrue(session.diffImagePreviews.isEmpty)
    }

    func testPreviewsAreAddressedAtThePullRequestsOwnRepository() throws {
        var session = Self.session(withDiff: true, withDetail: true)
        PullRequestsViewModel.refreshDiffImagePreviews(&session, identifier: Self.identifier)

        let version = try XCTUnwrap(session.diffImagePreviews["1:assets/logo.png"]?.new)
        guard case .gitHub(let source) = version.source else {
            return XCTFail("Expected a GitHub-addressed source")
        }
        XCTAssertEqual(source.owner, "octo")
        XCTAssertEqual(source.repo, "demo")
        XCTAssertEqual(source.storage, .blob(ref: "head123"))
    }

    // MARK: - Opening

    /// The opener seam is what routes a clicked image into the app's image modal instead of another
    /// application, so it has to be reached with the materialized URL.
    func testOpeningAPullRequestImageHandsItsURLToTheOpener() async throws {
        let imageData = try Self.onePixelPNGData()
        var opened: [(url: URL, name: String)] = []
        let viewModel = makePullRequestsViewModel(
            service: StubPullRequestsService(),
            imageBlobFetcher: StubPullRequestImageBlobFetcher(data: imageData),
            imagePreviewOpener: { opened.append((url: $0, name: $1)) }
        )
        let version = Self.remoteImageVersion()

        try await viewModel.openDiffImagePreview(version)

        XCTAssertEqual(opened.count, 1)
        // The materialized file is named by its cache identity, so the modal's title has to come
        // from the diff path instead.
        XCTAssertEqual(opened.first?.name, "hero.png")
        XCTAssertNotEqual(opened.first?.url.lastPathComponent, "hero.png")
    }

    func testOpeningWithoutAFetcherSurfacesAnErrorRatherThanOpeningAnything() async {
        var opened: [URL] = []
        let viewModel = makePullRequestsViewModel(
            service: StubPullRequestsService(),
            imagePreviewOpener: { url, _ in opened.append(url) }
        )

        do {
            try await viewModel.openDiffImagePreview(Self.remoteImageVersion())
            XCTFail("Expected the missing fetcher to surface")
        } catch {
            XCTAssertEqual(error as? DiffImagePreviewLoaderError, .unsupportedSource)
        }
        XCTAssertTrue(opened.isEmpty)
    }

    private static func remoteImageVersion() -> DiffImageVersion {
        DiffImageVersion(
            source: .gitHub(
                GitHubImageBlobSource(
                    owner: "octo",
                    repo: "demo",
                    path: "assets/hero.png",
                    storage: .lfs(oid: String(repeating: "d", count: 64), byteSize: 8)
                )
            ),
            side: .new,
            identityPrefix: "lfs-\(String(repeating: "d", count: 64))",
            fileIdentity: "assets/hero.png",
            fileExtension: "png",
            needsContentHash: false,
            byteSize: 8
        )
    }

    private static func onePixelPNGData() throws -> Data {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

/// Returns fixed bytes for any source, standing in for the GitHub transport.
private struct StubPullRequestImageBlobFetcher: DiffImageBlobFetching {
    let data: Data

    func blob(for source: DiffImageBlobSource, maxBytes: Int) async throws -> Data { data }
    func existingFileURL(for source: DiffImageBlobSource) -> URL? { nil }
}
