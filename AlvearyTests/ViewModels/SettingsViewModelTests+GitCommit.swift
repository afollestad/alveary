import XCTest

@testable import Alveary

@MainActor
extension SettingsViewModelTests {
    func testGitCommitGettersReflectCurrentSettings() {
        let service = InMemorySettingsService()
        service.update {
            $0.commitMessageGenerationPrompt = "Custom commit prompt"
            $0.gitCommitIncludeUnstagedChanges = false
        }
        let viewModel = SettingsViewModel(settingsService: service)

        XCTAssertEqual(viewModel.commitMessageGenerationPrompt, "Custom commit prompt")
        XCTAssertFalse(viewModel.gitCommitIncludeUnstagedChanges)
    }

    func testGitCommitSettersWriteBackToSettingsService() {
        let service = InMemorySettingsService()
        let viewModel = SettingsViewModel(settingsService: service)

        viewModel.commitMessageGenerationPrompt = "Updated commit prompt"
        viewModel.gitCommitIncludeUnstagedChanges = false

        XCTAssertEqual(service.current.commitMessageGenerationPrompt, "Updated commit prompt")
        XCTAssertFalse(service.current.gitCommitIncludeUnstagedChanges)
    }
}
