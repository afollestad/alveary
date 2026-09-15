import AgentCLIKit
import XCTest

@testable import Alveary

final class PullRequestReviewTeamResolverTests: XCTestCase {
    func testResolvesLeadFirstAndFreezesConcreteLaunchSettings() throws {
        var settings = AppSettings()
        settings.defaultHarness = "claude"
        settings.defaultModel = AppSettings.defaultModelValue
        settings.effort = "high"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", harnessID: "codex", model: "gpt-5.5", effort: "medium")
        ]

        let workers = try PullRequestReviewTeamResolver.resolve(
            settings: settings,
            harnessStatuses: Self.readyStatuses
        )

        XCTAssertEqual(workers.map(\.id), ["lead", "peer-1"])
        XCTAssertEqual(
            workers[0],
            ReviewWorkerConfiguration(
                id: "lead",
                harnessID: "claude",
                modelOptionID: "sonnet",
                launchModel: "sonnet",
                effort: "high",
                executablePath: "/usr/local/bin/claude"
            )
        )
        XCTAssertEqual(workers[1].launchModel, "gpt-5.5")
    }

    func testRejectsAStaleModelWithoutFallingBack() {
        var settings = AppSettings()
        settings.pullRequestReviewModel = "retired-model"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", harnessID: "codex", model: "gpt-5.5", effort: "medium")
        ]

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, harnessStatuses: Self.readyStatuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .modelUnavailable(memberID: "lead", memberName: "Lead", harnessID: "claude", model: "retired-model")
            )
        }
    }

    func testInheritedUnavailableHarnessDoesNotFallBackToAnotherReadyHarness() {
        var settings = AppSettings()
        settings.defaultHarness = "claude"
        settings.defaultModel = "sonnet"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", harnessID: "codex", model: "gpt-5.4-mini", effort: "medium")
        ]
        var statuses = Self.readyStatuses
        statuses[.claude] = nil

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(
                settings: settings,
                harnessStatuses: statuses,
                harnessOrdering: ["codex", "claude"]
            )
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .harnessUnavailable(memberID: "lead", memberName: "Lead", harnessID: "claude")
            )
        }
    }

    func testInheritedStaleModelDoesNotFallBackToTheHarnessDefault() {
        var settings = AppSettings()
        settings.defaultModel = "retired-model"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", harnessID: "codex", model: "gpt-5.5", effort: "medium")
        ]

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, harnessStatuses: Self.readyStatuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .modelUnavailable(memberID: "lead", memberName: "Lead", harnessID: "claude", model: "retired-model")
            )
        }
    }

    func testRejectsAHarnessDefaultWithNoConcreteLaunchModel() {
        var settings = AppSettings()
        settings.defaultHarness = "codex"
        settings.defaultModel = AppSettings.defaultModelValue
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", harnessID: "claude", model: "sonnet", effort: "high")
        ]
        var statuses = Self.readyStatuses
        statuses[.codex] = Self.status(
            harnessID: .codex,
            options: AgentDefaultModelOptions.harnessDefault(for: .codex)
        )

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, harnessStatuses: statuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .modelUnavailable(
                    memberID: "lead",
                    memberName: "Lead",
                    harnessID: "codex",
                    model: AppSettings.defaultModelValue
                )
            )
        }
    }

    func testRejectsDuplicateResolvedHarnessAndModelPairs() {
        var settings = AppSettings()
        settings.defaultModel = "sonnet"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", harnessID: "claude", model: "sonnet", effort: "medium")
        ]

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, harnessStatuses: Self.readyStatuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .duplicateModel(
                    firstMemberID: "lead",
                    firstMemberName: "Lead",
                    secondMemberID: "peer-1",
                    secondMemberName: "Reviewer 2"
                )
            )
        }
    }

    func testRejectsAnUnavailablePinnedHarness() {
        var settings = AppSettings()
        settings.defaultModel = "sonnet"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", harnessID: "codex", model: "gpt-5.5", effort: "medium")
        ]
        var statuses = Self.readyStatuses
        statuses[.codex] = Self.status(harnessID: .codex, installation: .missing, options: [])

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, harnessStatuses: statuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .harnessUnavailable(memberID: "peer-1", memberName: "Reviewer 2", harnessID: "codex")
            )
            XCTAssertEqual(error.localizedDescription, "Reviewer 2 uses codex, which is not ready.")
        }
    }

    func testExplicitLeadHarnessDoesNotFallBackWhenUnavailable() {
        var settings = AppSettings()
        settings.pullRequestReviewHarness = "codex"
        settings.pullRequestReviewModel = "gpt-5.5"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", harnessID: "claude", model: "sonnet", effort: "high")
        ]
        var statuses = Self.readyStatuses
        statuses[.codex] = Self.status(harnessID: .codex, installation: .missing, options: [])

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, harnessStatuses: statuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .harnessUnavailable(memberID: "lead", memberName: "Lead", harnessID: "codex")
            )
        }
    }

    func testRejectsUnsupportedEffortAndTooFewMembers() {
        var settings = AppSettings()
        settings.defaultModel = "sonnet"

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, harnessStatuses: Self.readyStatuses)
        ) { error in
            XCTAssertEqual(error as? PullRequestReviewTeamResolutionError, .invalidTeamSize(1))
        }

        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", harnessID: "codex", model: "gpt-5.4-mini", effort: "xhigh")
        ]
        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, harnessStatuses: Self.readyStatuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .effortUnavailable(memberID: "peer-1", memberName: "Reviewer 2", effort: "xhigh")
            )
        }
    }

    func testRejectsAModelWithoutDeclaredEffortSupport() {
        var settings = AppSettings()
        settings.defaultModel = "sonnet"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", harnessID: "codex", model: "gpt-5.5", effort: "medium")
        ]
        var statuses = Self.readyStatuses
        statuses[.codex] = Self.status(
            harnessID: .codex,
            options: [
                AgentModelOption(
                    harnessId: .codex,
                    id: "gpt-5.5",
                    model: "gpt-5.5",
                    label: "GPT-5.5"
                )
            ]
        )

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, harnessStatuses: statuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .effortUnavailable(memberID: "peer-1", memberName: "Reviewer 2", effort: "medium")
            )
        }
    }
}

private extension PullRequestReviewTeamResolverTests {
    static let readyStatuses: [AgentHarnessID: AgentHarnessStatus] = [
        .claude: status(harnessID: .claude, options: AgentModelOptionTestFixtures.claudeModelOptions),
        .codex: status(harnessID: .codex, options: AgentModelOptionTestFixtures.codexModelOptions)
    ]

    static func status(
        harnessID: AgentHarnessID,
        installation: AgentHarnessInstallationState = .installed,
        options: [AgentModelOption]
    ) -> AgentHarnessStatus {
        AgentHarnessStatus(
            harnessId: harnessID,
            definition: harnessID == .claude ? ClaudeHarnessDefinition.definition : CodexHarnessDefinition.definition,
            installation: installation,
            availability: AgentHarnessAvailability(
                harnessId: harnessID,
                executablePath: installation == .installed ? "/usr/local/bin/\(harnessID.rawValue)" : nil
            ),
            setup: .ready,
            modelOptions: options
        )
    }
}
