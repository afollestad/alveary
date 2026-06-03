import Foundation

struct NotificationSettings: Codable, Sendable, Equatable {
    static let availableSoundNames = ["Glass", "Pop", "Tink", "Purr"]
    static let defaultSoundName = "Glass"

    var enabled = true
    var osNotifications = true
    var sound = true
    var soundName: String? = NotificationSettings.defaultSoundName
}
