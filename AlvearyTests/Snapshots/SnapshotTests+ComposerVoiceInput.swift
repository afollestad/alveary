import SwiftUI

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testAppKitComposerPanelVoiceInputIdleLight() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(voiceInputPhase: .ready),
            size: CGSize(width: 1000, height: 150),
            named: "appkit_composer_panel_voice_input_idle_light",
            colorScheme: .light
        )
    }

    func testAppKitComposerPanelVoiceInputRecordingDark() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(voiceInputPhase: .recording),
            size: CGSize(width: 1000, height: 150),
            named: "appkit_composer_panel_voice_input_recording_dark",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelVoiceInputHighContrast() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                voiceInputPhase: .recording,
                voiceInputIncreasesContrast: true
            ),
            size: CGSize(width: 1000, height: 150),
            named: "appkit_composer_panel_voice_input_high_contrast",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelVoiceInputPreparingReduceMotionNarrow() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                voiceInputPhase: .preparing(message: "Loading voice model…", fraction: nil),
                voiceInputReducesMotion: true
            ),
            size: CGSize(width: 620, height: 150),
            named: "appkit_composer_panel_voice_input_preparing_reduce_motion_narrow",
            colorScheme: .dark
        )
    }
}

extension AppKitComposerPanelNativeRowSnapshot {
    var voiceInputConfiguration: ComposerVoiceInputConfiguration? {
        voiceInputPhase.map { phase in
            ComposerVoiceInputConfiguration(
                phase: phase,
                isEnabled: phase == .ready || phase == .recording,
                shortcutDisplay: "⌃⇧Space",
                unavailableHelp: nil,
                reducesMotion: voiceInputReducesMotion,
                increasesContrast: voiceInputIncreasesContrast,
                onPress: { true },
                onRelease: { _ in true },
                onAccessibilityToggle: {},
                onAccessibilityCancel: { true }
            )
        }
    }
}
