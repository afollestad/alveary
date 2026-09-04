import AgentCLIKit
import Foundation
import Testing

@testable import Alveary

@MainActor
struct PullRequestDiffPagingTests {
    @Test func `tool resumes preparation without another fetch`() async throws {
        let fixture = try PullRequestHostToolFixture()
        let gate = PullRequestsServiceGate()
        fixture.pullRequests.diffGate = gate
        fixture.pullRequests.detailResult = .success(makePullRequestDetail(id: identifier))
        fixture.pullRequests.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let service = PullRequestHostToolService(
            modelContext: fixture.modelContext, pullRequestsService: fixture.pullRequests,
            settingsService: fixture.settingsService, summaryHandoff: fixture.summaryHandoff, diffWait: .zero
        )
        let initial = await service.handle(context: fixture.agentContext(), call: .init(
            name: PullRequestHostToolCatalog.diffToolName, arguments: ["url": .string(PullRequestHostToolFixture.url)]
        ))
        let content = try diffPageObject(initial.structuredContent)
        #expect(content["status"] == .string("preparing"))
        let cursor = try #require(content["next_cursor"])
        gate.open()
        guard case .string(let token) = cursor else { throw PullRequestDiffError.expired }
        let parsed = try PullRequestHostToolDiffCursor.decode(token)
        _ = try await service.diffJobs.value(id: parsed.job)
        let resumed = await service.handle(context: fixture.agentContext(), call: .init(
            name: PullRequestHostToolCatalog.diffToolName, arguments: ["cursor": cursor]
        ))
        #expect(try diffPageObject(resumed.structuredContent)["status"] == .string("ready"))
        #expect(fixture.pullRequests.diffCallCount == 1)
        #expect(fixture.pullRequests.detailCallCount == 1)
    }

    @Test func `every long line and large inventory is reachable within the output limit`() throws {
        let patch = "@@ -0,0 +1 @@\n+" + String(repeating: "🐝", count: 100_000) + "\n"
        let first = "diff --git a/large b/large\n--- /dev/null\n+++ b/large\n" + patch
        let inventory = (0..<4_000).map { "diff --git a/metadata\($0) b/metadata\($0)\nold mode 100644\nnew mode 100755\n" }
            .joined()
        let snapshot = try PullRequestDiffSnapshot.make(text: first + inventory)
        let session = PullRequestHostToolDiffSession(snapshot: snapshot, detail: makePullRequestDetail(id: identifier),
                                                    source: "test", identifier: identifier)
        var cursor = PullRequestHostToolDiffCursor(job: "test", identifier: identifier, paths: nil)
        var paths = Set<String>()
        var reconstructed = ""
        var pages = 0
        while true {
            let result = try PullRequestHostToolDiffPage(session: session, cursor: cursor).render()
            let content = try diffPageObject(result.structuredContent)
            #expect(result.text.utf8.count + (try JSONEncoder().encode(result.structuredContent)).count < 1_000_000)
            if case .array(let files) = content["files"] {
                for file in files {
                    let row = try diffPageObject(file)
                    if case .string(let path) = row["path"] { paths.insert(path) }
                    if case .string(let text) = row["patch"] { reconstructed += text }
                }
            }
            pages += 1
            guard case .string(let token) = content["next_cursor"] else { break }
            cursor = try PullRequestHostToolDiffCursor.decode(token)
            try #require(pages < 100, "Cursor must make forward progress")
        }
        #expect(pages > 1)
        #expect(paths.count == 4_001)
        #expect(reconstructed == patch)
    }

    @Test func `review threads page without overflowing or disappearing`() throws {
        let snapshot = try PullRequestDiffSnapshot.make(text: makeUnifiedDiffFixture(fileCount: 1))
        var detail = makePullRequestDetail(id: identifier)
        detail.reviewThreads = (0..<100).map {
            makeReviewThread(nodeID: "thread\($0)", path: "File0.swift", line: 1, isPending: false,
                             bodies: Array(repeating: String(repeating: "🐝", count: 2_000), count: 10))
        }
        let session = PullRequestHostToolDiffSession(snapshot: snapshot, detail: detail, source: "test", identifier: identifier)
        var cursor = PullRequestHostToolDiffCursor(job: "test", identifier: identifier, paths: nil)
        var ids: [String] = []
        while true {
            let result = try PullRequestHostToolDiffPage(session: session, cursor: cursor).render()
            #expect(result.text.utf8.count + (try JSONEncoder().encode(result.structuredContent)).count < 1_000_000)
            let content = try diffPageObject(result.structuredContent)
            if case .array(let files) = content["files"] {
                for file in files {
                    if case .array(let threads) = try diffPageObject(file)["threads"] {
                        for thread in threads {
                            if case .string(let id) = try diffPageObject(thread)["thread_id"] { ids.append(id) }
                        }
                    }
                }
            }
            guard case .string(let token) = content["next_cursor"] else { break }
            cursor = try PullRequestHostToolDiffCursor.decode(token)
        }
        #expect(ids.count == 100)
        #expect(Set(ids).count == 100)
    }

    @Test func `a changed revision must be read before proposing a review`() async throws {
        let fixture = try PullRequestHostToolFixture()
        var detail = makePullRequestDetail(id: identifier)
        detail.headRefOid = "new-head"
        detail.baseRefOid = "base"
        fixture.pullRequests.detailResult = .success(detail)
        let key = "\(fixture.agentContext().conversationId.rawValue):\(identifier.displayKey)"
        fixture.service.reviewedDiffRevisions[key] = ("base", "old-head")
        let result = await fixture.handle(PullRequestHostToolCatalog.proposeReviewToolName, arguments: [
            "url": .string(PullRequestHostToolFixture.url), "event": .string("approve")
        ])
        #expect(result.isError)
        #expect(result.text.contains("changed"))
        #expect(fixture.pullRequests.diffCallCount == 0)
    }

    @Test func `cursor restores its path filter without serializing the paths`() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.detailResult = .success(makePullRequestDetail(id: identifier))
        fixture.pullRequests.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2, addedLinesPerFile: 30_000))
        var arguments: [String: AgentCLIKit.JSONValue] = [
            "url": .string(PullRequestHostToolFixture.url), "paths": .array([.string("File1.swift")])
        ]
        var pages = 0
        while true {
            let result = await fixture.handle(PullRequestHostToolCatalog.diffToolName, arguments: arguments)
            #expect(!result.isError)
            let content = try diffPageObject(result.structuredContent)
            #expect(content["total_files"] == .number(1))
            if case .array(let files) = content["files"] {
                for file in files { #expect(try diffPageObject(file)["path"] == .string("File1.swift")) }
            }
            pages += 1
            try #require(pages < 10)
            guard let token = content["next_cursor"] else { break }
            arguments = ["cursor": token]
        }
        #expect(pages > 1)
        #expect(fixture.pullRequests.diffCallCount == 1)
    }

    private var identifier: PullRequestIdentifier { .init(owner: "octo", repo: "alpha", number: 7) }
}

private func diffPageObject(_ value: AgentCLIKit.JSONValue?) throws -> [String: AgentCLIKit.JSONValue] {
    guard case .object(let object) = value else { throw PullRequestDiffError.invalidEncoding }
    return object
}
