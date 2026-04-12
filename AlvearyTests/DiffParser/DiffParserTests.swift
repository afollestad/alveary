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
