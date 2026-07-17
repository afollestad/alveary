import Carbon
import XCTest

@testable import Alveary

@MainActor
extension SettingsViewModelTests {
    func testVoiceInputShortcutSetterPersistsLiveChange() {
        let service = InMemorySettingsService()
        let viewModel = SettingsViewModel(settingsService: service)
        let shortcut = PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_R),
            modifiers: [.command, .control],
            keyEquivalent: "R"
        )

        viewModel.voiceInputShortcut = shortcut

        XCTAssertEqual(service.current.voiceInputShortcut, shortcut)
        XCTAssertEqual(service.updateCount, 1)
    }

    func testVoiceInputShortcutCanBeResetToMouseOnlyUnavailable() {
        let service = InMemorySettingsService()
        let viewModel = SettingsViewModel(settingsService: service)

        viewModel.voiceInputShortcut = nil

        XCTAssertNil(service.current.voiceInputShortcut)
        XCTAssertEqual(service.updateCount, 1)
    }
}
