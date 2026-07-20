import Darwin
import Foundation

struct AppRuntimeProfile: Sendable {
    enum Kind: Equatable, Sendable {
        case application
        case hostedUnitTest
    }

    static let hostedUnitTestEnvironmentKey = "ALVEARY_HOSTED_UNIT_TEST"
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
