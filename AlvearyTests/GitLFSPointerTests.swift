import XCTest
@testable import Alveary

final class GitLFSPointerTests: XCTestCase {
    private static let oid = "e908b5e52be4ecc4d05c38ad7afa27021fbb7472ff2d8eae58ae95fd0aca806a"

    private static func pointerLines(
        oid: String = GitLFSPointerTests.oid,
        size: String = "166854"
    ) -> [String] {
        [
            "version https://git-lfs.github.com/spec/v1",
            "oid sha256:\(oid)",
            "size \(size)"
        ]
    }

    // MARK: - Grammar

    func testParsesACanonicalPointer() throws {
        let pointer = try XCTUnwrap(GitLFSPointer.parse(lines: Self.pointerLines()))
        XCTAssertEqual(pointer.oid, Self.oid)
        XCTAssertEqual(pointer.byteSize, 166_854)
    }

    func testIgnoresBlankLinesAndSurroundingWhitespace() throws {
        let lines = [
            "  version https://git-lfs.github.com/spec/v1  ",
            "",
            "oid sha256:\(Self.oid)\t",
            "size 166854",
            ""
        ]
        XCTAssertEqual(GitLFSPointer.parse(lines: lines)?.byteSize, 166_854)
    }

    /// The case that motivated the strict grammar: source or documentation quoting the spec URL
    /// must not be turned into an image row.
    func testRejectsAFileThatMerelyMentionsTheSpecURL() {
        let lines = [
            "// See version https://git-lfs.github.com/spec/v1 for the pointer format.",
            "let oid = \"sha256:\(Self.oid)\""
        ]
        XCTAssertNil(GitLFSPointer.parse(lines: lines))
    }

    func testRejectsAPointerCarryingExtraContent() {
        XCTAssertNil(GitLFSPointer.parse(lines: Self.pointerLines() + ["trailing garbage"]))
    }

    func testRejectsAVersionLineThatIsNotFirst() {
        let lines = [
            "oid sha256:\(Self.oid)",
            "version https://git-lfs.github.com/spec/v1",
            "size 166854"
        ]
        XCTAssertNil(GitLFSPointer.parse(lines: lines))
    }

    func testRejectsAMissingSizeOrOID() {
        XCTAssertNil(GitLFSPointer.parse(lines: Array(Self.pointerLines().prefix(2))))
        XCTAssertNil(GitLFSPointer.parse(lines: [Self.pointerLines()[0], Self.pointerLines()[2]]))
    }

    func testRejectsADuplicatedField() {
        XCTAssertNil(GitLFSPointer.parse(lines: Self.pointerLines() + ["size 12"]))
    }

    func testRejectsAMalformedDigest() {
        XCTAssertNil(GitLFSPointer.parse(lines: Self.pointerLines(oid: String(Self.oid.dropLast()))))
        XCTAssertNil(GitLFSPointer.parse(lines: Self.pointerLines(oid: Self.oid.uppercased())))
        XCTAssertNil(GitLFSPointer.parse(lines: Self.pointerLines(oid: String(repeating: "z", count: 64))))
    }

    func testRejectsANonNumericSize() {
        XCTAssertNil(GitLFSPointer.parse(lines: Self.pointerLines(size: "12kb")))
        XCTAssertNil(GitLFSPointer.parse(lines: Self.pointerLines(size: "-4")))
        XCTAssertNil(GitLFSPointer.parse(lines: Self.pointerLines(size: "")))
    }

    // MARK: - Sides of a file diff

    func testExtractsBothSidesOfAModifiedPointer() throws {
        let newOID = String(repeating: "a", count: 64)
        let diff = """
        diff --git a/hero.png b/hero.png
        index abbe130..cd91f22 100644
        --- a/hero.png
        +++ b/hero.png
        @@ -1,3 +1,3 @@
         version https://git-lfs.github.com/spec/v1
        -oid sha256:\(Self.oid)
        -size 166854
        +oid sha256:\(newOID)
        +size 42
        """
        let file = try XCTUnwrap(DiffParser.parse(diff).first)
        let pointers = GitLFSPointer.pointers(in: file)
        XCTAssertEqual(pointers.old?.oid, Self.oid)
        XCTAssertEqual(pointers.old?.byteSize, 166_854)
        XCTAssertEqual(pointers.new?.oid, newOID)
        XCTAssertEqual(pointers.new?.byteSize, 42)
    }

    func testAnAddedPointerHasNoOldSide() throws {
        let diff = """
        diff --git a/hero.png b/hero.png
        new file mode 100644
        index 0000000..abbe130
        --- /dev/null
        +++ b/hero.png
        @@ -0,0 +1,3 @@
        +version https://git-lfs.github.com/spec/v1
        +oid sha256:\(Self.oid)
        +size 166854
        """
        let file = try XCTUnwrap(DiffParser.parse(diff).first)
        let pointers = GitLFSPointer.pointers(in: file)
        XCTAssertNil(pointers.old)
        XCTAssertEqual(pointers.new?.oid, Self.oid)
    }

    func testADeletedPointerHasNoNewSide() throws {
        let diff = """
        diff --git a/hero.png b/hero.png
        deleted file mode 100644
        index abbe130..0000000
        --- a/hero.png
        +++ /dev/null
        @@ -1,3 +0,0 @@
        -version https://git-lfs.github.com/spec/v1
        -oid sha256:\(Self.oid)
        -size 166854
        """
        let file = try XCTUnwrap(DiffParser.parse(diff).first)
        let pointers = GitLFSPointer.pointers(in: file)
        XCTAssertEqual(pointers.old?.oid, Self.oid)
        XCTAssertNil(pointers.new)
    }

    /// Every file in a pull request diff is asked, so a large one must not have its lines copied
    /// just to be rejected.
    func testALargeFileIsRejectedOnItsLineCountAlone() throws {
        let body = (1...500).map { "+line \($0)" }.joined(separator: "\n")
        let diff = """
        diff --git a/Big.swift b/Big.swift
        new file mode 100644
        --- /dev/null
        +++ b/Big.swift
        @@ -0,0 +1,500 @@
        \(body)
        """
        let file = try XCTUnwrap(DiffParser.parse(diff).first)
        XCTAssertGreaterThan(file.hunks.first?.lines.count ?? 0, 12)

        let pointers = GitLFSPointer.pointers(in: file)
        XCTAssertNil(pointers.old)
        XCTAssertNil(pointers.new)
    }

    /// The guard must still admit the longest shape a real pointer diff takes: three lines replaced
    /// by three.
    func testAFullyRewrittenPointerStaysWithinTheLineBudget() throws {
        let newOID = String(repeating: "b", count: 64)
        let diff = """
        diff --git a/hero.png b/hero.png
        index abbe130..cd91f22 100644
        --- a/hero.png
        +++ b/hero.png
        @@ -1,3 +1,3 @@
        -version https://git-lfs.github.com/spec/v1
        -oid sha256:\(Self.oid)
        -size 166854
        +version https://git-lfs.github.com/spec/v1
        +oid sha256:\(newOID)
        +size 42
        """
        let file = try XCTUnwrap(DiffParser.parse(diff).first)
        let pointers = GitLFSPointer.pointers(in: file)
        XCTAssertEqual(pointers.old?.oid, Self.oid)
        XCTAssertEqual(pointers.new?.oid, newOID)
    }

    func testAnOrdinaryTextDiffYieldsNoPointers() throws {
        let diff = """
        diff --git a/README.md b/README.md
        index abbe130..cd91f22 100644
        --- a/README.md
        +++ b/README.md
        @@ -1,2 +1,2 @@
         # Title
        -old line
        +new line
        """
        let file = try XCTUnwrap(DiffParser.parse(diff).first)
        let pointers = GitLFSPointer.pointers(in: file)
        XCTAssertNil(pointers.old)
        XCTAssertNil(pointers.new)
    }
}
