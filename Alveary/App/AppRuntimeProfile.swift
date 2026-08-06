import Darwin
import Foundation

struct AppRuntimeProfile: Sendable {
    enum Kind: Equatable, Sendable {
        case application
        case hostedUnitTest
        /// Debug-only isolated storage for manual first-run testing. Deliberately not
        /// `hostedUnitTest`, so window launch and restoration behave like a normal run.
        case scratch(name: String)
    }

    static let hostedUnitTestEnvironmentKey = "ALVEARY_HOSTED_UNIT_TEST"
    static let storageProfileEnvironmentKey = "ALVEARY_STORAGE_PROFILE"
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
