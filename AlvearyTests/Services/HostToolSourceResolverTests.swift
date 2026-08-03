import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class HostToolSourceResolverTests: XCTestCase {
    func testResolvesTheCallingConversationAndItsThread() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()

        let source = try HostToolSourceResolver.resolveSource(
            context: fixture.agentContext(),
            in: fixture.modelContext
        )

        XCTAssertEqual(source.conversation.id, fixture.conversation.id)
        XCTAssertEqual(source.thread.persistentModelID, fixture.thread.persistentModelID)
    }

    func testRejectsAConversationAlvearyCannotResolve() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let context = AgentCLIKit.AgentHostToolCallContext(
            conversationId: AgentCLIKit.AgentConversationID(rawValue: "missing-conversation"),
            providerId: .codex,
            processToken: UUID(),
            requestId: "request-1"
        )

        XCTAssertThrowsError(
            try HostToolSourceResolver.resolveSource(context: context, in: fixture.modelContext)
        ) { error in
            XCTAssertEqual(error as? HostToolSourceError, .sourceConversationUnavailable)
        }
    }

    func testRejectsDraftAndArchivedThreads() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()

        fixture.thread.isDraft = true
        try fixture.modelContext.save()
        XCTAssertThrowsError(
            try HostToolSourceResolver.resolveSource(context: fixture.agentContext(), in: fixture.modelContext)
        ) { error in
            XCTAssertEqual(error as? HostToolSourceError, .sourceConversationUnavailable)
        }

        fixture.thread.isDraft = false
        fixture.thread.archivedAt = Date(timeIntervalSince1970: 10)
        try fixture.modelContext.save()
        XCTAssertThrowsError(
            try HostToolSourceResolver.resolveSource(context: fixture.agentContext(), in: fixture.modelContext)
        ) { error in
            XCTAssertEqual(error as? HostToolSourceError, .sourceConversationUnavailable)
        }
    }

    func testRejectsAProviderThatDisagreesWithTheStoredOne() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()

        XCTAssertThrowsError(
            try HostToolSourceResolver.resolveSource(
                context: fixture.agentContext(providerID: .claude),
                in: fixture.modelContext
            )
        ) { error in
            XCTAssertEqual(error as? HostToolSourceError, .sourceProviderMismatch)
        }
    }
}
