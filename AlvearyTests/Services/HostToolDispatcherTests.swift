import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
final class HostToolDispatcherTests: XCTestCase {
    func testRoutesCallToTheFeatureOwningTheToolName() async {
        let scheduling = StubHostToolFeature(featureID: "scheduling", hostToolNames: ["list_scheduled_tasks"])
        let threads = StubHostToolFeature(featureID: "threads", hostToolNames: ["list_threads", "create_thread"])
        let dispatcher = HostToolDispatcher(features: [scheduling, threads])

        let result = await dispatcher.handle(
            context: Self.context(),
            call: AgentCLIKit.AgentHostToolCall(name: "create_thread")
        )

        XCTAssertEqual(result.text, "threads handled create_thread")
        XCTAssertFalse(result.isError)
        XCTAssertEqual(threads.handledToolNames, ["create_thread"])
        XCTAssertTrue(scheduling.handledToolNames.isEmpty)
    }

    func testUnknownToolNameReportsUnavailableWithoutReachingAFeature() async {
        let scheduling = StubHostToolFeature(featureID: "scheduling", hostToolNames: ["list_scheduled_tasks"])
        let dispatcher = HostToolDispatcher(features: [scheduling])

        let result = await dispatcher.handle(
            context: Self.context(),
            call: AgentCLIKit.AgentHostToolCall(name: "delete_thread")
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, "This Alveary tool is not available.")
        XCTAssertTrue(scheduling.handledToolNames.isEmpty)
    }

    func testHandlingAdapterDispatchesTheSameWayAsHandle() async {
        let feature = StubHostToolFeature(featureID: "threads", hostToolNames: ["archive_thread"])
        let dispatcher = HostToolDispatcher(features: [feature])

        let result = await dispatcher.handling.handle(
            context: Self.context(),
            call: AgentCLIKit.AgentHostToolCall(name: "archive_thread")
        )

        XCTAssertEqual(result.text, "threads handled archive_thread")
    }

    /// Collision detection is checked through the pure helper because the initializer's
    /// `preconditionFailure` cannot be caught.
    func testDuplicateToolNameDetectionFindsNamesClaimedByTwoFeatures() {
        XCTAssertNil(HostToolDispatcher.duplicateToolName(in: [["a", "b"], ["c"]]))
        XCTAssertEqual(HostToolDispatcher.duplicateToolName(in: [["a", "b"], ["b"]]), "b")
        XCTAssertNil(HostToolDispatcher.duplicateToolName(in: []))
    }

    private static func context() -> AgentCLIKit.AgentHostToolCallContext {
        AgentCLIKit.AgentHostToolCallContext(
            conversationId: AgentCLIKit.AgentConversationID(rawValue: "conversation-1"),
            providerId: .codex,
            processToken: UUID(),
            requestId: "request-1"
        )
    }
}

@MainActor
private final class StubHostToolFeature: HostToolFeature {
    let featureID: String
    let hostToolNames: Set<String>
    private(set) var handledToolNames: [String] = []

    init(featureID: String, hostToolNames: Set<String>) {
        self.featureID = featureID
        self.hostToolNames = hostToolNames
    }

    func handle(
        context: AgentCLIKit.AgentHostToolCallContext,
        call: AgentCLIKit.AgentHostToolCall
    ) async -> AgentCLIKit.AgentHostToolResult {
        handledToolNames.append(call.name)
        return AgentCLIKit.AgentHostToolResult(text: "\(featureID) handled \(call.name)")
    }
}
