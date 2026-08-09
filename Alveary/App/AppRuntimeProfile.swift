import Darwin
import Foundation

struct AppRuntimeProfile: Sendable {
    enum Kind: Equatable, Sendable {
        case application
        case hostedUnitTest
        /// Debug-only isolated storage for manual first-run testing. Deliberately not
        /// `hostedUnitTest`, so window launch and restoration behave like a normal run.
        case scratch(name: String)
        #if DEBUG
        /// Debug-only screenshot mode: isolated storage that is wiped and reseeded with
        /// deterministic fake data on every launch. Wrapped in `#if DEBUG` because its
        /// factory *deletes* a directory tree, which must not exist in a shipped binary.
        case demo
        #endif
    }

    static let hostedUnitTestEnvironmentKey = "ALVEARY_HOSTED_UNIT_TEST"
    static let storageProfileEnvironmentKey = "ALVEARY_STORAGE_PROFILE"
    static let demoEnvironmentKey = "ALVEARY_DEMO_MODE"
    static let current = makeCurrent()

    let kind: Kind
    let storageProfile: AppStorageProfile

    var isHostedUnitTest: Bool {
        kind == .hostedUnitTest
    }

    static func detectKind(environment: [String: String]) -> Kind {
        if environment[hostedUnitTestEnvironmentKey] == "1" {
            return .hostedUnitTest
        }

        let injectedLibraries = environment["DYLD_INSERT_LIBRARIES"] ?? ""
        if injectedLibraries
            .split(separator: ":")
            .contains(where: { $0.hasSuffix("libXCTestBundleInject.dylib") }) {
            return .hostedUnitTest
        }

        if environment["XCTestBundlePath"]?.hasSuffix("AlvearyTests.xctest") == true {
            return .hostedUnitTest
        }

        // Checked after every hosted-test marker so a stray variable cannot divert a test run.
        #if DEBUG
        // Demo outranks scratch: demo mode wipes its store on entry, and a launch asking for
        // both should get the mode that reseeds rather than the one that preserves.
        if environment[demoEnvironmentKey] == "1" {
            return .demo
        }

        if let scratchName = environment[storageProfileEnvironmentKey], !scratchName.isEmpty {
            return .scratch(name: AppStorageProfile.sanitizedScratchName(scratchName))
        }
        #endif

        return .application
    }

    private static func makeCurrent() -> AppRuntimeProfile {
        let kind = detectKind(environment: ProcessInfo.processInfo.environment)
        switch kind {
        case .application:
            return AppRuntimeProfile(kind: kind, storageProfile: .production)
        case .hostedUnitTest:
            let profile = AppRuntimeProfile(kind: kind, storageProfile: .hostedUnitTest())
            registerHostedUnitTestCleanup()
            return profile
        case .scratch(let name):
            return AppRuntimeProfile(kind: kind, storageProfile: .scratch(name: name))
        #if DEBUG
        case .demo:
            // `demo()` wipes its tree, so it must run before anything derived from an
            // `AppStorageProfile` path is opened. `AlvearyApp.init` resolves `AppDI.component`
            // (and therefore this profile) before the model container, which is what makes the
            // ordering safe today; `demo()` asserts the store is absent to catch a regression.
            // The handshake covers the other direction: a relaunch must not wipe the tree while
            // the instance it replaces is still shutting down with the store open.
            DemoStorageHandshake.waitForOtherInstancesToExit()
            return AppRuntimeProfile(kind: kind, storageProfile: .demo())
        #endif
        }
    }

    private static func registerHostedUnitTestCleanup() {
        // App-hosted XCTest processes do not reliably deliver `applicationWillTerminate`.
        // Keep this process-exit fallback so the isolated defaults domain is still removed.
        atexit {
            AppRuntimeProfile.current.storageProfile.cleanupSettingsDefaults()
        }
    }
}
