import XCTest

@testable import Alveary

// Notification subscriptions: the batched lookup the ignore sync reads, and the
// `updateSubscription` mutation ignoring and un-ignoring write.
extension GitHubPullRequestsServiceTests {
    func testSubscriptionLookupAliasesEachIdentifierThroughVariables() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(
            stdout: """
            {"data":{"rateLimit":{"cost":1},
              "pr0":{"pullRequest":\(subscriptionNodeJSON(nameWithOwner: "octo/alpha", number: 7, state: "OPEN", subscription: "UNSUBSCRIBED"))},
              "pr1":null},
             "errors":[{"type":"FORBIDDEN","path":["pr1"],"message":"Resource protected by organization SAML enforcement."}]}
            """,
            exitCode: 1
        )))
        let service = makeGitHubPullRequestsService(shell: shell)
        let alpha = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
        let beta = PullRequestIdentifier(owner: "saml", repo: "beta", number: 9)

        let snapshots = try await service.fetchSubscriptionStates(for: [alpha, beta])

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        let query = try XCTUnwrap(invocation.args.first { $0.hasPrefix("query=") })
        XCTAssertTrue(query.contains("pr1: repository(owner: $owner1, name: $name1)"))
        XCTAssertTrue(query.contains("viewerSubscription"))
        XCTAssertFalse(query.contains("octo"), "Identifiers travel as variables, never spliced into the document")
        XCTAssertTrue(invocation.args.contains("owner1=saml"))
        XCTAssertTrue(invocation.args.contains("name1=beta"))
        XCTAssertEqual(invocation.args[try XCTUnwrap(invocation.args.firstIndex(of: "number1=9")) - 1], "-F")

        // The SAML-nulled alias is absent rather than thrown.
        XCTAssertEqual(Array(snapshots.keys), [alpha])
        let snapshot = try XCTUnwrap(snapshots[alpha])
        XCTAssertEqual(snapshot.nodeID, "PR_octo/alpha_7")
        XCTAssertEqual(snapshot.subscription, .unsubscribed)
        XCTAssertTrue(snapshot.viewerCanSubscribe)
        XCTAssertEqual(snapshot.summary.status, .open)
        XCTAssertEqual(snapshot.summary.title, "Row 7")
        XCTAssertEqual(snapshot.summary.additions, 4)
    }

    func testSubscriptionLookupKeysResultsByRequestedIdentifier() async throws {
        let shell = MockShellRunner()
        let node = subscriptionNodeJSON(nameWithOwner: "octo/renamed", number: 7, state: "MERGED", subscription: "SUBSCRIBED")
        await shell.enqueue(.success(pullRequestsShellResult(stdout: """
        {"data":{"pr0":{"pullRequest":\(node)}}}
        """)))
        let service = makeGitHubPullRequestsService(shell: shell)
        let requested = PullRequestIdentifier(owner: "Octo", repo: "Alpha", number: 7)

        let snapshots = try await service.fetchSubscriptionStates(for: [requested])

        let snapshot = try XCTUnwrap(snapshots[requested])
        XCTAssertEqual(snapshot.summary.id, PullRequestIdentifier(owner: "octo", repo: "renamed", number: 7))
        XCTAssertEqual(snapshot.summary.status, .merged)
        XCTAssertEqual(snapshot.subscription, .subscribed)
    }

    func testSubscriptionLookupChunksLongListsIntoSequentialRequests() async throws {
        let shell = makeUniformShellRunner(pullRequestsShellResult(stdout: #"{"data":{}}"#))
        let service = makeGitHubPullRequestsService(shell: shell)
        let ids = (1...51).map { PullRequestIdentifier(owner: "octo", repo: "alpha", number: $0) }

        let snapshots = try await service.fetchSubscriptionStates(for: ids)

        XCTAssertTrue(snapshots.isEmpty)
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 2)
        XCTAssertTrue(invocations[0].args.contains("number49=50"))
        XCTAssertFalse(invocations[0].args.contains("number50=51"))
        XCTAssertTrue(invocations[1].args.contains("number0=51"))
    }

    func testSubscriptionLookupSkipsTheNetworkForNoIdentifiers() async throws {
        let shell = MockShellRunner()
        let service = makeGitHubPullRequestsService(shell: shell)

        let snapshots = try await service.fetchSubscriptionStates(for: [])

        XCTAssertTrue(snapshots.isEmpty)
        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    func testUpdateSubscriptionSendsMutationAndReturnsState() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: """
        {"data":{"updateSubscription":{"subscribable":{"viewerSubscription":"UNSUBSCRIBED"}}}}
        """)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let state = try await service.updatePullRequestSubscription(nodeID: "PR_41", subscribed: false)

        XCTAssertEqual(state, .unsubscribed)
        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocation.standardInput, .nullDevice)
        XCTAssertTrue(invocation.args.contains { $0.contains("updateSubscription") })
        XCTAssertTrue(invocation.args.contains("subscribableId=PR_41"))
        XCTAssertTrue(invocation.args.contains("state=UNSUBSCRIBED"))
    }

    func testResubscribeSendsSubscribedState() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: """
        {"data":{"updateSubscription":{"subscribable":{"viewerSubscription":"SUBSCRIBED"}}}}
        """)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let state = try await service.updatePullRequestSubscription(nodeID: "PR_41", subscribed: true)

        XCTAssertEqual(state, .subscribed)
        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertTrue(invocation.args.contains("state=SUBSCRIBED"))
    }

    /// The real response for a token without `notifications`: GitHub names the cause in the
    /// error's `type`, with no `data` and no HTTP status.
    func testMissingNotificationsScopeIsInsufficientScopes() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(
            stdout: #"{"errors":[{"type":"INSUFFICIENT_SCOPES","message":"\#(Self.insufficientScopesMessage)"}]}"#,
            stderr: "gh: \(Self.insufficientScopesMessage)",
            exitCode: 1
        )))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.insufficientScopes) {
            _ = try await service.updatePullRequestSubscription(nodeID: "PR_41", subscribed: false)
        }
    }

    func testInsufficientScopesIsClassifiedFromStandardErrorAlone() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(
            stderr: "gh: \(Self.insufficientScopesMessage)",
            exitCode: 1
        )))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.insufficientScopes) {
            _ = try await service.updatePullRequestSubscription(nodeID: "PR_41", subscribed: false)
        }
    }

    func testUpdateSubscriptionDoesNotRetryTransientFailures() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Bad Gateway (HTTP 502)", exitCode: 1)))
        await shell.enqueue(.success(pullRequestsShellResult(stdout: """
        {"data":{"updateSubscription":{"subscribable":{"viewerSubscription":"UNSUBSCRIBED"}}}}
        """)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 502)) {
            _ = try await service.updatePullRequestSubscription(nodeID: "PR_41", subscribed: false)
        }
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
    }

    private static let insufficientScopesMessage = "Your token has not been granted the required scopes to execute this query. "
        + "The 'updateSubscription' field requires one of the following scopes: ['notifications'], "
        + "but your token has only been granted the: ['gist', 'read:org', 'repo', 'workflow'] scopes."

    private func subscriptionNodeJSON(nameWithOwner: String, number: Int, state: String, subscription: String) -> String {
        """
        {"id":"PR_\(nameWithOwner)_\(number)","number":\(number),"title":"Row \(number)",
         "url":"https://github.com/\(nameWithOwner)/pull/\(number)","state":"\(state)","isDraft":false,
         "author":{"login":"octocat","avatarUrl":null},"headRefName":"feature","baseRefName":"main",
         "updatedAt":"2026-10-01T12:00:00Z","additions":4,"deletions":2,
         "repository":{"nameWithOwner":"\(nameWithOwner)"},
         "viewerSubscription":"\(subscription)","viewerCanSubscribe":true}
        """
    }
}
