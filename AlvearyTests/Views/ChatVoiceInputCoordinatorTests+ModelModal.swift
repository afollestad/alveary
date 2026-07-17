import XCTest

@testable import Alveary

private struct VoiceModelPreparationCopyCase {
    let kind: VoiceInputModelPreparationKind
    let phaseMessage: String
    let modalTitle: String
    let modalStatus: String
}

private let voiceModelPreparationCopyCases = [
    VoiceModelPreparationCopyCase(
        kind: .installation,
        phaseMessage: "Downloading voice model (about 600 MB)…",
        modalTitle: "Downloading Voice Model",
        modalStatus: "Downloading the English voice model (about 600 MB)…"
    ),
    VoiceModelPreparationCopyCase(
        kind: .update,
        phaseMessage: "Updating voice model (about 600 MB)…",
        modalTitle: "Updating Voice Model",
        modalStatus: "Updating the English voice model (about 600 MB)…"
    ),
    VoiceModelPreparationCopyCase(
        kind: .repair,
        phaseMessage: "Repairing voice model (about 600 MB)…",
        modalTitle: "Repairing Voice Model",
        modalStatus: "Repairing the English voice model (about 600 MB)…"
    )
]

@MainActor
extension ChatVoiceInputCoordinatorTests {
    func testPreparationUsesInstallUpdateAndRepairCopy() async throws {
        for testCase in voiceModelPreparationCopyCases {
            let fixture = try makeFixture()
            fixture.service.setPreparationResult(VoiceInputPreparationResult(
                source: .downloaded(testCase.kind),
                requestedMicrophonePermission: false
            ))
            fixture.service.setPreparationProgress([.downloading(kind: testCase.kind, fraction: 0.5)])
            fixture.service.setSuspendsPrepare(true)

            XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
            await waitUntil { fixture.service.hasPendingPrepare }
            await waitUntil {
                fixture.coordinator.phase == .preparing(message: testCase.phaseMessage, fraction: 0.5)
            }
            XCTAssertEqual(fixture.coordinator.phase, .preparing(message: testCase.phaseMessage, fraction: 0.5))
            XCTAssertEqual(
                fixture.coordinator.modelModalState,
                .preparing(.downloading(kind: testCase.kind, fraction: 0.5))
            )
            XCTAssertEqual(
                VoiceInputModelModalPresentation(state: try XCTUnwrap(fixture.coordinator.modelModalState)).title,
                testCase.modalTitle
            )

            fixture.service.resumePendingPrepare()
            await waitUntil { fixture.coordinator.phase == .ready }
            XCTAssertEqual(fixture.coordinator.modelModalState, .ready)
        }
    }

    func testVoiceModelModalPresentationCoversProgressSuccessFailureAndCancelling() {
        let checkingPermission = VoiceInputModelModalPresentation(state: .preparing(.checkingPermission))
        XCTAssertEqual(checkingPermission.title, "Preparing Voice Input")
        XCTAssertEqual(checkingPermission.indicator, .progress(fraction: nil))
        XCTAssertEqual(checkingPermission.action, .cancel(isEnabled: true))
        XCTAssertEqual(
            VoiceInputModelModalPresentation.indeterminateProgressAccessibilityLabel,
            "Voice model preparation progress"
        )
        XCTAssertNotEqual(
            VoiceInputModelModalPresentation.indeterminateProgressAccessibilityLabel,
            checkingPermission.status
        )

        let checkingModel = VoiceInputModelModalPresentation(state: .preparing(.checkingModel))
        XCTAssertEqual(checkingModel.status, "Checking the local voice model cache…")
        XCTAssertEqual(checkingModel.indicator, .progress(fraction: nil))

        let loading = VoiceInputModelModalPresentation(state: .preparing(.loadingModel))
        XCTAssertEqual(loading.title, "Loading Voice Model")
        XCTAssertEqual(loading.indicator, .progress(fraction: nil))

        let ready = VoiceInputModelModalPresentation(state: .ready)
        XCTAssertEqual(ready.title, "Voice Input Is Ready")
        XCTAssertEqual(ready.indicator, .success)
        XCTAssertEqual(ready.action, .proceed)
        XCTAssertEqual(
            VoiceInputModelModalPresentation(state: .preparing(.ready)),
            ready
        )

        let cancelling = VoiceInputModelModalPresentation(state: .cancelling)
        XCTAssertEqual(cancelling.title, "Cancelling Voice Model Setup")
        XCTAssertEqual(cancelling.indicator, .progress(fraction: nil))
        XCTAssertEqual(cancelling.action, .cancel(isEnabled: false))

        let failed = VoiceInputModelModalPresentation(state: .failed(
            message: "Microphone access is off.",
            recovery: .microphoneSettings
        ))
        XCTAssertEqual(failed.title, "Voice Input Setup Failed")
        XCTAssertEqual(failed.indicator, .failure)
        XCTAssertEqual(failed.action, .cancel(isEnabled: true))
        XCTAssertTrue(failed.showsMicrophoneSettings)
    }

    func testVoiceModelModalDownloadProgressIsTypedAndClamped() {
        for testCase in voiceModelPreparationCopyCases {
            let presentation = VoiceInputModelModalPresentation(state: .preparing(
                .downloading(kind: testCase.kind, fraction: 1.25)
            ))
            XCTAssertEqual(presentation.title, testCase.modalTitle)
            XCTAssertEqual(presentation.status, testCase.modalStatus)
            XCTAssertEqual(presentation.indicator, .progress(fraction: 1))
            XCTAssertEqual(presentation.action, .cancel(isEnabled: true))
            XCTAssertFalse(presentation.showsMicrophoneSettings)
        }

        let negative = VoiceInputModelModalPresentation(state: .preparing(
            .downloading(kind: .installation, fraction: -0.5)
        ))
        XCTAssertEqual(negative.indicator, .progress(fraction: 0))

        let nonfinite = VoiceInputModelModalPresentation(state: .preparing(
            .downloading(kind: .installation, fraction: .nan)
        ))
        XCTAssertEqual(nonfinite.indicator, .progress(fraction: nil))
    }
}
