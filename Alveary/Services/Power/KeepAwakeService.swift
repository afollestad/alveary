import Foundation
import IOKit.pwr_mgt

@MainActor
protocol KeepAwakeService: AnyObject, Sendable {
    func setActive(_ active: Bool, for source: KeepAwakeActivitySource)
}

struct KeepAwakeActivitySource: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case runtimeActivity
        case outboundConversationWork
    }

    let kind: Kind
    let id: String

    static let runtimeActivity = KeepAwakeActivitySource(kind: .runtimeActivity, id: "runtime")

    static func outboundConversationWork(conversationId: String) -> KeepAwakeActivitySource {
        KeepAwakeActivitySource(kind: .outboundConversationWork, id: conversationId)
    }
}

@MainActor
final class DefaultKeepAwakeService: NSObject, KeepAwakeService {
    private static let assertionOrder: [PowerAssertionKind] = [
        .preventUserIdleSystemSleep,
        .preventUserIdleDisplaySleep
    ]

    private let settingsService: SettingsService
    private let assertionClient: PowerAssertionClient
    private let assertionName = "Alveary thread work" as CFString
    // Sources behave like leases; assertions stay live until the final source clears.
    private var activeSources = Set<KeepAwakeActivitySource>()
    private var activeAssertions: [PowerAssertionKind: PowerAssertionID] = [:]
    private var settings: TurnAwakeSettings

    init(
        settingsService: SettingsService,
        assertionClient: PowerAssertionClient = IOKitPowerAssertionClient()
    ) {
        self.settingsService = settingsService
        self.assertionClient = assertionClient
        self.settings = settingsService.current.turnAwake
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .appSettingsChanged,
            object: nil
        )
        reconcileAssertions()
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        for id in activeAssertions.values {
            assertionClient.releaseAssertion(id: id)
        }
    }

    func setActive(_ active: Bool, for source: KeepAwakeActivitySource) {
        if active {
            activeSources.insert(source)
        } else {
            activeSources.remove(source)
        }
        reconcileAssertions()
    }

    @objc private func handleSettingsChanged() {
        settings = settingsService.current.turnAwake
        reconcileAssertions()
    }

    private func reconcileAssertions() {
        let desired = desiredAssertionKinds()
        for kind in Self.assertionOrder where !desired.contains(kind) {
            if let id = activeAssertions.removeValue(forKey: kind) {
                assertionClient.releaseAssertion(id: id)
            }
        }

        for kind in Self.assertionOrder where desired.contains(kind) && activeAssertions[kind] == nil {
            if let id = assertionClient.createAssertion(kind: kind, name: assertionName) {
                activeAssertions[kind] = id
            }
        }
    }

    private func desiredAssertionKinds() -> Set<PowerAssertionKind> {
        guard settings.enabled, !activeSources.isEmpty else {
            return []
        }

        var kinds: Set<PowerAssertionKind> = [.preventUserIdleSystemSleep]
        if settings.preventDisplaySleep {
            // Display sleep is separate from idle system sleep; keep it opt-out so the setting can match caffeinate -d -i.
            kinds.insert(.preventUserIdleDisplaySleep)
        }
        return kinds
    }
}

enum PowerAssertionKind: String, Sendable, Hashable {
    case preventUserIdleSystemSleep
    case preventUserIdleDisplaySleep

    var cfString: CFString {
        switch self {
        case .preventUserIdleSystemSleep:
            return kIOPMAssertPreventUserIdleSystemSleep as CFString
        case .preventUserIdleDisplaySleep:
            return kIOPMAssertPreventUserIdleDisplaySleep as CFString
        }
    }
}

typealias PowerAssertionID = IOPMAssertionID

protocol PowerAssertionClient: AnyObject, Sendable {
    func createAssertion(kind: PowerAssertionKind, name: CFString) -> PowerAssertionID?
    func releaseAssertion(id: PowerAssertionID)
}

final class IOKitPowerAssertionClient: PowerAssertionClient, @unchecked Sendable {
    func createAssertion(kind: PowerAssertionKind, name: CFString) -> PowerAssertionID? {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kind.cfString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }

    func releaseAssertion(id: PowerAssertionID) {
        IOPMAssertionRelease(id)
    }
}
