import AppKit
import Foundation

extension ChatView {
    func handleAppShotShortcut() {
        Task {
            do {
                let appShot = try await appShotCoordinator.captureAppShot(
                    conversationId: conversation.id,
                    attachmentStore: viewModel.attachmentStore
                )
                viewModel.stageAppShot(appShot)
                presentCapturedAppShotFeedback()
            } catch let error as AppShotCaptureError where error.missingPermission != nil {
                if let permission = error.missingPermission {
                    AppShotPermissionDragGrantAssistant.shared.present(
                        permission: permission,
                        sourceFrameInScreen: nil
                    )
                }
            } catch {
                viewModel.lastTurnError = error.localizedDescription
            }
        }
    }

    private func presentCapturedAppShotFeedback() {
        AppShotCaptureFeedback.playScreenshotSound()
        bringAlvearyWindowToFront()
        appState.requestComposerFocus()
    }

    private func bringAlvearyWindowToFront() {
        NSApp.unhide(nil)
        if let window = AppShotCaptureFeedback.mainAlvearyWindow() {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    #if DEBUG
    func copyAppShotDebugPreview() {
        let draft = viewModel.flushDraftFromEditor()
        do {
            guard !viewModel.state.stagedAppShots.isEmpty else {
                throw AgentError.spawnFailed("No staged app shots to preview.")
            }
            let preview = try viewModel.appShotDebugPreview(providerID: providerID, userInput: draft.messageText)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(preview, forType: .string)
        } catch {
            viewModel.lastTurnError = error.localizedDescription
        }
    }
    #endif
}

@MainActor
private enum AppShotCaptureFeedback {
    private static var screenshotSound: NSSound?
    private static let screenshotSoundPaths = [
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif"
    ]

    static func mainAlvearyWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.title == "Alveary" && window.canBecomeKey
        } ?? NSApp.mainWindow ?? NSApp.keyWindow
    }

    static func playScreenshotSound() {
        let sound = screenshotSound ?? loadScreenshotSound()
        screenshotSound = sound
        guard let sound else {
            NSSound(named: NSSound.Name("Glass"))?.play()
            return
        }
        if sound.isPlaying {
            sound.stop()
        }
        sound.play()
    }

    private static func loadScreenshotSound() -> NSSound? {
        for path in screenshotSoundPaths {
            guard FileManager.default.isReadableFile(atPath: path),
                  let sound = NSSound(contentsOfFile: path, byReference: true) else {
                continue
            }
            return sound
        }
        return NSSound(named: NSSound.Name("Glass"))
    }
}
