import XCTest

@testable import Alveary

extension GitHubPullRequestsServiceTests {
    // MARK: - Mapping

    func testListMapsNodesMergesBucketsAndSetsFlags() async throws {
        let shell = makeUniformShellRunner(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list))
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil, options: .firstPage)

        XCTAssertEqual(result.warnings, [])
        // Empty and null nodes drop out; buckets merge by id and sort newest first.
        XCTAssertEqual(result.summaries.map(\.id.number), [2, 1, 3])

        let merged = result.summaries[1]
        XCTAssertEqual(merged.id, PullRequestIdentifier(owner: "octo", repo: "alpha", number: 1))
        // The newer authored entry supplies fields; the stale requested duplicate only ORs flags.
        XCTAssertEqual(merged.title, "Add feature one")
        XCTAssertEqual(merged.status, .open)
        XCTAssertEqual(merged.authorLogin, "alice")
        XCTAssertEqual(merged.authorAvatarURL, URL(string: "https://avatars.example.com/alice"))
        XCTAssertEqual(merged.headRefName, "feat/one")
        XCTAssertEqual(merged.baseRefName, "main")
        XCTAssertEqual(merged.additions, 5)
        XCTAssertEqual(merged.deletions, 2)
        XCTAssertEqual(merged.reviewDecision, "REVIEW_REQUIRED")
        XCTAssertTrue(merged.isAuthored)
        XCTAssertTrue(merged.isReviewRequested)
        XCTAssertFalse(merged.hasReviewed)

        let draft = result.summaries[0]
        XCTAssertEqual(draft.status, .draft)
        XCTAssertEqual(draft.authorLogin, "ghost")
        XCTAssertNil(draft.authorAvatarURL)
        XCTAssertFalse(draft.isAuthored)
        XCTAssertTrue(draft.isReviewRequested)

        let reviewed = result.summaries[2]
        XCTAssertEqual(reviewed.status, .merged)
        XCTAssertTrue(reviewed.hasReviewed)
    }

    func testMergeCombinesBucketsFlagsAndSorts() {
        let older = makePullRequestSummary(
            number: 1,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isAuthored: true
        )
        let newerSameID = makePullRequestSummary(
            number: 1,
            title: "Newer title",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isReviewRequested: true
        )
        let other = makePullRequestSummary(
            number: 2,
            updatedAt: Date(timeIntervalSince1970: 1_500),
            hasReviewed: true
        )

        let merged = PullRequestListMerge.merge([[older], [newerSameID, other]])

        XCTAssertEqual(merged.map(\.id.number), [1, 2])
        XCTAssertEqual(merged[0].title, "Newer title")
        XCTAssertTrue(merged[0].isAuthored)
        XCTAssertTrue(merged[0].isReviewRequested)
        XCTAssertFalse(merged[0].hasReviewed)
        XCTAssertTrue(merged[1].hasReviewed)
    }

    // MARK: - Fan-out

    func testListFansOutOneRequestPerBucketWithoutRollup() async throws {
        let shell = makeUniformShellRunner(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list))
        let service = makeGitHubPullRequestsService(shell: shell)

        _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil, options: .firstPage)

        // One request per bucket: GitHub runs a batched request's aliased searches serially, so
        // three in one request cost about three searches.
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 3)
        XCTAssertEqual(Set(invocations.compactMap(searchArgument)), [
            "authored=is:pr author:@me sort:updated-desc",
            "requested=is:pr review-requested:@me sort:updated-desc",
            "reviewed=is:pr reviewed-by:@me sort:updated-desc"
        ])
        for invocation in invocations {
            XCTAssertEqual(invocation.executable, "/opt/homebrew/bin/gh")
            XCTAssertEqual(Array(invocation.args.prefix(2)), ["api", "graphql"])
            // Exactly one search alias per leg, so no leg pays for another's search.
            XCTAssertEqual(invocation.args.filter(isSearchArgument).count, 1)
            let query = try XCTUnwrap(invocation.args.first { $0.hasPrefix("query=") })
            XCTAssertTrue(query.contains("fragment pr on PullRequest"))
            // The list intentionally skips rollup — it is the slow, 502-prone field.
            XCTAssertFalse(query.contains("statusCheckRollup"))
            XCTAssertEqual(invocation.stdoutLimitBytes, 4 * 1024 * 1024)
            // Under the host-tool bridge's 30s budget, so a hung `gh` names its own timeout.
            XCTAssertEqual(invocation.timeout, .seconds(20))
            // A credential prompt on inherited stdin would hang the leg until that timeout.
            XCTAssertEqual(invocation.standardInput, .nullDevice)
        }
    }

    func testListRequestsOnlyTheBucketsAskedFor() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: [.authored], status: nil, options: .firstPage)

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertTrue(invocation.args.contains("authored=is:pr author:@me sort:updated-desc"))
        XCTAssertFalse(invocation.args.contains { $0.hasPrefix("requested=") })
        XCTAssertFalse(invocation.args.contains { $0.hasPrefix("reviewed=") })
        let query = try XCTUnwrap(invocation.args.first { $0.hasPrefix("query=") })
        XCTAssertTrue(query.contains("query($authored: String!, $authoredAfter: String)"))
        XCTAssertFalse(query.contains("requested:"))
        XCTAssertFalse(query.contains("reviewed:"))
        // The fixture carries all three buckets; only the requested one is keyed back.
        XCTAssertEqual(Set(result.summariesByBucket.keys), [.authored])
    }

    func testListDegradesToTheBucketsThatLoaded() async throws {
        let shell = MockShellRunner()
        await shell.setResponder { invocation in
            guard invocation.args.contains(where: { $0.hasPrefix("requested=") }) else {
                return .success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list))
            }
            return .success(pullRequestsShellResult(stderr: "gh: Bad gateway (HTTP 502)", exitCode: 1))
        }
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil, options: .firstPage)

        // A failed bucket is absent rather than empty, which is what tells it apart from the
        // SAML-forbidden bucket below; the warning is what says the answer is short one bucket.
        XCTAssertEqual(Set(result.summariesByBucket.keys), [.authored, .reviewed])
        XCTAssertEqual(result.summaries.map(\.id.number), [1, 3])
        XCTAssertEqual(
            result.warnings,
            ["Could not load review-requested pull requests: GitHub request failed with HTTP 502"]
        )
    }

    func testListThrowsTheFirstBucketFailureWhenEveryLegFails() async {
        let shell = MockShellRunner()
        await shell.setResponder { invocation in
            guard invocation.args.contains(where: { $0.hasPrefix("authored=") }) else {
                return .success(pullRequestsShellResult(stderr: "gh: Not Found (HTTP 404)", exitCode: 1))
            }
            return .success(pullRequestsShellResult(stderr: "gh: HTTP 401 Bad credentials", exitCode: 1))
        }
        let service = makeGitHubPullRequestsService(shell: shell)

        // `allCases` order, not completion order, so repeated runs report the same failure.
        await assertPullRequestsServiceThrows(.notAuthenticated) {
            _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil, options: .firstPage)
        }
    }

    // MARK: - Paging

    func testListDecodesPageInfoAndAlignsRowCursorsWithTheRowsThatMapped() async throws {
        let shell = makeUniformShellRunner(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list))
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil, options: .firstPage)

        // The authored bucket's second and third edges map to nothing, so neither contributes a
        // row cursor — the two arrays have to stay index-for-index.
        XCTAssertEqual(result.summariesByBucket[.authored]?.count, 1)
        XCTAssertEqual(result.pageInfoByBucket[.authored]?.rowCursors, ["authored-1"])
        XCTAssertEqual(result.pageInfoByBucket[.authored]?.hasNextPage, false)

        XCTAssertEqual(result.pageInfoByBucket[.reviewRequested]?.rowCursors, ["requested-1", "requested-2"])
        XCTAssertEqual(result.pageInfoByBucket[.reviewRequested]?.endCursor, "requested-2")
        XCTAssertEqual(result.pageInfoByBucket[.reviewRequested]?.hasNextPage, true)
    }

    func testListSelectsEdgeCursorsAndPageInfoAndClampsThePageSize() async throws {
        let shell = makeUniformShellRunner(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list))
        let service = makeGitHubPullRequestsService(shell: shell)

        _ = try await service.listInvolvedPullRequests(
            buckets: [.authored],
            status: nil,
            // Past GitHub's own `search` ceiling, which the query must clamp rather than send.
            options: PullRequestListOptions(pageSize: 500)
        )

        let invocations = await shell.invocations
        let query = try XCTUnwrap(invocations.first?.args.first { $0.hasPrefix("query=") })
        XCTAssertTrue(query.contains("first: 100"), query)
        XCTAssertTrue(query.contains("edges { cursor node { ...pr } }"), query)
        XCTAssertTrue(query.contains("pageInfo { endCursor hasNextPage }"), query)
        XCTAssertFalse(query.contains("nodes { ...pr }"), query)
    }

    func testListPassesACursorOnlyForTheBucketThatHasOne() async throws {
        let shell = makeUniformShellRunner(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list))
        let service = makeGitHubPullRequestsService(shell: shell)

        _ = try await service.listInvolvedPullRequests(
            buckets: allBuckets,
            status: nil,
            options: PullRequestListOptions(cursors: [.reviewRequested: "requested-2"])
        )

        let invocations = await shell.invocations
        let afterArguments = invocations.flatMap { $0.args.filter { $0.contains("After=") } }
        // The variable is declared on every leg, but only the resumed bucket is given a value —
        // an omitted one arrives as null, which is GitHub's "start at the first page".
        XCTAssertEqual(afterArguments, ["requestedAfter=requested-2"])
        for invocation in invocations {
            let query = try XCTUnwrap(invocation.args.first { $0.hasPrefix("query=") })
            XCTAssertTrue(query.contains("After: String)"), query)
        }
    }

    func testListPutsTheUpdatedBoundsInEveryBucketsSearchQuery() async throws {
        let shell = makeUniformShellRunner(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list))
        let service = makeGitHubPullRequestsService(shell: shell)

        _ = try await service.listInvolvedPullRequests(
            buckets: [.authored],
            status: .open,
            options: PullRequestListOptions(
                updatedAfter: Date(timeIntervalSince1970: 1_767_225_600),
                updatedBefore: Date(timeIntervalSince1970: 1_772_409_600)
            )
        )

        let invocations = await shell.invocations
        XCTAssertEqual(
            invocations.compactMap(searchArgument),
            ["authored=is:pr is:open draft:false author:@me updated:>=2026-01-01 updated:<=2026-03-02 sort:updated-desc"]
        )
    }

    func testListReportsASAMLForbiddenBucketAsHavingNoNextPage() async throws {
        let shell = makeUniformShellRunner(pullRequestsShellResult(
            stdout: PullRequestsServiceFixtures.samlPartial,
            exitCode: 1
        ))
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil, options: .firstPage)

        // Loaded-and-empty, not more-pages-unknown: a caller must never page a bucket GitHub
        // refuses to answer.
        XCTAssertEqual(result.pageInfoByBucket[.reviewRequested], .exhausted)
    }

    // MARK: - Search qualifiers

    func testListNarrowsEveryBucketToTheSelectedStatus() async throws {
        let shell = makeUniformShellRunner(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list))
        let service = makeGitHubPullRequestsService(shell: shell)

        _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: .open, options: .firstPage)

        let invocations = await shell.invocations
        // `is:open` alone would keep drafts, which are open pull requests.
        XCTAssertEqual(Set(invocations.compactMap(searchArgument)), [
            "authored=is:pr is:open draft:false author:@me sort:updated-desc",
            "requested=is:pr is:open draft:false review-requested:@me sort:updated-desc",
            "reviewed=is:pr is:open draft:false reviewed-by:@me sort:updated-desc"
        ])
    }

    func testListStatusQualifiersCoverEveryStatus() {
        XCTAssertEqual(PullRequestStatus.open.searchQualifier, "is:open draft:false")
        XCTAssertEqual(PullRequestStatus.draft.searchQualifier, "is:open draft:true")
        XCTAssertEqual(PullRequestStatus.merged.searchQualifier, "is:merged")
        // `is:closed` alone counts merged pull requests as closed.
        XCTAssertEqual(PullRequestStatus.closed.searchQualifier, "is:closed is:unmerged")
    }

    // MARK: - Partial results and failures

    func testListKeysARequestedButForbiddenBucketAsEmptyRatherThanMissing() async throws {
        let shell = makeUniformShellRunner(pullRequestsShellResult(
            stdout: PullRequestsServiceFixtures.samlPartial,
            exitCode: 1
        ))
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil, options: .firstPage)

        // A null bucket must read as fetched-and-empty; absent would have the caller refetch forever.
        XCTAssertEqual(Set(result.summariesByBucket.keys), allBuckets)
        XCTAssertEqual(result.summariesByBucket[.reviewRequested], [])
    }

    func testListToleratesPartialForbiddenResults() async throws {
        let shell = makeUniformShellRunner(
            pullRequestsShellResult(stdout: PullRequestsServiceFixtures.samlPartial, exitCode: 1)
        )
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil, options: .firstPage)

        XCTAssertEqual(result.summaries.map(\.id.number), [1])
        XCTAssertTrue(result.summaries[0].isAuthored)
        // Every leg carries the same SAML message; the merge reports it once.
        XCTAssertEqual(result.warnings, ["Resource protected by organization SAML enforcement."])
    }

    func testListMissingCLIThrowsWithoutInvocation() async {
        let shell = MockShellRunner()
        let service = makeGitHubPullRequestsService(shell: shell, executablePath: nil)

        await assertPullRequestsServiceThrows(.ghNotInstalled) {
            _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil, options: .firstPage)
        }
        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    func testListClassifiesFailures() async {
        await assertListFailure(
            .requestFailed(statusCode: 404),
            stderr: "gh: Not Found (HTTP 404)",
            exitCode: 1
        )
        await assertListFailure(
            .notAuthenticated,
            stderr: "gh: HTTP 401 Bad credentials",
            exitCode: 1
        )
        await assertListFailure(
            .notAuthenticated,
            stderr: "To get started with GitHub CLI, please run:  gh auth login",
            exitCode: 4
        )
        await assertListFailure(
            .rateLimited,
            stderr: "gh: API rate limit exceeded for user (HTTP 403)",
            exitCode: 1
        )
        await assertListFailure(
            .ghNotInstalled,
            stderr: "command not found: gh",
            exitCode: 127
        )
        await assertListFailure(
            .transport("boom"),
            stderr: "boom",
            exitCode: 1
        )
    }

    func testListTruncatedResponseThrowsTooLarge() async {
        let shell = makeUniformShellRunner(
            pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list, stdoutWasTruncated: true)
        )
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.responseTooLarge) {
            _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil, options: .firstPage)
        }
    }

    func testListDecodeFailureOnSuccessExitThrowsDecodingFailed() async {
        let shell = makeUniformShellRunner(pullRequestsShellResult(stdout: "not json"))
        let service = makeGitHubPullRequestsService(shell: shell)

        do {
            _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil, options: .firstPage)
            XCTFail("Expected an error")
        } catch let error as PullRequestsServiceError {
            guard case .decodingFailed = error else {
                return XCTFail("Expected decodingFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    // MARK: - Retries

    // A single bucket so the queue stays deterministic: a fan-out's legs consume it in whatever
    // order the task group schedules them.
    func testListRetriesTransientServerErrors() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Something went wrong (HTTP 502)", exitCode: 1)))
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Bad gateway (HTTP 502)", exitCode: 1)))
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: [.authored], status: nil, options: .firstPage)

        XCTAssertEqual(result.summaries.map(\.id.number), [1])
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 3)
    }

    func testListStopsRetryingTransientErrorsAfterLimit() async {
        let shell = makeUniformShellRunner(
            pullRequestsShellResult(stderr: "gh: Bad gateway (HTTP 502)", exitCode: 1)
        )
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 502)) {
            _ = try await service.listInvolvedPullRequests(buckets: [.authored], status: nil, options: .firstPage)
        }
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 3)
    }

    func testListDoesNotRetryNonTransientFailures() async {
        let shell = makeUniformShellRunner(
            pullRequestsShellResult(stderr: "gh: HTTP 401 Bad credentials", exitCode: 1)
        )
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.notAuthenticated) {
            _ = try await service.listInvolvedPullRequests(buckets: [.authored], status: nil, options: .firstPage)
        }
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
    }

    /// The retry budget stops short rather than letting an attempt run past the caller's deadline,
    /// where its named failure would be replaced by a generic timeout.
    func testNextRetryAttemptTimeoutFitsTheRemainingBudget() {
        XCTAssertEqual(
            GitHubPullRequestsService.nextRetryAttemptTimeout(
                elapsed: .zero,
                nextBackoff: .milliseconds(400),
                attemptTimeout: .seconds(20),
                budget: .seconds(25)
            ),
            .seconds(20)
        )
        // Less budget than one full attempt: shorten rather than overrun.
        XCTAssertEqual(
            GitHubPullRequestsService.nextRetryAttemptTimeout(
                elapsed: .seconds(18),
                nextBackoff: .milliseconds(500),
                attemptTimeout: .seconds(20),
                budget: .seconds(25)
            ),
            .milliseconds(6_500)
        )
        // Under two seconds an attempt can only time out, so stop.
        XCTAssertNil(GitHubPullRequestsService.nextRetryAttemptTimeout(
            elapsed: .seconds(24),
            nextBackoff: .milliseconds(400),
            attemptTimeout: .seconds(20),
            budget: .seconds(25)
        ))
    }
}
