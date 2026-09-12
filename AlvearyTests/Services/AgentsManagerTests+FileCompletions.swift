import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testBackgroundToolResultRefreshesFileCompletionsInEveryWorkspaceRoot() async throws {
        let fixture = try await makeFileCompletionRuntimeFixture()
        defer { fixture.remove() }
        let before = await fixture.loadFiles()
        XCTAssertEqual(before, fixture.originalFiles)
        XCTAssertFalse(fixture.manager.conversationState(for: fixture.conversationId).isViewMounted)
        try fixture.replaceFiles()
        let cached = await fixture.loadFiles()
        XCTAssertEqual(cached, before)

        let generation = try await fixture.bufferGeneration()
        await fixture.manager.handleStreamEvent(
            .toolResult(id: "write", output: "Done", isError: false, parentToolUseId: nil, metadata: nil),
            conversationId: fixture.conversationId,
            generation: generation,
            providerId: "claude"
        )

        let refreshed = await fixture.loadFiles()
        XCTAssertEqual(refreshed, fixture.replacementFiles)
    }

    func testRetiredSubscriptionCannotInvalidateReplacementWorkspaceCompletions() async throws {
        let fixture = try await makeFileCompletionRuntimeFixture()
        defer { fixture.remove() }
        let oldGeneration = try await fixture.bufferGeneration()
        let newEvents = AsyncStream<AgentCLIKit.AgentEventEnvelope>.makeStream()
        defer { newEvents.continuation.finish() }
        await fixture.manager.installAgentCLIKitSubscriptionBuffer(
            conversationId: fixture.conversationId,
            config: spawnConfig(workingDirectory: fixture.primary.path),
            subscription: AgentCLIKit.AgentEventSubscription(generation: 2, events: newEvents.stream)
        )
        let before = await fixture.loadFiles()
        try fixture.replaceFiles()

        await fixture.manager.handleStreamEvent(
            .stop(message: nil), conversationId: fixture.conversationId,
            generation: oldGeneration, providerId: "claude"
        )
        let stillCached = await fixture.loadFiles()
        XCTAssertEqual(stillCached, before)

        let currentGeneration = try await fixture.bufferGeneration()
        await fixture.manager.handleStreamEvent(
            .stop(message: nil), conversationId: fixture.conversationId,
            generation: currentGeneration, providerId: "claude"
        )
        let currentFiles = await fixture.loadFiles()
        // The replacement explicitly removed its secondary grant; only its primary is invalidated.
        XCTAssertEqual(currentFiles, [fixture.replacementFiles[0], fixture.originalFiles[1]])
    }

    func testProviderGenerationReplacementRetainsWorkspaceCompletionRoots() async throws {
        let fixture = try await makeFileCompletionRuntimeFixture()
        defer { fixture.remove() }
        _ = await fixture.loadFiles()
        try fixture.replaceFiles()
        fixture.events.continuation.yield(AgentCLIKit.AgentEventEnvelope(
            generation: 2, index: 1, providerId: .claude,
            conversationId: AgentCLIKit.AgentConversationID(rawValue: fixture.conversationId),
            providerSessionId: nil, source: .process,
            event: .lifecycle(AgentCLIKit.AgentLifecycleEvent(state: .exited))
        ))
        try await waitUntil("expected replacement generation terminal event") {
            let generation = await fixture.manager.agentCLIKitGenerationByConversation[fixture.conversationId]
            let eventCount = await fixture.manager.eventBuffers[fixture.conversationId]?.observedEventCount
            return generation == 2 && eventCount == 1
        }
        let refreshed = await fixture.loadFiles()
        XCTAssertEqual(refreshed, fixture.replacementFiles)
    }

    func testBackgroundTaskStatusSettlementRefreshesUnselectedFolderCompletions() async throws {
        let fixture = try await makeFileCompletionRuntimeFixture()
        defer { fixture.remove() }
        await fixture.manager.applyAgentCLIKitStatus(
            fixture.status(index: 1, backgroundTasks: 1), conversationId: fixture.conversationId
        )
        _ = await fixture.loadFiles()
        try fixture.replaceFiles()
        await fixture.manager.applyAgentCLIKitStatus(
            fixture.status(index: 2, backgroundTasks: 0), conversationId: fixture.conversationId
        )
        let refreshed = await fixture.loadFiles()
        XCTAssertEqual(refreshed, fixture.replacementFiles)
    }

    private func makeFileCompletionRuntimeFixture() async throws -> FileCompletionRuntimeFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let primary = root.appendingPathComponent("primary")
        let secondary = root.appendingPathComponent("secondary")
        for directory in [primary, secondary] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent("old.txt"))
        }
        let shell = MockShellRunner(defaultResponse: .success(ShellResult(
            stdout: "", stderr: "fatal: not a git repository", exitCode: 128,
            stdoutWasTruncated: false, stderrWasTruncated: false
        )))
        let files = GitFileListManager(gitService: CLIGitService(shell: shell))
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: "agent"),
            detectedPath: "/usr/bin/agent", basePath: "/usr/bin:/bin", fileListManager: files
        ).manager
        let conversationId = UUID().uuidString
        let events = AsyncStream<AgentCLIKit.AgentEventEnvelope>.makeStream()
        await manager.installAgentCLIKitSubscriptionBuffer(
            conversationId: conversationId,
            config: Alveary.AgentSpawnConfig(
                providerId: "claude", workingDirectory: primary.path, additionalWorkspaceRoots: [primary.path, secondary.path]
            ),
            subscription: AgentCLIKit.AgentEventSubscription(generation: 1, events: events.stream)
        )
        return FileCompletionRuntimeFixture(
            root: root, primary: primary, secondary: secondary, manager: manager, fileListManager: files,
            conversationId: conversationId, events: events
        )
    }
}

@MainActor
private struct FileCompletionRuntimeFixture {
    let root: URL
    let primary: URL
    let secondary: URL
    let manager: DefaultAgentsManager
    let fileListManager: GitFileListManager
    let conversationId: String
    let events: (stream: AsyncStream<AgentCLIKit.AgentEventEnvelope>, continuation: AsyncStream<AgentCLIKit.AgentEventEnvelope>.Continuation)

    var originalFiles: [String] { [primary, secondary].map { $0.appendingPathComponent("old.txt").path } }
    var replacementFiles: [String] { [primary, secondary].map { $0.appendingPathComponent("new.txt").path } }

    func loadFiles() async -> [String] {
        await ConversationView.makeFileCompletionLoader(
            fileListManager: fileListManager, workingDirectory: primary.path, additionalRoots: [secondary.path]
        )()
    }

    func bufferGeneration() async throws -> UUID {
        let generation = await manager.eventBuffers[conversationId]?.generation
        return try XCTUnwrap(generation)
    }

    func replaceFiles() throws {
        for path in originalFiles { try FileManager.default.removeItem(atPath: path) }
        for path in replacementFiles { try Data().write(to: URL(fileURLWithPath: path)) }
    }

    func status(index: Int, backgroundTasks: Int) -> AgentCLIKit.AgentRuntimeStatus {
        AgentCLIKit.AgentRuntimeStatus(
            conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId), providerId: .claude,
            generation: 1, state: .running, lastEventIndex: index, providerSessionId: nil,
            isTurnActive: false, liveBackgroundTaskCount: backgroundTasks
        )
    }

    func remove() {
        events.continuation.finish()
        try? FileManager.default.removeItem(at: root)
    }
}
