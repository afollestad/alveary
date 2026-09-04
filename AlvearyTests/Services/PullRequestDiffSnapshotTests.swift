import Foundation
import Testing

@testable import Alveary

struct PullRequestDiffSnapshotTests {
    @Test func `unrecognized output is never reported as an empty diff`() {
        #expect(throws: PullRequestDiffError.self) { try PullRequestDiffSnapshot.make(text: "unable to fetch the diff") }
    }

    @Test func `large hunks and UTF8 lines resume without dropping bytes`() throws {
        let lines = String(repeating: "+" + String(repeating: "x", count: 220) + "\n", count: 25_000)
        let longLine = "+" + String(repeating: "🐝", count: 90_000) + "\n"
        let patch = "@@ -0,0 +1,25001 @@\n" + lines + longLine
        let text = "diff --git a/large.txt b/large.txt\nnew file mode 100644\n--- /dev/null\n+++ b/large.txt\n" + patch
        let snapshot = try PullRequestDiffSnapshot.make(text: text)
        #expect(snapshot.byteCount > 5 * 1024 * 1024)
        #expect(snapshot.files.first?.additions == 25_001)
        #expect(throws: PullRequestsServiceError.responseTooLarge) { try snapshot.text(maxBytes: 5 * 1024 * 1024) }
        var reconstructed = ""
        var offset = 0
        var sawContinuation = false
        while offset < patch.utf8.count {
            let fragment = try snapshot.fragment(file: 0, offset: offset, maxBytes: 15_001)
            #expect(fragment.nextOffset > offset)
            reconstructed += fragment.text
            offset = fragment.nextOffset
            if fragment.startsMidLine {
                sawContinuation = true
                #expect(fragment.newLine != nil)
            }
        }
        #expect(reconstructed == patch)
        #expect(sawContinuation)
        let files = try snapshot.parsedFiles(paths: ["large.txt"])
        #expect(files.first?.hunks.first?.lines.last?.newLineNumber == 25_001)
    }

    @Test func `index preserves quoted paths renames deletions and binary files`() throws {
        let text = #"""
        diff --git "a/old\tname.txt" "b/new\n\303\251.txt"
        similarity index 100%
        rename from "old\tname.txt"
        rename to "new\n\303\251.txt"
        diff --git a/image.png b/image.png
        Binary files a/image.png and b/image.png differ
        diff --git "a/deleted\tfile" "b/deleted\tfile"
        deleted file mode 100644
        --- "a/deleted\tfile"
        +++ /dev/null
        @@ -1 +0,0 @@
        -gone
        """#
        let snapshot = try PullRequestDiffSnapshot.make(text: text)
        #expect(snapshot.files.map(\.metadata.path) == ["new\né.txt", "image.png", "deleted\tfile"])
        #expect(snapshot.files[0].metadata.oldPath == "old\tname.txt")
        #expect(snapshot.files[1].metadata.isBinary)
        #expect(snapshot.files[2].deletions == 1)
        #expect(try snapshot.parsedFiles(paths: ["old\tname.txt"]).count == 1)
    }

    @Test func `snapshot releases its owned directory`() throws {
        var snapshot: PullRequestDiffSnapshot? = try .make(text: "")
        let url = try #require(snapshot?.url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        snapshot = nil
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }
}
