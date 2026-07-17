import SwiftUI

extension View {
    func appUpdateRestartAlert(
        updateManager: AppUpdateManager,
        isSuppressed: Bool = false
    ) -> some View {
        modifier(AppUpdateRestartAlertModifier(
            updateManager: updateManager,
            isSuppressed: isSuppressed
        ))
    }
}

enum AppUpdateRestartAlertPolicy {
    static func isPresented(hasRestartPrompt: Bool, isSuppressed: Bool) -> Bool {
        hasRestartPrompt && !isSuppressed
    }

    static func shouldDismissPrompt(requestedPresentation: Bool, isSuppressed: Bool) -> Bool {
        !requestedPresentation && !isSuppressed
    }
}

private struct AppUpdateRestartAlertModifier: ViewModifier {
    let updateManager: AppUpdateManager
    let isSuppressed: Bool

    func body(content: Content) -> some View {
        content.alert(
            "Restart Alveary to install update?",
            isPresented: Binding(
                get: {
                    AppUpdateRestartAlertPolicy.isPresented(
                        hasRestartPrompt: updateManager.restartPrompt != nil,
                        isSuppressed: isSuppressed
                    )
                },
                set: { isPresented in
                    if AppUpdateRestartAlertPolicy.shouldDismissPrompt(
                        requestedPresentation: isPresented,
                        isSuppressed: isSuppressed
                    ) {
                        updateManager.dismissRestartPrompt()
                    }
                }
            )
        ) {
            Button("Restart and Install") {
                Task {
                    await updateManager.installDownloadedUpdate()
                }
            }
            Button("Later", role: .cancel) {
                updateManager.dismissRestartPrompt()
            }
        } message: {
            if let restartPrompt = updateManager.restartPrompt {
                Text("Alveary \(restartPrompt.release.version.description) has been downloaded and is ready to install.")
            }
        }
    }
}
