import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class DiffCreatePullRequestModalModelTests: XCTestCase {
    private let createdIdentifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 41)

    // MARK: - Load

    func testLoadOnBaseBranchDefaultsToANewBranch() async throws {
        let harness = try Harness(currentBranch: "main")

        await harness.model.load()

        XCTAssertEqual(harness.model.branchSelection, .new)
        XCTAssertFalse(harness.model.isBaseBranchSelectable)
    }

    func testLoadOffBaseDefaultsToTheCurrentBranch() async throws {
        let harness = try Harness(currentBranch: "alveary/feature")

        await harness.model.load()

        XCTAssertEqual(harness.model.branchSelection, .current)
        XCTAssertTrue(harness.model.isCurrentBranchSelectable)
    }

    // MARK: - Preflight

    func testNoCommitsAheadBlocksSubmission() async throws {
        let harness = try Harness(currentBranch: "alveary/feature", commitsAhead: 0)

        await harness.model.load()

        XCTAssertNotNil(harness.model.preflightMessage)
        XCTAssertTrue(harness.model.createButtonDisabled)
    }

    func testEmptyNewBranchNameBlocksSubmission() async throws {
        let harness = try Harness(currentBranch: "main", commitsAhead: 2)
        await harness.model.load()
        harness.model.newBranchName = "   "

        XCTAssertEqual(harness.model.preflightMessage, "Enter a branch name.")
    }

    // MARK: - Submit

    /// Off base with typed content: no branch is created, the checkout pushes,
    /// and the create call carries the checkout as head.
    func testSubmitFromExistingBranchPushesThenCreates() async throws {
        let harness = try Harness(currentBranch: "alveary/feature", commitsAhead: 2)
        harness.service.createPullRequestResult = .success(createdIdentifier)
        await harness.model.load()
        harness.model.title = "Add caching"
        harness.model.descriptionDraft.replaceText("Caches responses.")

        let identifier = await harness.model.submit()

        XCTAssertEqual(identifier, createdIdentifier)
        XCTAssertNil(harness.model.errorMessage)
        let checkouts = await harness.gitService.checkoutNewBranchCalls()
        XCTAssertTrue(checkouts.isEmpty)
        let pushes = await harness.gitService.pushCalls()
        XCTAssertEqual(pushes.map(\.remoteName), ["origin"])
        XCTAssertEqual(harness.service.createdPullRequests, [
            StubPullRequestsService.CreatedPullRequest(
                directory: "/tmp/alveary-project",
                baseBranch: "main",
                headBranch: "alveary/feature",
                title: "Add caching",
                body: "Caches responses."
            )
        ])
        XCTAssertTrue(harness.didRefreshAfterMutation)
    }

    /// On base: the prefixed branch is created first, and it becomes the head.
    func testSubmitOnBaseCreatesTheNewBranchFirst() async throws {
        let harness = try Harness(currentBranch: "main", commitsAhead: 1)
        harness.service.createPullRequestResult = .success(createdIdentifier)
        await harness.model.load()
        harness.model.title = "Add caching"
        harness.model.descriptionDraft.replaceText("Caches responses.")

        let identifier = await harness.model.submit()

        XCTAssertEqual(identifier, createdIdentifier)
        let checkouts = await harness.gitService.checkoutNewBranchCalls()
        XCTAssertEqual(checkouts.map(\.branchName), ["alveary/test-thread"])
        XCTAssertEqual(harness.service.createdPullRequests.map(\.headBranch), ["alveary/test-thread"])
    }

    /// Blank title and description generate once, fill both fields, and submit
    /// the generated values.
    func testBlankFieldsGenerateTitleAndDescription() async throws {
        let harness = try Harness(
            currentBranch: "alveary/feature",
            commitsAhead: 1,
            generatedText: "# Add response caching\n\nCaches GitHub responses for an hour."
        )
        harness.service.createPullRequestResult = .success(createdIdentifier)
        await harness.model.load()

        let identifier = await harness.model.submit()

        XCTAssertEqual(identifier, createdIdentifier)
        XCTAssertEqual(harness.generationPrompts.count, 1)
        XCTAssertEqual(harness.model.title, "Add response caching")
        XCTAssertEqual(harness.model.descriptionDraft.markdown, "Caches GitHub responses for an hour.")
        XCTAssertEqual(harness.service.createdPullRequests.map(\.title), ["Add response caching"])
        XCTAssertEqual(harness.service.createdPullRequests.map(\.body), ["Caches GitHub responses for an hour."])
    }

    func testTypedContentSkipsGeneration() async throws {
        let harness = try Harness(currentBranch: "alveary/feature", commitsAhead: 1)
        harness.service.createPullRequestResult = .success(createdIdentifier)
        await harness.model.load()
        harness.model.title = "Typed title"
        harness.model.descriptionDraft.replaceText("Typed body.")

        _ = await harness.model.submit()

        XCTAssertTrue(harness.generationPrompts.isEmpty)
    }

    /// A blank title with a typed body generates, keeps the typed body, and
    /// takes only the title from the response.
    func testBlankTitleAloneGeneratesButKeepsTheTypedBody() async throws {
        let harness = try Harness(
            currentBranch: "alveary/feature",
            commitsAhead: 1,
            generatedText: "Generated title\n\nGenerated body."
        )
        harness.service.createPullRequestResult = .success(createdIdentifier)
        await harness.model.load()
        harness.model.descriptionDraft.replaceText("Typed body.")

        _ = await harness.model.submit()

        XCTAssertEqual(harness.model.title, "Generated title")
        XCTAssertEqual(harness.service.createdPullRequests.map(\.body), ["Typed body."])
    }

    // MARK: - Failures

    func testPushFailureNamesTheStepAndStops() async throws {
        let harness = try Harness(
            currentBranch: "alveary/feature",
            commitsAhead: 1,
            pushResults: [.failure(ModalTestError("remote rejected"))]
        )
        await harness.model.load()
        harness.model.title = "Title"
        harness.model.descriptionDraft.replaceText("Body.")

        let identifier = await harness.model.submit()

        XCTAssertNil(identifier)
        XCTAssertEqual(harness.model.errorMessage, "Push failed: remote rejected")
        XCTAssertEqual(harness.model.phase, .idle)
        XCTAssertTrue(harness.service.createdPullRequests.isEmpty)
    }

    /// A create failure after the push says the branch survived, so the user
    /// knows the repository was mutated.
    func testCreateFailureAfterPushSaysTheBranchWasPushed() async throws {
        let harness = try Harness(currentBranch: "alveary/feature", commitsAhead: 1)
        harness.service.createPullRequestResult = .failure(.requestFailed(statusCode: 422))
        await harness.model.load()
        harness.model.title = "Title"
        harness.model.descriptionDraft.replaceText("Body.")

        let identifier = await harness.model.submit()

        XCTAssertNil(identifier)
        XCTAssertEqual(
            harness.model.errorMessage,
            "The branch was pushed, but creating the pull request failed: GitHub request failed with HTTP 422"
        )
    }

    // MARK: - Harness

    @MainActor
    private final class Harness {
        let gitService: DiffGitCommitModalMockGitService
        let service: StubPullRequestsService
        let model: DiffCreatePullRequestModalModel
        private(set) var generationPrompts: [String] = []
        private(set) var didRefreshAfterMutation = false

        init(
            currentBranch: String,
            commitsAhead: Int = 1,
            pushResults: [Result<Void, Error>] = [.success(())],
            generatedText: String = "Generated title\n\nGenerated body."
        ) throws {
            gitService = Self.makeGitService(
                currentBranch: currentBranch,
                commitsAhead: commitsAhead,
                pushResults: pushResults
            )
            service = StubPullRequestsService()

            var recordPrompt: ((String) -> Void)?
            var recordRefresh: (() -> Void)?
            model = DiffCreatePullRequestModalModel(
                context: DiffCreatePullRequestModalContext(
                    directory: "/tmp/alveary-project",
                    targetName: "Test Thread",
                    baseBranch: "main",
                    remoteName: "origin",
                    owner: .thread(try Self.makeThreadIdentifier())
                ),
                gitService: gitService,
                pullRequestsService: service,
                settingsService: InMemorySettingsService(),
                generateText: { prompt in
                    recordPrompt?(prompt)
                    return generatedText
                },
                refreshAfterMutation: {
                    recordRefresh?()
                }
            )
            recordPrompt = { [weak self] prompt in
                self?.generationPrompts.append(prompt)
            }
            recordRefresh = { [weak self] in
                self?.didRefreshAfterMutation = true
            }
        }

        private static func makeGitService(
            currentBranch: String,
            commitsAhead: Int,
            pushResults: [Result<Void, Error>]
        ) -> DiffGitCommitModalMockGitService {
            DiffGitCommitModalMockGitService(
                statusResults: [],
                pushResults: pushResults,
                currentBranchResult: .success(currentBranch),
                commitsAheadResult: .success(commitsAhead),
                commitsAheadDetailsResult: .success([
                    CommitInfo(
                        hash: "abc123",
                        message: "Add caching layer",
                        author: "Tester",
                        date: Date(timeIntervalSince1970: 100)
                    )
                ]),
                diffForCommitResults: ["abc123": "+ cached line"]
            )
        }

        private static func makeThreadIdentifier() throws -> PersistentIdentifier {
            let container = try ModelContainer(
                for: Project.self,
                AgentThread.self,
                Conversation.self,
                ConversationEventRecord.self,
                ScheduledTask.self,
                ScheduledTaskRun.self,
                ScheduledTaskProposal.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = ModelContext(container)
            let thread = AgentThread(name: "Thread")
            context.insert(thread)
            try context.save()
            return thread.persistentModelID
        }
    }
}
