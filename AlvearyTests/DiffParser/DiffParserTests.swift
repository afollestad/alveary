import XCTest

@testable import Alveary

final class DiffParserTests: XCTestCase {
    func testParseReturnsEmptyArrayForEmptyDiff() {
        XCTAssertTrue(DiffParser.parse("").isEmpty)
    }

    func testParseMultiFileDiffCapturesPathsCountsAndLineNumbers() {
        let diff = """
        diff --git a/src/auth.swift b/src/auth.swift
        index 1111111..2222222 100644
        --- a/src/auth.swift
        +++ b/src/auth.swift
        @@ -10,7 +10,8 @@ func validateToken(_ token: Token) -> Bool {
             guard let expiry = token.expiry else {
                 return false
             }
        -    return expiry > Date()
        +    let now = Date()
        +    return expiry > now && !token.isRevoked
         }
        diff --git a/src/auth.test.swift b/src/auth.test.swift
        new file mode 100644
        --- /dev/null
        +++ b/src/auth.test.swift
        @@ -0,0 +1,3 @@
        +import XCTest
        +
        +final class AuthTests: XCTestCase {}
        """

        let files = DiffParser.parse(diff)

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].path, "src/auth.swift")
        XCTAssertEqual(files[0].linesAdded, 2)
        XCTAssertEqual(files[0].linesDeleted, 1)
        XCTAssertEqual(files[0].hunks[0].header, "func validateToken(_ token: Token) -> Bool {")
        XCTAssertEqual(
            files[0].hunks[0].lines[3],
            DiffLine(type: .deleted, content: "    return expiry > Date()", oldLineNumber: 13, newLineNumber: nil)
        )
        XCTAssertEqual(
            files[0].hunks[0].lines[4],
            DiffLine(type: .added, content: "    let now = Date()", oldLineNumber: nil, newLineNumber: 13)
        )
        XCTAssertNil(files[1].oldPath)
        XCTAssertEqual(files[1].newPath, "src/auth.test.swift")
    }

    func testParseSplitsCRLFLinesWithoutSwallowingTheNextFile() {
        let diff = "diff --git a/run.bat b/run.bat\n--- a/run.bat\n+++ b/run.bat\n@@ -1,2 +1,2 @@ :start\r\n"
            + " echo\r\n-old\r\n+new\r\n"
            + "diff --git a/next.txt b/next.txt\n--- a/next.txt\n+++ b/next.txt\n@@ -1 +1 @@\n-x\n+y\n"

        let files = DiffParser.parse(diff)

        XCTAssertEqual(files.map(\.path), ["run.bat", "next.txt"])
        XCTAssertEqual(files[0].hunks[0].header, ":start")
        XCTAssertEqual(files[0].hunks[0].lines, [
            DiffLine(type: .context, content: "echo", oldLineNumber: 1, newLineNumber: 1),
            DiffLine(type: .deleted, content: "old", oldLineNumber: 2, newLineNumber: nil),
            DiffLine(type: .added, content: "new", oldLineNumber: nil, newLineNumber: 2)
        ])
    }

    func testParseHandlesRenameAndBinaryMarkers() {
        let diff = """
        diff --git a/old.txt b/new.txt
        similarity index 100%
        rename from old.txt
        rename to new.txt
        Binary files a/old.txt and b/new.txt differ
        """

        let files = DiffParser.parse(diff)

        XCTAssertEqual(files, [
            DiffFile(oldPath: "old.txt", newPath: "new.txt", isBinary: true, isRenamed: true, hunks: [])
        ])
    }

    func testParseHunkHeaderKeepsAtSignsInContextSuffix() {
        let diff = """
        diff --git a/Foo.swift b/Foo.swift
        index 1111111..2222222 100644
        --- a/Foo.swift
        +++ b/Foo.swift
        @@ -1,1 +1,1 @@ @MainActor func load() {
        -oldValue()
        +newValue()
        """

        let files = DiffParser.parse(diff)

        XCTAssertEqual(files[0].hunks[0].header, "@MainActor func load() {")
    }
}
