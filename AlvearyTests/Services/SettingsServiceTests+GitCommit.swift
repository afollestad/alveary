import XCTest

@testable import Alveary

@MainActor
extension SettingsServiceTests {
    func testUserDefaultsSettingsServicePersistsGitCommitSettingsAcrossReloads() throws {
        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(defaults: defaults)

        service.update {
            $0.commitMessageGenerationPrompt = "Custom commit prompt"
            $0.gitCommitIncludeUnstagedChanges = false
        }

        let reloadedService = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(reloadedService.current.commitMessageGenerationPrompt, "Custom commit prompt")
        XCTAssertFalse(reloadedService.current.gitCommitIncludeUnstagedChanges)
    }
}
