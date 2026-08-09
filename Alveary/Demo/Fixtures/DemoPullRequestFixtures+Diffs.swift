#if DEBUG
import Foundation

// The unified diff each fake pull request serves on its Changes tab.
//
// Review-thread anchors are line numbers into these hunks. A thread whose path and line do not
// name a rendered line simply never appears in the diff — silently, because the tab emits a
// comment row only from a line it drew. `DemoPullRequestFixturesTests` checks every anchor,
// the review proposals' staged comments included, against what these parse to.
//
// Hunk bodies carry no blank lines: a line with no leading marker ends the hunk in `DiffParser`.
extension DemoPullRequestFixtures {
    static func diff(for id: PullRequestIdentifier) -> String? {
        diffsByID[id]
    }

    private static let diffsByID: [PullRequestIdentifier: String] = [
        onboardingWalkthrough: onboardingDiff,
        searchEmptyState: emptyStateDiff,
        webhookRetries: webhookRetriesDiff,
        tileCaching: tileCacheDiff,
        rateLimitMiddleware: rateLimiterDiff,
        filterBottomSheet: filterSheetDiff
    ]

    /// Also `DemoGitWorkspaces.waypoint`'s canned working-copy diff, so the pull request and the
    /// local checkout of the same file tell one story.
    static let tileCacheDiff = """
        diff --git a/Sources/Waypoint/Map/TileCache.swift b/Sources/Waypoint/Map/TileCache.swift
        index 3f1a9c2..b7d40e8 100644
        --- a/Sources/Waypoint/Map/TileCache.swift
        +++ b/Sources/Waypoint/Map/TileCache.swift
        @@ -18,8 +18,17 @@ actor TileCache {
             private let directory: URL
             private var inFlight: [TileKey: Task<Data, Error>] = [:]
        -    func tile(for key: TileKey) async throws -> Data {
        -        try await download(key)
        -    }
        +    func tile(for key: TileKey) async throws -> Data {
        +        if let cached = try? Data(contentsOf: url(for: key)) {
        +            return cached
        +        }
        +        if let existing = inFlight[key] {
        +            return try await existing.value
        +        }
        +        let task = Task { try await download(key) }
        +        inFlight[key] = task
        +        defer { inFlight[key] = nil }
        +        return try await task.value
        +    }
             private func url(for key: TileKey) -> URL {
                 directory.appendingPathComponent(key.filename)
             }
        @@ -34,7 +43,11 @@ actor TileCache {
             private func evict(olderThan age: Duration) throws {
                 let cutoff = Date.now.addingTimeInterval(-age.seconds)
        -        for url in try contents() where try modified(url) < cutoff {
        -            try FileManager.default.removeItem(at: url)
        -        }
        +        let stale = try contents().filter { try modified($0) < cutoff }
        +        for url in stale {
        +            try FileManager.default.removeItem(at: url)
        +        }
        +        if stale.count > Self.evictionWarningThreshold {
        +            logger.notice("evicted \\(stale.count) tiles")
        +        }
             }
         }
        """

    private static let onboardingDiff = """
        diff --git a/Sources/Waypoint/Onboarding/OnboardingFlow.swift b/Sources/Waypoint/Onboarding/OnboardingFlow.swift
        index 4c2a10b..91de7f3 100644
        --- a/Sources/Waypoint/Onboarding/OnboardingFlow.swift
        +++ b/Sources/Waypoint/Onboarding/OnboardingFlow.swift
        @@ -12,8 +12,17 @@ struct OnboardingFlow: View {
             @State private var step: OnboardingStep = .welcome
        -    var body: some View {
        -        VStack {
        -            Text(step.title)
        -            Button("Continue") { step = step.next }
        -        }
        -    }
        +    @State private var completed: Set<OnboardingStep> = []
        +    var body: some View {
        +        VStack(spacing: 24) {
        +            OnboardingProgressBar(step: step, completed: completed)
        +            OnboardingStepView(step: step)
        +                .transition(.opacity.combined(with: .move(edge: .trailing)))
        +            Button(step.continueTitle) { advance() }
        +                .buttonStyle(.borderedProminent)
        +        }
        +        .animation(.snappy, value: step)
        +    }
        +    private func advance() {
        +        completed.insert(step)
        +        step = step.next
        +    }
         }
        diff --git a/Sources/Waypoint/Onboarding/OnboardingStep.swift b/Sources/Waypoint/Onboarding/OnboardingStep.swift
        index 7c9d0e1..2f3a4b5 100644
        --- a/Sources/Waypoint/Onboarding/OnboardingStep.swift
        +++ b/Sources/Waypoint/Onboarding/OnboardingStep.swift
        @@ -3,4 +3,8 @@ enum OnboardingStep: Hashable, CaseIterable {
             case welcome
             case permissions
        +    case sampleTrip
             case finish
        +    var continueTitle: String {
        +        self == .finish ? "Start exploring" : "Continue"
        +    }
         }
        """

    private static let emptyStateDiff = """
        diff --git a/Sources/Hummingbird/Search/SearchEmptyState.swift b/Sources/Hummingbird/Search/SearchEmptyState.swift
        index 5b8c1d0..93e7f24 100644
        --- a/Sources/Hummingbird/Search/SearchEmptyState.swift
        +++ b/Sources/Hummingbird/Search/SearchEmptyState.swift
        @@ -8,6 +8,16 @@ struct SearchEmptyState: View {
             let query: String
        -    var body: some View {
        -        Text("No results")
        -            .foregroundStyle(.secondary)
        -    }
        +    let suggestions: [String]
        +    var body: some View {
        +        VStack(spacing: 12) {
        +            Image(systemName: "magnifyingglass")
        +                .font(.largeTitle)
        +                .foregroundStyle(.tertiary)
        +            Text("No results for \\(query)")
        +                .font(.headline)
        +            if !suggestions.isEmpty {
        +                SuggestionChips(suggestions: suggestions)
        +            }
        +        }
        +        .padding(32)
        +    }
         }
        """

    private static let webhookRetriesDiff = """
        diff --git a/Sources/Ledger/Webhooks/RetryKey.swift b/Sources/Ledger/Webhooks/RetryKey.swift
        new file mode 100644
        index 0000000..6b3ad10
        --- /dev/null
        +++ b/Sources/Ledger/Webhooks/RetryKey.swift
        @@ -0,0 +1,20 @@
        +import Crypto
        +import Foundation
        +/// A stable key for one webhook delivery, so a replay is recognized as the same work.
        +struct RetryKey: Hashable, Sendable {
        +    let value: String
        +    init(payload: WebhookPayload) {
        +        var hasher = SHA256()
        +        hasher.update(data: Data(payload.eventID.utf8))
        +        hasher.update(data: Data(payload.deliveryID.utf8))
        +        hasher.update(data: payload.rawBody)
        +        value = hasher.finalize().hexString
        +    }
        +}
        +extension WebhookPayload {
        +    /// The bytes the key is derived from, kept apart so the timestamp header can be
        +    /// excluded without touching the hashing itself.
        +    var rawBody: Data {
        +        Data(body.utf8)
        +    }
        +}
        diff --git a/Sources/Ledger/Webhooks/RetryPolicy.swift b/Sources/Ledger/Webhooks/RetryPolicy.swift
        index 2c8e5a1..f019b3d 100644
        --- a/Sources/Ledger/Webhooks/RetryPolicy.swift
        +++ b/Sources/Ledger/Webhooks/RetryPolicy.swift
        @@ -44,6 +44,11 @@ struct RetryPolicy: Sendable {
             let maximumAttempts: Int
             let ceiling: Duration
        -    func delay(forAttempt attempt: Int) -> Duration {
        -        base * pow(2, Double(attempt))
        -    }
        +    func delay(forAttempt attempt: Int) -> Duration {
        +        let exponential = base * pow(2, Double(attempt))
        +        let capped = min(exponential, ceiling)
        +        return capped + jitter(upTo: capped / 4)
        +    }
        +    private func jitter(upTo limit: Duration) -> Duration {
        +        .seconds(Double.random(in: 0...limit.seconds))
        +    }
         }
        diff --git a/Tests/LedgerTests/RetryPolicyTests.swift b/Tests/LedgerTests/RetryPolicyTests.swift
        new file mode 100644
        index 0000000..0d7c1a9
        --- /dev/null
        +++ b/Tests/LedgerTests/RetryPolicyTests.swift
        @@ -0,0 +1,10 @@
        +import Testing
        +@testable import Ledger
        +@Test func retryKeyIsStableAcrossDeliveries() {
        +    let payload = WebhookPayload.fixture(eventID: "evt_1")
        +    #expect(RetryKey(payload: payload) == RetryKey(payload: payload))
        +}
        +@Test func delayNeverExceedsTheCeiling() {
        +    let policy = RetryPolicy(base: .seconds(1), maximumAttempts: 6, ceiling: .seconds(30))
        +    #expect(policy.delay(forAttempt: 6) <= .seconds(30))
        +}
        """

    private static let rateLimiterDiff = """
        diff --git a/Sources/Ledger/Middleware/RateLimiter.swift b/Sources/Ledger/Middleware/RateLimiter.swift
        index 91c7d02..5ea3f84 100644
        --- a/Sources/Ledger/Middleware/RateLimiter.swift
        +++ b/Sources/Ledger/Middleware/RateLimiter.swift
        @@ -6,5 +6,11 @@ struct RateLimiter: Sendable {
             let bucket: TokenBucket
        -    func allow(_ request: Request) -> Bool {
        -        bucket.take(1)
        -    }
        +    func allow(_ request: Request) -> Bool {
        +        guard let key = request.clientKey else {
        +            return true
        +        }
        +        return bucket.take(1, for: key)
        +    }
        +    func retryAfter(for request: Request) -> Duration? {
        +        request.clientKey.flatMap { bucket.refillInterval(for: $0) }
        +    }
         }
        """

    private static let filterSheetDiff = """
        diff --git a/Sources/Hummingbird/Search/FilterBottomSheet.swift b/Sources/Hummingbird/Search/FilterBottomSheet.swift
        index c4d51e8..1a0b73f 100644
        --- a/Sources/Hummingbird/Search/FilterBottomSheet.swift
        +++ b/Sources/Hummingbird/Search/FilterBottomSheet.swift
        @@ -14,9 +14,5 @@ struct FilterBottomSheet: View {
             @Binding var filters: FilterSet
        -    @State private var detent: PresentationDetent = .medium
        -    @State private var isDragging = false
        -    var body: some View {
        -        sheetContent
        -            .presentationDetents([.medium, .large], selection: $detent)
        -            .presentationDragIndicator(.visible)
        -    }
        +    var body: some View {
        +        FilterPopover(filters: $filters)
        +    }
         }
        diff --git a/Sources/Hummingbird/Search/FilterSheetDetents.swift b/Sources/Hummingbird/Search/FilterSheetDetents.swift
        deleted file mode 100644
        index 8e2d1c4..0000000
        --- a/Sources/Hummingbird/Search/FilterSheetDetents.swift
        +++ /dev/null
        @@ -1,7 +0,0 @@
        -import SwiftUI
        -/// The detent ladder the bottom sheet snapped to.
        -enum FilterSheetDetent: CaseIterable {
        -    case peek
        -    case medium
        -    case full
        -}
        """
}
#endif
