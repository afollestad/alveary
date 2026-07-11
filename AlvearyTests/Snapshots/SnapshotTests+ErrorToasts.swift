import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testAppSuccessToast() {
        let toast = AppState.UnexpectedErrorToast(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004") ?? UUID(),
            message: "App shot added to Feature work.",
            kind: .success
        )

        assertMacSnapshot(
            ZStack(alignment: .bottom) {
                Color(nsColor: .windowBackgroundColor)
                AppErrorToastStack(toasts: [toast], onDismiss: { _ in })
            },
            size: CGSize(width: 700, height: 180),
            named: "app_success_toast",
            colorScheme: .dark
        )
    }

    func testAppErrorToastStackMultipleToasts() {
        let toasts = [
            AppState.UnexpectedErrorToast(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                message: "Provider archive sync failed."
            ),
            AppState.UnexpectedErrorToast(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID(),
                message: "Could not restore Codex provider session session-2."
            ),
            AppState.UnexpectedErrorToast(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003") ?? UUID(),
                message: "Developer test error toast"
            )
        ]

        assertMacSnapshot(
            ZStack(alignment: .bottom) {
                Color(nsColor: .windowBackgroundColor)
                AppErrorToastStack(toasts: toasts, onDismiss: { _ in })
            },
            size: CGSize(width: 700, height: 300),
            named: "app_error_toast_stack_multiple_toasts",
            colorScheme: .dark
        )
    }
}
