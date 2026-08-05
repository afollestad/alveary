import XCTest

@testable import Alveary

@MainActor
final class ProjectConfigStoreTests: XCTestCase {
    func testConfigReadsOnceThenServesTheCachedValue() async {
        let counter = ReadCounter()
        let store = ProjectConfigStore { path in
            await counter.record(path)
            return AlvearyProjectConfig(actions: [.init(name: "Build", command: "build")])
        }

        let first = await store.config(forProjectPath: "/tmp/project")
        let second = await store.config(forProjectPath: "/tmp/project")

        XCTAssertEqual(first.actions?.count, 1)
        XCTAssertEqual(second, first)
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    func testCachedIsNilBeforeAnyLoadAndPopulatedAfter() async {
        let store = ProjectConfigStore { _ in
            AlvearyProjectConfig(setupScript: "setup")
        }

        XCTAssertNil(store.cached(forProjectPath: "/tmp/project"))

        _ = await store.config(forProjectPath: "/tmp/project")

        XCTAssertEqual(store.cached(forProjectPath: "/tmp/project")?.setupScript, "setup")
    }

    func testConcurrentLoadsForTheSameProjectShareOneRead() async {
        let counter = ReadCounter()
        let store = ProjectConfigStore { path in
            // Suspend so both callers arrive while the first read is still running.
            try? await Task.sleep(for: .milliseconds(20))
            await counter.record(path)
            return AlvearyProjectConfig(setupScript: "setup")
        }

        async let first = store.config(forProjectPath: "/tmp/project")
        async let second = store.reload(forProjectPath: "/tmp/project")
        let results = await [first, second]

        XCTAssertEqual(results[0], results[1])
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    func testReloadReadsAgainEvenWhenCached() async {
        let counter = ReadCounter()
        let store = ProjectConfigStore { path in
            let attempt = await counter.record(path)
            return AlvearyProjectConfig(setupScript: "setup-\(attempt)")
        }

        _ = await store.config(forProjectPath: "/tmp/project")
        let reloaded = await store.reload(forProjectPath: "/tmp/project")

        XCTAssertEqual(reloaded.setupScript, "setup-2")
        XCTAssertEqual(store.cached(forProjectPath: "/tmp/project")?.setupScript, "setup-2")
    }

    func testStoredConfigReplacesTheCachedValueWithoutReading() async {
        let counter = ReadCounter()
        let store = ProjectConfigStore { path in
            await counter.record(path)
            return .empty
        }

        store.store(AlvearyProjectConfig(setupScript: "written"), forProjectPath: "/tmp/project")
        let config = await store.config(forProjectPath: "/tmp/project")

        XCTAssertEqual(config.setupScript, "written")
        let count = await counter.count
        XCTAssertEqual(count, 0)
    }

    func testReplacingACachedValuePostsTheChangeNotification() async {
        let store = ProjectConfigStore { _ in AlvearyProjectConfig(setupScript: "original") }
        _ = await store.config(forProjectPath: "/tmp/project")

        let posted = expectation(forNotification: .projectConfigDidChange, object: nil) { notification in
            ProjectConfigChangeNotifier.changedProjectPath(in: notification) == "/tmp/project"
        }

        store.store(AlvearyProjectConfig(setupScript: "changed"), forProjectPath: "/tmp/project")

        await fulfillment(of: [posted], timeout: 1)
    }

    func testFirstLoadAndUnchangedValuesPostNoNotification() async {
        let store = ProjectConfigStore { _ in AlvearyProjectConfig(setupScript: "same") }
        let observer = NotificationObserver(name: .projectConfigDidChange)
        defer { observer.stop() }

        // A first load has no reader that could be holding a stale value.
        _ = await store.config(forProjectPath: "/tmp/project")
        // Re-storing an equal value changes nothing for anyone.
        store.store(AlvearyProjectConfig(setupScript: "same"), forProjectPath: "/tmp/project")

        XCTAssertEqual(observer.count, 0)
    }

    func testProjectsAreCachedIndependently() async {
        let store = ProjectConfigStore { path in
            AlvearyProjectConfig(setupScript: "setup-for-\(path)")
        }

        let first = await store.config(forProjectPath: "/tmp/one")
        let second = await store.config(forProjectPath: "/tmp/two")

        XCTAssertEqual(first.setupScript, "setup-for-/tmp/one")
        XCTAssertEqual(second.setupScript, "setup-for-/tmp/two")
        XCTAssertEqual(store.cached(forProjectPath: "/tmp/one")?.setupScript, "setup-for-/tmp/one")
    }
}

private actor ReadCounter {
    private(set) var count = 0
    private(set) var paths: [String] = []

    @discardableResult
    func record(_ path: String) -> Int {
        count += 1
        paths.append(path)
        return count
    }
}

@MainActor
private final class NotificationObserver {
    private(set) var count = 0
    private var token: NSObjectProtocol?

    init(name: Notification.Name) {
        token = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.count += 1
            }
        }
    }

    func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
    }
}
