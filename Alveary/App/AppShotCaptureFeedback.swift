@preconcurrency import AppKit
import Foundation

@MainActor
enum AppShotCaptureFeedback {
    private static var screenshotSound: NSSound?
    private static let screenshotSoundPaths = [
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif"
    ]

    static func activateAlveary() {
        NSApp.unhide(nil)
        if let window = mainAlvearyWindow() {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
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

    private static func mainAlvearyWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.title == "Alveary" && window.canBecomeKey
        } ?? NSApp.mainWindow ?? NSApp.keyWindow
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
