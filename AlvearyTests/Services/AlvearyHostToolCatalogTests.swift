import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class AlvearyHostToolCatalogTests: XCTestCase {
    func testServerIdentityIsOwnedInOnePlace() {
        XCTAssertEqual(AlvearyHostToolCatalog.serverName, "alveary_host")
        XCTAssertEqual(AlvearyHostToolCatalog.serverMetadata.name, "alveary_host")
        XCTAssertEqual(
            AlvearyHostToolCatalog.qualifiedToolName("list_threads"),
            "mcp__alveary_host__list_threads"
        )
        // The transcript layer must resolve names through the same owner.
        XCTAssertEqual(
            HostToolTranscriptCatalog.toolName("list_threads"),
            AlvearyHostToolCatalog.qualifiedToolName("list_threads")
        )
    }

    func testNameMatchingAcceptsBothProviderShapes() {
        XCTAssertTrue(AlvearyHostToolCatalog.matches(reportedName: "list_threads", hostToolName: "list_threads"))
        XCTAssertTrue(
            AlvearyHostToolCatalog.matches(
                reportedName: "mcp__alveary_host__list_threads",
                hostToolName: "list_threads"
            )
        )
        XCTAssertFalse(AlvearyHostToolCatalog.matches(reportedName: "list_thread", hostToolName: "list_threads"))
        XCTAssertFalse(
            AlvearyHostToolCatalog.matches(reportedName: "mcp__other__list_threads", hostToolName: "list_threads")
        )
    }

    func testToolsAreTheEnrolledFeatureCatalogsWithoutDuplicateNames() {
        let toolNames = AlvearyHostToolCatalog.tools.map(\.name)
        XCTAssertEqual(toolNames, AlvearyHostToolCatalog.featureCatalogs.flatMap(\.toolNames))
        XCTAssertEqual(Set(toolNames).count, toolNames.count)
        XCTAssertEqual(AlvearyHostToolCatalog.featureCatalogs.map(\.featureID), ["scheduling", "threads"])
    }

    func testInstructionsComposeTheNeutralPreambleWithEachFeatureFragment() throws {
        let instructions = try XCTUnwrap(AlvearyHostToolCatalog.serverMetadata.instructions)

        XCTAssertTrue(instructions.hasPrefix(AlvearyHostToolCatalog.instructionsPreamble))
        // The preamble carries the rules that apply to every feature, so a feature fragment
        // does not have to repeat them.
        XCTAssertTrue(instructions.contains("only when the user explicitly asks"))
        XCTAssertTrue(instructions.contains("never invent a tool this server does not list"))
        for fragment in AlvearyHostToolCatalog.featureCatalogs.map(\.instructionsFragment) {
            XCTAssertTrue(instructions.contains(fragment))
        }
        XCTAssertTrue(instructions.contains("propose_scheduled_task"))
        XCTAssertTrue(instructions.contains("create_thread"))
    }

    /// Guards the one structural risk of splitting static catalogs from DI-built handlers:
    /// a tool the server advertises that no feature actually answers.
    func testEveryAdvertisedToolIsRoutableAndHandled() async throws {
        let scheduling = try ScheduledTaskHostToolFixture.project()
        let threads = try ThreadHostToolFixture()
        let dispatcher = HostToolDispatcher(features: [scheduling.service, threads.service])

        XCTAssertEqual(
            scheduling.service.hostToolNames.union(threads.service.hostToolNames),
            Set(AlvearyHostToolCatalog.tools.map(\.name))
        )

        for tool in AlvearyHostToolCatalog.tools {
            let result = await dispatcher.handle(
                context: scheduling.agentContext(),
                call: AgentCLIKit.AgentHostToolCall(name: tool.name)
            )
            XCTAssertNotEqual(
                result.text,
                "This Alveary tool is not available.",
                "\(tool.name) is advertised but no feature handles it"
            )
            XCTAssertNotEqual(
                result.text,
                ScheduledTaskHostToolServiceError.unsupportedTool.localizedDescription,
                "\(tool.name) reached its feature but fell through to the unsupported branch"
            )
            XCTAssertNotEqual(
                result.text,
                ThreadHostToolServiceError.unsupportedTool.localizedDescription,
                "\(tool.name) reached its feature but fell through to the unsupported branch"
            )
        }
    }
}
