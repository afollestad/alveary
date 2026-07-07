import SwiftUI

extension View {
    func appUpdateRestartAlert(updateManager: AppUpdateManager) -> some View {
        modifier(AppUpdateRestartAlertModifier(updateManager: updateManager))
    }
}

private struct AppUpdateRestartAlertModifier: ViewModifier {
    let updateManager: AppUpdateManager

    func body(content: Content) -> some View {
        content.alert(
            "Restart Alveary to install update?",
            isPresented: Binding(
                get: { updateManager.restartPrompt != nil },
                set: { isPresented in
                    if !isPresented {
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
