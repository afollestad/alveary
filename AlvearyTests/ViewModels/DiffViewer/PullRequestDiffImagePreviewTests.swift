import XCTest

@testable import Alveary

/// How a pull request diff maps onto image versions: which storage serves each side, which ref it is
/// read from, and what stays a plain callout.
final class PullRequestDiffImagePreviewTests: XCTestCase {
    private static let oldOID = "e908b5e52be4ecc4d05c38ad7afa27021fbb7472ff2d8eae58ae95fd0aca806a"
    private static let newOID = String(repeating: "a", count: 64)

    private func previews(
        _ diff: String,
        headRef: String? = "head123",
        baseRef: String? = "base123"
    ) -> [String: DiffImagePreview] {
        DiffImagePreviewSupport.pullRequestPreviews(
            for: DiffParser.parse(diff),
            owner: "octo",
            repo: "demo",
            headRef: headRef,
            baseRef: baseRef
        )
    }

    private func modifiedPointerDiff(path: String = "assets/hero.png") -> String {
        """
        diff --git a/\(path) b/\(path)
        index abbe130..cd91f22 100644
        --- a/\(path)
        +++ b/\(path)
        @@ -1,3 +1,3 @@
         version https://git-lfs.github.com/spec/v1
        -oid sha256:\(Self.oldOID)
        -size 166854
        +oid sha256:\(Self.newOID)
        +size 4096
        """
    }

    private func binaryDiff(path: String = "assets/logo.png") -> String {
        """
        diff --git a/\(path) b/\(path)
        index abbe130..cd91f22 100644
        Binary files a/\(path) and b/\(path) differ
        """
    }

    // MARK: - Git LFS

    func testAnLFSImageIsAddressedByContentOnBothSides() throws {
        let preview = try XCTUnwrap(previews(modifiedPointerDiff())["0:assets/hero.png"])

        XCTAssertEqual(
            preview.old?.source,
            .gitHub(GitHubImageBlobSource(
                owner: "octo",
                repo: "demo",
                path: "assets/hero.png",
                storage: .lfs(oid: Self.oldOID, byteSize: 166_854)
            ))
        )
        XCTAssertEqual(
            preview.new?.source,
            .gitHub(GitHubImageBlobSource(
                owner: "octo",
                repo: "demo",
                path: "assets/hero.png",
                storage: .lfs(oid: Self.newOID, byteSize: 4_096)
            ))
        )
        // The pointer states the size, so the auto-load gate needs no request to apply.
        XCTAssertEqual(preview.old?.byteSize, 166_854)
        XCTAssertEqual(preview.new?.byteSize, 4_096)
    }

    /// An LFS object is content-addressed, so it resolves without knowing which commits the diff
    /// spans — which is what lets an image render before the detail leg has returned.
    func testAnLFSImageResolvesWithoutAnyRefs() throws {
        let preview = try XCTUnwrap(
            previews(modifiedPointerDiff(), headRef: nil, baseRef: nil)["0:assets/hero.png"]
        )
        XCTAssertNotNil(preview.old)
        XCTAssertNotNil(preview.new)
    }

    func testAnLFSVersionIsCachedByItsOIDAndNeedsNoContentHash() throws {
        let preview = try XCTUnwrap(previews(modifiedPointerDiff())["0:assets/hero.png"])
        XCTAssertEqual(preview.new?.identityPrefix, "lfs-\(Self.newOID)")
        XCTAssertEqual(preview.new?.needsContentHash, false)
    }

    // MARK: - Ordinary binary images

    func testABinaryImageReadsOldFromTheBaseCommitAndNewFromTheHead() throws {
        let preview = try XCTUnwrap(previews(binaryDiff())["0:assets/logo.png"])

        XCTAssertEqual(
            preview.old?.source,
            .gitHub(GitHubImageBlobSource(owner: "octo", repo: "demo", path: "assets/logo.png", storage: .blob(ref: "base123")))
        )
        XCTAssertEqual(
            preview.new?.source,
            .gitHub(GitHubImageBlobSource(owner: "octo", repo: "demo", path: "assets/logo.png", storage: .blob(ref: "head123")))
        )
        // Only the transport can discover an ordinary blob's size.
        XCTAssertNil(preview.new?.byteSize)
    }

    func testABinaryImageIsLeftAloneUntilTheRefsAreKnown() {
        XCTAssertTrue(previews(binaryDiff(), headRef: nil, baseRef: nil).isEmpty)
    }

    func testADeletedBinaryImageHasOnlyAnOldSide() throws {
        let diff = """
        diff --git a/assets/logo.png b/assets/logo.png
        deleted file mode 100644
        index abbe130..0000000
        Binary files a/assets/logo.png and /dev/null differ
        """
        let preview = try XCTUnwrap(previews(diff)["0:assets/logo.png"])
        XCTAssertNotNil(preview.old)
        XCTAssertNil(preview.new)
    }

    // MARK: - What stays a callout

    func testANonImageBinaryFileGetsNoPreview() {
        XCTAssertTrue(previews(binaryDiff(path: "docs/manual.pdf")).isEmpty)
    }

    func testAnOrdinaryTextDiffGetsNoPreview() {
        let diff = """
        diff --git a/README.md b/README.md
        index abbe130..cd91f22 100644
        --- a/README.md
        +++ b/README.md
        @@ -1,2 +1,2 @@
         # Title
        -old
        +new
        """
        XCTAssertTrue(previews(diff).isEmpty)
    }

    /// A text file that happens to carry an image extension must keep its text diff, matching the
    /// diff viewer's rule.
    func testATextFileNamedLikeAnImageGetsNoPreview() {
        let diff = """
        diff --git a/notes.png b/notes.png
        index abbe130..cd91f22 100644
        --- a/notes.png
        +++ b/notes.png
        @@ -1,2 +1,2 @@
         heading
        -old
        +new
        """
        XCTAssertTrue(previews(diff).isEmpty)
    }

    // MARK: - Keys

    func testPreviewsAreKeyedTheWayTheRowBuilderKeysFiles() throws {
        let diff = modifiedPointerDiff() + "\n" + binaryDiff()
        let files = DiffParser.parse(diff)
        XCTAssertEqual(files.count, 2)

        let built = previews(diff)
        for (index, file) in files.enumerated() {
            let rowKey = FlattenedDiffPreviewRows.fileCollapseID(for: file, fileIndex: index)
            XCTAssertNotNil(built[rowKey], "Missing preview for row key \(rowKey)")
        }
    }

    // MARK: - Load policy

    func testTheAutoLoadGateIsLowerForRemoteImagesThanTheHardCap() {
        let remote = gitHubBlobSource(storage: .blob(ref: "abc"))
        XCTAssertEqual(
            DiffImagePreviewSupport.byteLimit(for: remote, intent: .automatic),
            DiffImagePreviewSupport.autoLoadByteLimit
        )
        XCTAssertEqual(
            DiffImagePreviewSupport.byteLimit(for: remote, intent: .confirmed),
            DiffImagePreviewSupport.remoteMaxSourceBytes
        )
        XCTAssertTrue(
            DiffImagePreviewSupport.exceedsHardLimit(
                byteSize: DiffImagePreviewSupport.remoteMaxSourceBytes + 1,
                source: remote
            )
        )
    }

    /// A checkout read costs no bandwidth, so gating it would only add a click.
    func testCheckoutImagesKeepOneFlatLimitRegardlessOfIntent() {
        let local = DiffImageBlobSource.git(.worktree(path: "a.png"))
        XCTAssertEqual(
            DiffImagePreviewSupport.byteLimit(for: local, intent: .automatic),
            DiffImagePreviewSupport.maxSourceBytes
        )
        XCTAssertEqual(
            DiffImagePreviewSupport.byteLimit(for: local, intent: .confirmed),
            DiffImagePreviewSupport.maxSourceBytes
        )
    }
}
