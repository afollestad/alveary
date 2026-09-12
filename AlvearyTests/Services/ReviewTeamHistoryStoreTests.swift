import CryptoKit
import Foundation
import Testing

@testable import Alveary

struct ReviewTeamHistoryStoreTests {
    @Test func `history is private and deduplicated within each run`() async throws {
        let fixture = try HistoryStoreFixture()
        defer { fixture.cleanUp() }
        let store = ReviewTeamHistoryStore(rootDirectory: fixture.root)
        let data = Data("exact prompt\n".utf8)
        let first = try await store.save(conversationID: "task/one", runID: "run/one", name: "../prompt", data: data)
        let second = try await store.save(conversationID: "task/one", runID: "run/one", name: "response", data: data)
        let run = fixture.runDirectory(conversationID: "task/one", runID: "run/one")

        #expect(first == ReviewHistoryArtifact(id: fixture.digest(data), name: "../prompt", byteCount: data.count))
        #expect(second.id == first.id)
        #expect(second.name == "response")
        #expect(try await store.read(first, conversationID: "task/one", runID: "run/one") == data)
        #expect(try fixture.children(of: run) == [first.id])
        #expect(try fixture.permissions(at: fixture.root) == 0o700)
        #expect(try fixture.permissions(at: run.deletingLastPathComponent()) == 0o700)
        #expect(try fixture.permissions(at: run) == 0o700)
        #expect(try fixture.permissions(at: run.appendingPathComponent(first.id)) == 0o400)

        let reopened = ReviewTeamHistoryStore(rootDirectory: fixture.root)
        #expect(try await reopened.read(first, conversationID: "task/one", runID: "run/one") == data)
        await #expect(throws: ReviewTeamHistoryStoreError.missingArtifact) {
            try await store.read(first, conversationID: "other", runID: "run/one")
        }
    }

    @Test func `read rejects modified bytes and incorrect artifact sizes`() async throws {
        let fixture = try HistoryStoreFixture()
        defer { fixture.cleanUp() }
        let store = ReviewTeamHistoryStore(rootDirectory: fixture.root)
        let artifact = try await fixture.save(in: store, text: "original")
        let incorrect = ReviewHistoryArtifact(id: artifact.id, name: artifact.name, byteCount: artifact.byteCount + 1)
        await #expect(throws: ReviewTeamHistoryStoreError.changedArtifact) {
            try await store.read(incorrect, conversationID: "task", runID: "run")
        }
        let blob = fixture.runDirectory().appendingPathComponent(artifact.id)
        try fixture.replaceBlob(blob, data: Data("modified".utf8))
        await #expect(throws: ReviewTeamHistoryStoreError.changedArtifact) {
            try await store.read(artifact, conversationID: "task", runID: "run")
        }
        await #expect(throws: ReviewTeamHistoryStoreError.changedArtifact) {
            try await fixture.save(in: store, text: "original")
        }
    }

    @Test func `artifact identifiers cannot escape the run directory`() async throws {
        let fixture = try HistoryStoreFixture()
        defer { fixture.cleanUp() }
        let store = ReviewTeamHistoryStore(rootDirectory: fixture.root)
        let artifact = ReviewHistoryArtifact(id: "../outside", name: "prompt", byteCount: 4)
        await #expect(throws: ReviewTeamHistoryStoreError.invalidArtifact) {
            try await store.read(artifact, conversationID: "task", runID: "run")
        }
        #expect(!fixture.exists(fixture.root))
    }

    @Test func `redirected conversation directories are never followed or removed`() async throws {
        let fixture = try HistoryStoreFixture()
        defer { fixture.cleanUp() }
        let store = ReviewTeamHistoryStore(rootDirectory: fixture.root)
        let artifact = try await fixture.save(in: store)
        let conversation = fixture.runDirectory().deletingLastPathComponent()
        let outside = fixture.parent.appendingPathComponent("outside")
        try FileManager.default.moveItem(at: conversation, to: outside)
        try FileManager.default.createSymbolicLink(at: conversation, withDestinationURL: outside)

        await #expect(throws: ReviewTeamHistoryStoreError.pathEscapedRoot) {
            try await store.read(artifact, conversationID: "task", runID: "run")
        }
        await #expect(throws: ReviewTeamHistoryStoreError.pathEscapedRoot) {
            try await fixture.save(in: store)
        }
        await #expect(throws: ReviewTeamHistoryStoreError.pathEscapedRoot) {
            try await store.remove(conversationID: "task")
        }
        #expect(fixture.exists(outside.appendingPathComponent(fixture.digest(Data("run".utf8))).appendingPathComponent(artifact.id)))
        await #expect(throws: ReviewTeamHistoryStoreError.deletedConversation) {
            try await fixture.save(in: store)
        }
    }

    @Test func `root and blob symlinks are rejected even when their destinations are inside storage`() async throws {
        let fixture = try HistoryStoreFixture()
        defer { fixture.cleanUp() }
        let store = ReviewTeamHistoryStore(rootDirectory: fixture.root)
        let first = try await fixture.save(in: store, text: "first")
        let second = try await fixture.save(in: store, text: "second")
        let blob = fixture.runDirectory().appendingPathComponent(first.id)
        let destination = fixture.runDirectory().appendingPathComponent(second.id)
        try FileManager.default.removeItem(at: blob)
        try FileManager.default.createSymbolicLink(at: blob, withDestinationURL: destination)
        await #expect(throws: ReviewTeamHistoryStoreError.pathEscapedRoot) {
            try await store.read(first, conversationID: "task", runID: "run")
        }
        await #expect(throws: ReviewTeamHistoryStoreError.pathEscapedRoot) {
            try await store.prune(retainingConversationIDs: [])
        }
        #expect(fixture.exists(destination))

        let original = fixture.parent.appendingPathComponent("original")
        try FileManager.default.moveItem(at: fixture.root, to: original)
        try FileManager.default.createSymbolicLink(at: fixture.root, withDestinationURL: original)
        let reopened = ReviewTeamHistoryStore(rootDirectory: fixture.root)
        await #expect(throws: ReviewTeamHistoryStoreError.pathEscapedRoot) {
            try await reopened.prune(retainingConversationIDs: [])
        }
        await #expect(throws: ReviewTeamHistoryStoreError.pathEscapedRoot) {
            try await store.remove(conversationID: "task")
        }
        #expect(fixture.exists(original))
    }

    @Test func `limits count unique bytes per run and reject oversized captures before writing`() async throws {
        let fixture = try HistoryStoreFixture()
        defer { fixture.cleanUp() }
        let store = ReviewTeamHistoryStore(rootDirectory: fixture.root, maximumRunBytes: 6, maximumFileBytes: 4)
        await #expect(throws: ReviewTeamHistoryStoreError.fileTooLarge(limitBytes: 4)) {
            try await fixture.save(in: store, text: "12345")
        }
        #expect(!fixture.exists(fixture.root))
        let first = try await fixture.save(in: store, text: "1234")
        let duplicate = try await fixture.save(in: store, text: "1234")
        #expect(duplicate == first)
        await #expect(throws: ReviewTeamHistoryStoreError.runTooLarge(limitBytes: 6)) {
            try await fixture.save(in: store, text: "567")
        }
        #expect(try fixture.children(of: fixture.runDirectory()) == [first.id])
        _ = try await fixture.save(in: store, text: "56")
        _ = try await store.save(conversationID: "task", runID: "other", name: "prompt", data: Data("5678".utf8))
        #expect(try fixture.children(of: fixture.runDirectory()).count == 2)
    }

    @Test func `prune retains live tasks and deletion prevents late saves`() async throws {
        let fixture = try HistoryStoreFixture()
        defer { fixture.cleanUp() }
        let store = ReviewTeamHistoryStore(rootDirectory: fixture.root)
        let artifact = try await fixture.save(in: store)
        _ = try await store.save(conversationID: "task", runID: "older", name: "prompt", data: Data("old".utf8))
        let previousStore = ReviewTeamHistoryStore(rootDirectory: fixture.root)
        _ = try await previousStore.save(conversationID: "deleted", runID: "run", name: "prompt", data: Data("gone".utf8))
        try await store.prune(retainingConversationIDs: ["task"])
        #expect(try await store.read(artifact, conversationID: "task", runID: "run") == Data("prompt".utf8))
        #expect(!fixture.exists(fixture.runDirectory(conversationID: "deleted")))
        #expect(fixture.exists(fixture.runDirectory(runID: "older")))
        try await store.remove(conversationID: "task")
        #expect(try fixture.children(of: fixture.root).isEmpty)
        await #expect(throws: ReviewTeamHistoryStoreError.deletedConversation) {
            try await fixture.save(in: store)
        }
        try await store.remove(conversationID: "not-yet-created")
        await #expect(throws: ReviewTeamHistoryStoreError.deletedConversation) {
            try await store.save(conversationID: "not-yet-created", runID: "run", name: "prompt", data: Data())
        }
    }

    @Test func `cleanup of absent history does not create storage`() async throws {
        let fixture = try HistoryStoreFixture()
        defer { fixture.cleanUp() }
        let store = ReviewTeamHistoryStore(rootDirectory: fixture.root)
        try await store.prune(retainingConversationIDs: [])
        try await store.remove(conversationID: "task")
        #expect(!fixture.exists(fixture.root))
        await #expect(throws: ReviewTeamHistoryStoreError.deletedConversation) {
            try await fixture.save(in: store)
        }
    }

    @Test func `deletion removes modified blobs and interrupted temporary writes`() async throws {
        let fixture = try HistoryStoreFixture()
        defer { fixture.cleanUp() }
        let store = ReviewTeamHistoryStore(rootDirectory: fixture.root)
        let artifact = try await fixture.save(in: store)
        let blob = fixture.runDirectory().appendingPathComponent(artifact.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: blob.path)
        try Data("partial".utf8).write(to: fixture.runDirectory().appendingPathComponent(".interrupted-write"))
        try await store.remove(conversationID: "task")
        #expect(try fixture.children(of: fixture.root).isEmpty)
    }

    @Test func `startup pruning cannot delete history saved after its task snapshot`() async throws {
        let fixture = try HistoryStoreFixture()
        defer { fixture.cleanUp() }
        let store = ReviewTeamHistoryStore(rootDirectory: fixture.root)
        let artifact = try await fixture.save(in: store)
        try await store.prune(retainingConversationIDs: [])
        #expect(try await store.read(artifact, conversationID: "task", runID: "run") == Data("prompt".utf8))
        try await store.remove(conversationID: "task")
        try await store.prune(retainingConversationIDs: [])
        #expect(try fixture.children(of: fixture.root).isEmpty)
    }

    @Test(arguments: [false, true])
    func `missing roots resolve existing aliases regardless of directory hints`(directoryHint: Bool) async throws {
        let fixture = try HistoryStoreFixture()
        defer { fixture.cleanUp() }
        let alias = fixture.parent.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.parent)
        let root = URL(fileURLWithPath: alias.appendingPathComponent("new/history").path, isDirectory: directoryHint)
        let store = ReviewTeamHistoryStore(rootDirectory: root)
        let artifact = try await fixture.save(in: store)

        #expect(try await store.read(artifact, conversationID: "task", runID: "run") == Data("prompt".utf8))
        let reopened = ReviewTeamHistoryStore(rootDirectory: root)
        #expect(try await reopened.read(artifact, conversationID: "task", runID: "run") == Data("prompt".utf8))
        try await store.remove(conversationID: "task")
        #expect(try fixture.children(of: root).isEmpty)
    }
}

private struct HistoryStoreFixture {
    let parent: URL
    var root: URL { parent.appendingPathComponent("history", isDirectory: true) }

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("review-history-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    func save(in store: ReviewTeamHistoryStore, text: String = "prompt") async throws -> ReviewHistoryArtifact {
        try await store.save(conversationID: "task", runID: "run", name: "prompt", data: Data(text.utf8))
    }

    func runDirectory(conversationID: String = "task", runID: String = "run") -> URL {
        root.appendingPathComponent(digest(Data(conversationID.utf8)), isDirectory: true)
            .appendingPathComponent(digest(Data(runID.utf8)), isDirectory: true)
    }

    func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func children(of url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    func permissions(at url: URL) throws -> Int? {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func replaceBlob(_ url: URL, data: Data) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: parent) }
}
