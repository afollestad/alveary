import XCTest

@testable import Alveary

final class AgentEnvironmentBuilderTests: XCTestCase {
    func testPathIsAugmentedWithFallbackExecutableDirectories() throws {
        let path = try XCTUnwrap(DefaultAgentEnvironmentBuilder().buildEnvironment()["PATH"])
        let components = path.split(separator: ":").map(String.init)

        for directory in ExecutableSearchPath.defaultFallbackExecutableDirectories {
            let expanded = ExecutableSearchPath.expandHomeDirectory(in: directory)
            XCTAssertTrue(
                components.contains(expanded),
                "Expected augmented PATH to contain \(expanded)"
            )
        }
    }

    func testAugmentedPathAppendsToBareFinderPathWithoutDuplicates() {
        // A Finder-launched app gets exactly this PATH, which is why agents could not see `gh`.
        let bareFinderPath = "/usr/bin:/bin:/usr/sbin:/sbin"
        let augmented = ExecutableSearchPath.augmentedPath(bareFinderPath)
        let components = augmented.split(separator: ":").map(String.init)

        XCTAssertEqual(Array(components.prefix(4)), ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
        XCTAssertEqual(Set(components).count, components.count, "Augmented PATH must not repeat entries")
        XCTAssertTrue(components.contains("/opt/homebrew/bin"))
    }

    func testAugmentedPathDoesNotDuplicateDirectoriesAlreadyPresent() {
        let augmented = ExecutableSearchPath.augmentedPath("/opt/homebrew/bin:/usr/bin")
        let components = augmented.split(separator: ":").map(String.init)

        XCTAssertEqual(components.filter { $0 == "/opt/homebrew/bin" }.count, 1)
        XCTAssertEqual(components.first, "/opt/homebrew/bin", "Existing PATH order must be preserved")
    }

    func testProviderEnvironmentOverridesBaseValues() {
        let environment = DefaultAgentEnvironmentBuilder().buildEnvironment(
            providerEnv: ["PATH": "/provider/only", "CUSTOM": "value"]
        )

        XCTAssertEqual(environment["PATH"], "/provider/only")
        XCTAssertEqual(environment["CUSTOM"], "value")
    }
}
