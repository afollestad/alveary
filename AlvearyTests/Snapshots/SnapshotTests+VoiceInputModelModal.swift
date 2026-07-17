import SwiftUI

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testVoiceInputModelModalDownloadLight() {
        assertMacSnapshot(
            VoiceInputModelModal(
                state: .preparing(.downloading(kind: .installation, fraction: 0.42)),
                onCancel: {},
                onContinue: {},
                onOpenMicrophoneSettings: {}
            ),
            size: CGSize(width: 900, height: 640),
            named: "voice_input_model_modal_download_light",
            colorScheme: .light
        )
    }

    func testVoiceInputModelModalReadyDark() {
        assertMacSnapshot(
            VoiceInputModelModal(
                state: .ready,
                onCancel: {},
                onContinue: {},
                onOpenMicrophoneSettings: {}
            ),
            size: CGSize(width: 900, height: 640),
            named: "voice_input_model_modal_ready_dark",
            colorScheme: .dark
        )
    }

    func testVoiceInputModelModalLoadingNarrow() {
        assertMacSnapshot(
            VoiceInputModelModal(
                state: .preparing(.loadingModel),
                onCancel: {},
                onContinue: {},
                onOpenMicrophoneSettings: {}
            ),
            size: CGSize(width: 520, height: 700),
            named: "voice_input_model_modal_loading_narrow",
            colorScheme: .light
        )
    }

    func testVoiceInputModelModalCancellingNarrow() {
        assertMacSnapshot(
            VoiceInputModelModal(
                state: .cancelling,
                onCancel: {},
                onContinue: {},
                onOpenMicrophoneSettings: {}
            ),
            size: CGSize(width: 520, height: 700),
            named: "voice_input_model_modal_cancelling_narrow",
            colorScheme: .dark
        )
    }
}
