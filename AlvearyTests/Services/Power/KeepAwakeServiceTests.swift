import Foundation
import XCTest

@testable import Alveary

@MainActor
final class KeepAwakeServiceTests: XCTestCase {
    func testAcquiresSystemAndDisplayAssertionsForActiveSourceWhenEnabled() {
        let settings = makeSettings(enabled: true, preventDisplaySleep: true)
        let client = RecordingPowerAssertionClient()
        let service = DefaultKeepAwakeService(settingsService: settings, assertionClient: client)

        service.setActive(true, for: .runtimeActivity)

        XCTAssertEqual(client.createdKinds, [.preventUserIdleSystemSleep, .preventUserIdleDisplaySleep])
        XCTAssertTrue(client.releasedIDs.isEmpty)
    }

    func testDoesNotAcquireAssertionsWhenDisabled() {
        let settings = makeSettings(enabled: false, preventDisplaySleep: true)
        let client = RecordingPowerAssertionClient()
        let service = DefaultKeepAwakeService(settingsService: settings, assertionClient: client)

        service.setActive(true, for: .runtimeActivity)

        XCTAssertTrue(client.createdKinds.isEmpty)
        XCTAssertTrue(client.releasedIDs.isEmpty)
    }

    func testAcquiresOnlySystemAssertionWhenDisplaySleepPreventionIsDisabled() {
        let settings = makeSettings(enabled: true, preventDisplaySleep: false)
        let client = RecordingPowerAssertionClient()
        let service = DefaultKeepAwakeService(settingsService: settings, assertionClient: client)

        service.setActive(true, for: .runtimeActivity)

        XCTAssertEqual(client.createdKinds, [.preventUserIdleSystemSleep])
        XCTAssertTrue(client.releasedIDs.isEmpty)
    }

    func testKeepsAssertionsUntilLastSourceClears() {
        let settings = makeSettings(enabled: true, preventDisplaySleep: true)
        let client = RecordingPowerAssertionClient()
        let service = DefaultKeepAwakeService(settingsService: settings, assertionClient: client)
        let outboundSource = KeepAwakeActivitySource.outboundConversationWork(conversationId: "conversation-1")

        service.setActive(true, for: .runtimeActivity)
        service.setActive(true, for: outboundSource)
        service.setActive(false, for: .runtimeActivity)

        XCTAssertEqual(client.createdKinds, [.preventUserIdleSystemSleep, .preventUserIdleDisplaySleep])
        XCTAssertTrue(client.releasedIDs.isEmpty)

        service.setActive(false, for: outboundSource)

        XCTAssertEqual(client.releasedIDs, [1, 2])
    }

    func testReleasesImmediatelyWhenSettingIsDisabled() {
        let settings = makeSettings(enabled: true, preventDisplaySleep: true)
        let client = RecordingPowerAssertionClient()
        let service = DefaultKeepAwakeService(settingsService: settings, assertionClient: client)
        service.setActive(true, for: .runtimeActivity)

        settings.update {
            $0.turnAwake.enabled = false
        }

        XCTAssertEqual(client.releasedIDs, [1, 2])
    }

    func testUpdatesDisplayAssertionWhenSettingChanges() {
        let settings = makeSettings(enabled: true, preventDisplaySleep: true)
        let client = RecordingPowerAssertionClient()
        let service = DefaultKeepAwakeService(settingsService: settings, assertionClient: client)
        service.setActive(true, for: .runtimeActivity)

        settings.update {
            $0.turnAwake.preventDisplaySleep = false
        }

        XCTAssertEqual(client.createdKinds, [.preventUserIdleSystemSleep, .preventUserIdleDisplaySleep])
        XCTAssertEqual(client.releasedIDs, [2])

        settings.update {
            $0.turnAwake.preventDisplaySleep = true
        }

        XCTAssertEqual(client.createdKinds, [
            .preventUserIdleSystemSleep,
            .preventUserIdleDisplaySleep,
            .preventUserIdleDisplaySleep
        ])
    }

    private func makeSettings(enabled: Bool, preventDisplaySleep: Bool) -> InMemorySettingsService {
        var appSettings = AppSettings()
        appSettings.turnAwake = TurnAwakeSettings(enabled: enabled, preventDisplaySleep: preventDisplaySleep)
        return InMemorySettingsService(current: appSettings)
    }
}

private final class RecordingPowerAssertionClient: PowerAssertionClient, @unchecked Sendable {
    private let lock = NSLock()
    private var nextID: PowerAssertionID = 1

    var createdKinds: [PowerAssertionKind] {
        lock.withLock { _createdKinds }
    }

    var releasedIDs: [PowerAssertionID] {
        lock.withLock { _releasedIDs }
    }

    private var _createdKinds: [PowerAssertionKind] = []
    private var _releasedIDs: [PowerAssertionID] = []

    func createAssertion(kind: PowerAssertionKind, name: CFString) -> PowerAssertionID? {
        lock.withLock {
            let id = nextID
            nextID += 1
            _createdKinds.append(kind)
            return id
        }
    }

    func releaseAssertion(id: PowerAssertionID) {
        lock.withLock {
            _releasedIDs.append(id)
        }
    }
}
