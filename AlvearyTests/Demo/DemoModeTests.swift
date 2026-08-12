#if DEBUG
import XCTest

@testable import Alveary

/// Guards the Developer menu's relaunch toggle in both directions. The environment it builds is
/// merged into the successor's inherited one rather than swapped for it, so the difference between
/// naming the key and omitting it is the difference between leaving demo mode and staying in it.
@MainActor
final class DemoModeTests: XCTestCase {
    func testLeavingDemoModeNamesTheKeyRatherThanOmittingIt() {
        let environment = DemoMode.relaunchEnvironment(inDemoMode: false)
        XCTAssertEqual(environment[AppRuntimeProfile.demoEnvironmentKey], "0")
        XCTAssertEqual(AppRuntimeProfile.detectKind(environment: environment), .application)
    }

    func testEnteringDemoModeSelectsTheDemoProfile() {
        let environment = DemoMode.relaunchEnvironment(inDemoMode: true)
        XCTAssertEqual(AppRuntimeProfile.detectKind(environment: environment), .demo)
    }
}
#endif
