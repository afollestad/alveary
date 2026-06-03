import AppKit

@MainActor
final class SettingsSoundPreviewer {
    private var currentSound: NSSound?

    func play(_ soundName: String) {
        currentSound?.stop()
        let sound = NSSound(named: NSSound.Name(soundName))
        currentSound = sound
        sound?.play()
    }
}
