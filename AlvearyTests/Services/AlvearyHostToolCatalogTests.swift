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
        XCTAssertEqual(
            AlvearyHostToolCatalog.featureCatalogs.map(\.featureID),
            ["scheduling", "threads", "pull_requests"]
        )
    }

    /// The preamble is the first thing a provider reads, and it used to say the server only acted
    /// on Alveary — which made reaching for `gh` or a web search look like the right call for a
    /// GitHub question. It has to name the substitutes it is ruling out.
    func testThePreambleRulesOutTheToolsItActuallyCompetesWith() throws {
        let instructions = try XCTUnwrap(AlvearyHostToolCatalog.serverMetadata.instructions)

        XCTAssertTrue(instructions.contains("gh CLI"))
        XCTAssertTrue(instructions.contains("web search"))
        // The claim that broke it: the server does reach GitHub, for pull requests.
        XCTAssertFalse(AlvearyHostToolCatalog.instructionsPreamble.contains("act on Alveary itself"))
        XCTAssertTrue(AlvearyHostToolCatalog.instructionsPreamble.contains("GitHub pull requests"))
        // Still true of every tool, and the reason the carve-out above is safe.
        XCTAssertTrue(instructions.contains("never touch the user's code or files"))
    }

    /// A bare "list my pull requests" was landing on the threads feature's bookmark reader, which
    /// answers with an empty list as if it were the truth.
    func testTheThreadLinkListingDeflectsRequestsForTheUsersPullRequests() throws {
        let listLinked = try XCTUnwrap(
            AlvearyHostToolCatalog.tools.first { $0.name == ThreadHostToolCatalog.listPullRequestsToolName }
        )

        XCTAssertTrue(listLinked.description.contains("wrong tool"))
        XCTAssertTrue(listLinked.description.contains("list my pull requests"))
        XCTAssertTrue(listLinked.description.contains("what needs my review"))
    }

    /// Two features list pull requests from different sources, so each has to point at the other.
    /// Without it a model asked "what am I working on" reaches for whichever name it saw first and
    /// gets Alveary's hand-linked record instead of GitHub.
    func testThePullRequestListingToolsDisambiguateEachOther() throws {
        let listInvolved = try XCTUnwrap(
            AlvearyHostToolCatalog.tools.first { $0.name == PullRequestHostToolCatalog.listToolName }
        )
        let listLinked = try XCTUnwrap(
            AlvearyHostToolCatalog.tools.first { $0.name == ThreadHostToolCatalog.listPullRequestsToolName }
        )

        XCTAssertTrue(listInvolved.description.contains(listLinked.name))
        XCTAssertTrue(listLinked.description.contains(listInvolved.name))
        // Neither name may contain the other: the original `list_prs` read as the generic default
        // beside `list_linked_prs`, which is exactly how the wrong one got picked.
        XCTAssertFalse(listLinked.name.contains(listInvolved.name))
        XCTAssertFalse(listInvolved.name.contains(listLinked.name))

        // The listing covers pull requests the user did not open, so nothing may call them theirs.
        XCTAssertTrue(listInvolved.description.contains("not only the user's own pull requests"))

        let instructions = try XCTUnwrap(AlvearyHostToolCatalog.serverMetadata.instructions)
        XCTAssertTrue(instructions.contains(listInvolved.name))
        XCTAssertTrue(instructions.contains(listLinked.name))
    }

    /// The draft directions are one reversible pair, so each description names the other as its
    /// undo — without that the model describes either direction as final.
    func testTheDraftDirectionToolsNameEachOtherAsTheUndo() throws {
        let markReady = try XCTUnwrap(
            AlvearyHostToolCatalog.tools.first { $0.name == PullRequestHostToolCatalog.markReadyToolName }
        )
        let markDraft = try XCTUnwrap(
            AlvearyHostToolCatalog.tools.first { $0.name == PullRequestHostToolCatalog.markDraftToolName }
        )

        XCTAssertTrue(markReady.description.contains(markDraft.name))
        XCTAssertTrue(markDraft.description.contains(markReady.name))
    }

    /// No tool here opens a pull request, so two things have to say so: the fragment, whose blanket
    /// "never run gh yourself" would otherwise ban the only route to creating one, and `reopen_pr`,
    /// whose name is what an "open a pull request" ask reaches for.
    func testNothingClaimsToOpenANewPullRequest() throws {
        let reopen = try XCTUnwrap(
            AlvearyHostToolCatalog.tools.first { $0.name == PullRequestHostToolCatalog.reopenToolName }
        )

        XCTAssertTrue(reopen.description.contains("not how a pull request gets opened in the first place"))

        let instructions = try XCTUnwrap(AlvearyHostToolCatalog.serverMetadata.instructions)
        XCTAssertTrue(instructions.contains("None of these tools creates one"))
        XCTAssertTrue(instructions.contains("gh pr create"))
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
        XCTAssertTrue(instructions.contains("propose_pr_review"))
    }

    /// Guards the one structural risk of splitting static catalogs from DI-built handlers:
    /// a tool the server advertises that no feature actually answers.
    func testEveryAdvertisedToolIsRoutableAndHandled() async throws {
        let scheduling = try ScheduledTaskHostToolFixture.project()
        let threads = try ThreadHostToolFixture()
        let pullRequests = try PullRequestHostToolFixture()
        let dispatcher = HostToolDispatcher(
            features: [scheduling.service, threads.service, pullRequests.service]
        )

        XCTAssertEqual(
            scheduling.service.hostToolNames
                .union(threads.service.hostToolNames)
                .union(pullRequests.service.hostToolNames),
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
            XCTAssertNotEqual(
                result.text,
                PullRequestHostToolServiceError.unsupportedTool.localizedDescription,
                "\(tool.name) reached its feature but fell through to the unsupported branch"
            )
        }
    }
}
