import AgentCLIKit
import XCTest

@testable import Alveary

final class PullRequestReviewTeamResolverTests: XCTestCase {
    func testResolvesLeadFirstAndFreezesConcreteLaunchSettings() throws {
        var settings = AppSettings()
        settings.defaultProvider = "claude"
        settings.defaultModel = AppSettings.defaultModelValue
        settings.effort = "high"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", providerID: "codex", model: "gpt-5.5", effort: "medium")
        ]

        let workers = try PullRequestReviewTeamResolver.resolve(
            settings: settings,
            providerStatuses: Self.readyStatuses
        )

        XCTAssertEqual(workers.map(\.id), ["lead", "peer-1"])
        XCTAssertEqual(
            workers[0],
            ReviewWorkerConfiguration(
                id: "lead",
                providerID: "claude",
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
            PullRequestReviewPeer(id: "peer-1", providerID: "codex", model: "gpt-5.5", effort: "medium")
        ]

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, providerStatuses: Self.readyStatuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .modelUnavailable(memberID: "lead", memberName: "Lead", providerID: "claude", model: "retired-model")
            )
        }
    }

    func testInheritedUnavailableProviderDoesNotFallBackToAnotherReadyProvider() {
        var settings = AppSettings()
        settings.defaultProvider = "claude"
        settings.defaultModel = "sonnet"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", providerID: "codex", model: "gpt-5.4-mini", effort: "medium")
        ]
        var statuses = Self.readyStatuses
        statuses[.claude] = nil

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(
                settings: settings,
                providerStatuses: statuses,
                providerOrdering: ["codex", "claude"]
            )
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .providerUnavailable(memberID: "lead", memberName: "Lead", providerID: "claude")
            )
        }
    }

    func testInheritedStaleModelDoesNotFallBackToTheProviderDefault() {
        var settings = AppSettings()
        settings.defaultModel = "retired-model"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", providerID: "codex", model: "gpt-5.5", effort: "medium")
        ]

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, providerStatuses: Self.readyStatuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .modelUnavailable(memberID: "lead", memberName: "Lead", providerID: "claude", model: "retired-model")
            )
        }
    }

    func testRejectsAProviderDefaultWithNoConcreteLaunchModel() {
        var settings = AppSettings()
        settings.defaultProvider = "codex"
        settings.defaultModel = AppSettings.defaultModelValue
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", providerID: "claude", model: "sonnet", effort: "high")
        ]
        var statuses = Self.readyStatuses
        statuses[.codex] = Self.status(
            providerID: .codex,
            options: AgentDefaultModelOptions.providerDefault(for: .codex)
        )

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, providerStatuses: statuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .modelUnavailable(
                    memberID: "lead",
                    memberName: "Lead",
                    providerID: "codex",
                    model: AppSettings.defaultModelValue
                )
            )
        }
    }

    func testRejectsDuplicateResolvedProviderAndModelPairs() {
        var settings = AppSettings()
        settings.defaultModel = "sonnet"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", providerID: "claude", model: "sonnet", effort: "medium")
        ]

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, providerStatuses: Self.readyStatuses)
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

    func testRejectsAnUnavailablePinnedProvider() {
        var settings = AppSettings()
        settings.defaultModel = "sonnet"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", providerID: "codex", model: "gpt-5.5", effort: "medium")
        ]
        var statuses = Self.readyStatuses
        statuses[.codex] = Self.status(providerID: .codex, installation: .missing, options: [])

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, providerStatuses: statuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .providerUnavailable(memberID: "peer-1", memberName: "Reviewer 2", providerID: "codex")
            )
            XCTAssertEqual(error.localizedDescription, "Reviewer 2 uses codex, which is not ready.")
        }
    }

    func testExplicitLeadProviderDoesNotFallBackWhenUnavailable() {
        var settings = AppSettings()
        settings.pullRequestReviewProvider = "codex"
        settings.pullRequestReviewModel = "gpt-5.5"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", providerID: "claude", model: "sonnet", effort: "high")
        ]
        var statuses = Self.readyStatuses
        statuses[.codex] = Self.status(providerID: .codex, installation: .missing, options: [])

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, providerStatuses: statuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .providerUnavailable(memberID: "lead", memberName: "Lead", providerID: "codex")
            )
        }
    }

    func testRejectsUnsupportedEffortAndTooFewMembers() {
        var settings = AppSettings()
        settings.defaultModel = "sonnet"

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, providerStatuses: Self.readyStatuses)
        ) { error in
            XCTAssertEqual(error as? PullRequestReviewTeamResolutionError, .invalidTeamSize(1))
        }

        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", providerID: "codex", model: "gpt-5.4-mini", effort: "xhigh")
        ]
        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, providerStatuses: Self.readyStatuses)
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
            PullRequestReviewPeer(id: "peer-1", providerID: "codex", model: "gpt-5.5", effort: "medium")
        ]
        var statuses = Self.readyStatuses
        statuses[.codex] = Self.status(
            providerID: .codex,
            options: [
                AgentModelOption(
                    providerId: .codex,
                    id: "gpt-5.5",
                    model: "gpt-5.5",
                    label: "GPT-5.5"
                )
            ]
        )

        XCTAssertThrowsError(
            try PullRequestReviewTeamResolver.resolve(settings: settings, providerStatuses: statuses)
        ) { error in
            XCTAssertEqual(
                error as? PullRequestReviewTeamResolutionError,
                .effortUnavailable(memberID: "peer-1", memberName: "Reviewer 2", effort: "medium")
            )
        }
    }
}

private extension PullRequestReviewTeamResolverTests {
    static let readyStatuses: [AgentProviderID: AgentProviderStatus] = [
        .claude: status(providerID: .claude, options: AgentModelOptionTestFixtures.claudeModelOptions),
        .codex: status(providerID: .codex, options: AgentModelOptionTestFixtures.codexModelOptions)
    ]

    static func status(
        providerID: AgentProviderID,
        installation: AgentProviderInstallationState = .installed,
        options: [AgentModelOption]
    ) -> AgentProviderStatus {
        AgentProviderStatus(
            providerId: providerID,
            definition: providerID == .claude ? ClaudeProviderDefinition.definition : CodexProviderDefinition.definition,
            installation: installation,
            availability: AgentProviderAvailability(
                providerId: providerID,
                executablePath: installation == .installed ? "/usr/local/bin/\(providerID.rawValue)" : nil
            ),
            setup: .ready,
            modelOptions: options
        )
    }
}
