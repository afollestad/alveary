import XCTest

@testable import Alveary

@MainActor
final class AppUpdateManagerTests: XCTestCase {
    func testForceCheckReportsUpdateAndRecordsState() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let clock = AppUpdateTestClock(now: Date(timeIntervalSince1970: 100))
        let manager = AppUpdateManager(
            releaseClient: AppUpdateReleaseClientFake(results: [.installable(release)]),
            versionProvider: AppUpdateVersionProviderFake(versionString: "0.1.0"),
            scheduleTiming: clock.scheduleTiming
        )

        let result = await manager.forceCheck()

        let currentVersion = try XCTUnwrap(AppUpdateVersion(string: "0.1.0"))
        XCTAssertEqual(result, .updateAvailable(release, currentVersion: currentVersion))
        XCTAssertEqual(manager.status, .updateAvailable(release, currentVersion: currentVersion))
        XCTAssertEqual(manager.latestRelease, release)
        XCTAssertEqual(manager.currentVersion, currentVersion)
        XCTAssertEqual(manager.lastCheckedAt, Date(timeIntervalSince1970: 100))
        XCTAssertFalse(manager.isChecking)
        XCTAssertNil(manager.lastManualFailure)
        XCTAssertEqual(manager.toolbarBadgeState, .updateAvailable)
    }

    func testAutomaticUnavailableResultStaysQuiet() async {
        let manager = AppUpdateManager(
            releaseClient: AppUpdateReleaseClientFake(results: [.unavailable(.privateOrNotFound)]),
            versionProvider: AppUpdateVersionProviderFake(versionString: "0.1.0")
        )

        let result = await manager.runCheck(trigger: .automatic)

        XCTAssertEqual(result, .unavailable(.privateOrNotFound))
        XCTAssertEqual(manager.status, .idle)
        XCTAssertNil(manager.lastManualFailure)
    }

    func testManualUnavailableResultSurfacesFailure() async {
        let manager = AppUpdateManager(
            releaseClient: AppUpdateReleaseClientFake(results: [.unavailable(.rateLimited(resetDate: nil))]),
            versionProvider: AppUpdateVersionProviderFake(versionString: "0.1.0")
        )

        let result = await manager.forceCheck()

        XCTAssertEqual(result, .unavailable(.rateLimited(resetDate: nil)))
        XCTAssertEqual(manager.status, .unavailable(.rateLimited(resetDate: nil)))
        XCTAssertEqual(manager.lastManualFailure, .rateLimited(resetDate: nil))
        XCTAssertEqual(manager.toolbarBadgeState, .none)
    }

    func testForceCheckCoalescesOverlappingChecks() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let client = AppUpdateReleaseClientFake()
        let manager = AppUpdateManager(
            releaseClient: client,
            versionProvider: AppUpdateVersionProviderFake(versionString: "0.1.0")
        )

        let firstCheck = Task { @MainActor in
            await manager.forceCheck()
        }
        let secondCheck = Task { @MainActor in
            await manager.forceCheck()
        }

        try await waitUntil("expected one coalesced release lookup") {
            await client.callCount() == 1
        }
        await client.completeNext(with: .installable(release))

        let currentVersion = try XCTUnwrap(AppUpdateVersion(string: "0.1.0"))
        let expectedResult = AppUpdateCheckResult.updateAvailable(release, currentVersion: currentVersion)
        let firstResult = await firstCheck.value
        let secondResult = await secondCheck.value
        let callCount = await client.callCount()

        XCTAssertEqual(firstResult, expectedResult)
        XCTAssertEqual(secondResult, expectedResult)
        XCTAssertEqual(callCount, 1)
        XCTAssertFalse(manager.isChecking)
    }

    func testStartAutomaticChecksRunsLaunchCheckAndSchedulesSixHourChecks() async throws {
        let firstRelease = try makeManagerTestRelease(tagName: "v0.1.1")
        let secondRelease = try makeManagerTestRelease(tagName: "v0.1.2")
        let client = AppUpdateReleaseClientFake(results: [
            .installable(firstRelease),
            .installable(secondRelease)
        ])
        let clock = AppUpdateTestClock()
        let manager = AppUpdateManager(
            releaseClient: client,
            versionProvider: AppUpdateVersionProviderFake(versionString: "0.1.0"),
            scheduleTiming: clock.scheduleTiming
        )
        defer { manager.stopAutomaticChecks() }

        manager.startAutomaticChecks()
        manager.startAutomaticChecks()

        try await waitUntil("expected one launch update check") {
            await client.callCount() == 1
        }
        try await waitUntil("expected scheduled automatic sleep") {
            clock.sleepDurations().count == 1
        }
        XCTAssertEqual(clock.sleepDurations(), [.seconds(21_600)])

        clock.advanceNextSleep()

        try await waitUntil("expected scheduled update check") {
            await client.callCount() == 2
        }
        XCTAssertEqual(manager.latestRelease, secondRelease)
    }

    func testForceCheckResetsNextAutomaticCheckFromCompletion() async throws {
        let launchRelease = try makeManagerTestRelease(tagName: "v0.1.1")
        let manualRelease = try makeManagerTestRelease(tagName: "v0.1.2")
        let client = AppUpdateReleaseClientFake(results: [
            .installable(launchRelease),
            .installable(manualRelease)
        ])
        let clock = AppUpdateTestClock()
        let manager = AppUpdateManager(
            releaseClient: client,
            versionProvider: AppUpdateVersionProviderFake(versionString: "0.1.0"),
            scheduleTiming: clock.scheduleTiming
        )
        defer { manager.stopAutomaticChecks() }

        manager.startAutomaticChecks()
        try await waitUntil("expected launch check schedule") {
            clock.sleepDurations().count == 1
        }

        await manager.forceCheck()

        try await waitUntil("expected manual check to reset automatic schedule") {
            clock.sleepDurations().count == 2 && clock.cancelledSleepCount() == 1
        }
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(manager.latestRelease, manualRelease)
    }

}

actor AppUpdateReleaseClientFake: AppUpdateReleaseClient {
    private var results: [AppUpdateReleaseLookupResult]
    private var pendingContinuations: [CheckedContinuation<AppUpdateReleaseLookupResult, Never>] = []
    private var latestReleaseCallCount = 0

    init(results: [AppUpdateReleaseLookupResult] = []) {
        self.results = results
    }

    func latestRelease() async -> AppUpdateReleaseLookupResult {
        latestReleaseCallCount += 1
        if !results.isEmpty {
            return results.removeFirst()
        }

        return await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
        }
    }

    func completeNext(with result: AppUpdateReleaseLookupResult) {
        guard !pendingContinuations.isEmpty else {
            results.append(result)
            return
        }

        pendingContinuations.removeFirst().resume(returning: result)
    }

    func callCount() -> Int {
        latestReleaseCallCount
    }
}

struct AppUpdateVersionProviderFake: AppVersionProviding {
    let versionString: String?

    var currentVersionString: String? {
        versionString
    }

    var currentVersion: AppUpdateVersion? {
        versionString.flatMap(AppUpdateVersion.init(string:))
    }
}

private final class AppUpdateTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var nowValue: Date
    private var nextSleepID = 0
    private var sleepRequests: [SleepRequest] = []

    init(now: Date = Date(timeIntervalSince1970: 0)) {
        nowValue = now
    }

    var scheduleTiming: AppUpdateScheduleTiming {
        AppUpdateScheduleTiming(
            automaticCheckInterval: .seconds(21_600),
            now: { [weak self] in
                self?.currentDate() ?? Date(timeIntervalSince1970: 0)
            },
            sleep: { [weak self] duration in
                guard let self else {
                    throw CancellationError()
                }
                try await self.sleep(for: duration)
            }
        )
    }

    func sleepDurations() -> [Duration] {
        lock.withLock {
            sleepRequests.map(\.duration)
        }
    }

    func cancelledSleepCount() -> Int {
        lock.withLock {
            sleepRequests.filter(\.isCancelled).count
        }
    }

    func advanceNextSleep() {
        let continuation = lock.withLock {
            guard let index = sleepRequests.firstIndex(where: { $0.continuation != nil && !$0.isCancelled }) else {
                return nil as CheckedContinuation<Void, Error>?
            }

            sleepRequests[index].isCompleted = true
            let continuation = sleepRequests[index].continuation
            sleepRequests[index].continuation = nil
            return continuation
        }

        continuation?.resume()
    }

    private func currentDate() -> Date {
        lock.withLock {
            nowValue
        }
    }

    private func sleep(for duration: Duration) async throws {
        let sleepID = lock.withLock {
            let sleepID = nextSleepID
            nextSleepID += 1
            sleepRequests.append(SleepRequest(id: sleepID, duration: duration))
            return sleepID
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let shouldCancel = storeContinuation(continuation, for: sleepID)
                if shouldCancel {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            self.cancelSleep(id: sleepID)
        }
    }

    private func storeContinuation(_ continuation: CheckedContinuation<Void, Error>, for sleepID: Int) -> Bool {
        lock.withLock {
            guard let index = sleepRequests.firstIndex(where: { $0.id == sleepID }) else {
                return true
            }

            if sleepRequests[index].isCancelled {
                return true
            }

            sleepRequests[index].continuation = continuation
            return false
        }
    }

    private func cancelSleep(id sleepID: Int) {
        let continuation = lock.withLock {
            guard let index = sleepRequests.firstIndex(where: { $0.id == sleepID }) else {
                return nil as CheckedContinuation<Void, Error>?
            }

            guard !sleepRequests[index].isCompleted, !sleepRequests[index].isCancelled else {
                return nil as CheckedContinuation<Void, Error>?
            }

            sleepRequests[index].isCancelled = true
            let continuation = sleepRequests[index].continuation
            sleepRequests[index].continuation = nil
            return continuation
        }

        continuation?.resume(throwing: CancellationError())
    }
}

private struct SleepRequest {
    let id: Int
    let duration: Duration
    var continuation: CheckedContinuation<Void, Error>?
    var isCancelled = false
    var isCompleted = false
}

func makeManagerTestRelease(tagName: String) throws -> AppUpdateRelease {
    let downloadURL = "https://github.com/afollestad/alveary/releases/download/\(tagName)/Alveary.app.zip"
    return AppUpdateRelease(
        tagName: tagName,
        version: try XCTUnwrap(AppUpdateVersion(string: tagName)),
        changelogMarkdown: "Changes",
        htmlURL: try XCTUnwrap(URL(string: "https://github.com/afollestad/alveary/releases/tag/\(tagName)")),
        repositoryHTMLURL: try XCTUnwrap(URL(string: "https://github.com/afollestad/alveary")),
        asset: AppUpdateReleaseAsset(
            name: "Alveary.app.zip",
            apiURL: try XCTUnwrap(URL(string: "https://api.github.com/repos/afollestad/alveary/releases/assets/123")),
            downloadURL: try XCTUnwrap(URL(string: downloadURL)),
            size: 123,
            digest: try XCTUnwrap(AppUpdateReleaseAssetDigest(sha256HexDigest: String(repeating: "a", count: 64)))
        )
    )
}

private extension NSLock {
    func withLock<Result>(_ body: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return body()
    }
}
