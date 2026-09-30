import Observation
import XCTest

@testable import Alveary

@MainActor
final class ContentViewHostTests: XCTestCase {
    /// `ContentView.init` runs inside `ContentViewHost.body`, so anything it observes re-runs the
    /// whole root on every write.
    func testContentViewInitObservesNoSettingsOrThreadWrites() throws {
        let profile = AppStorageProfile.hostedUnitTest()
        defer { profile.cleanupSettingsDefaults() }
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true, storageProfile: profile)
        let thread = AgentThread(name: "Thread")
        component.modelContainer.mainContext.insert(thread)
        try component.modelContainer.mainContext.save()
        let dependencies = ContentViewDependencies.resolve(component)
        let appState = AppState()
        let bootstrapState = ContentView.makeBootstrapState(dependencies: dependencies, appState: appState)
        let didInvalidate = LockedState(false)

        withObservationTracking {
            _ = ContentView(dependencies: dependencies, bootstrapState: bootstrapState, appState: appState)
        } onChange: {
            didInvalidate.withLock { $0 = true }
        }
        component.settingsService.update { $0.rightPaneWidth += 1 }
        thread.name = "Renamed"

        XCTAssertFalse(didInvalidate.withLock { $0 })
    }
}
