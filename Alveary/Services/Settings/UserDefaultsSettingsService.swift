import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class UserDefaultsSettingsService: SettingsService {
    static let storageKey = "appSettings"

    private let defaults: UserDefaults
    private let encode: @Sendable (AppSettings) throws -> Data
    private(set) var current: AppSettings

    init(
        defaults: UserDefaults = .standard,
        hasEnabledSystemConflict: @escaping (PhysicalKeyboardShortcut) -> Bool = {
            PhysicalKeyboardShortcutValidation.hasEnabledSystemShortcut(matching: $0)
        },
        encode: @escaping @Sendable (AppSettings) throws -> Data = { try JSONEncoder().encode($0) }
    ) {
        self.defaults = defaults
        self.encode = encode

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            let migrationState = Self.voiceInputShortcutMigrationState(data)
            var loadedSettings = decoded.normalized()
            if migrationState.needsDefaultSelection {
                loadedSettings.voiceInputShortcut = AppSettings.migratedVoiceInputShortcut(
                    appShotShortcut: loadedSettings.appShotShortcut,
                    hasEnabledSystemConflict: hasEnabledSystemConflict
                )
            }
            current = loadedSettings
            if migrationState.needsPersistence,
               let migratedData = try? encode(current) {
                defaults.set(migratedData, forKey: Self.storageKey)
            }
        } else {
            var initialSettings = AppSettings()
            initialSettings.voiceInputShortcut = AppSettings.migratedVoiceInputShortcut(
                appShotShortcut: initialSettings.appShotShortcut,
                hasEnabledSystemConflict: hasEnabledSystemConflict
            )
            current = initialSettings
            if let initialData = try? encode(initialSettings) {
                defaults.set(initialData, forKey: Self.storageKey)
            }
        }
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        var updated = current
        transform(&updated)
        updated = updated.normalized()

        persist(updated, notify: true)
    }

    func updateRestoreSelection(threadID: PersistentIdentifier?, conversationID: PersistentIdentifier?) {
        guard current.lastOpenThreadID != threadID || current.lastOpenConversationID != conversationID else {
            return
        }

        var updated = current
        updated.lastOpenThreadID = threadID
        updated.lastOpenConversationID = conversationID
        updated = updated.normalized()

        persist(updated, notify: false)
    }

    func updateLastActiveProjectPath(_ path: String?) {
        guard current.lastActiveProjectPath != path else {
            return
        }

        var updated = current
        updated.lastActiveProjectPath = path
        persist(updated.normalized(), notify: false)
    }

    private func persist(_ updated: AppSettings, notify: Bool) {
        do {
            let data = try encode(updated)
            defaults.set(data, forKey: Self.storageKey)
            current = updated
            if notify {
                NotificationCenter.default.post(name: .appSettingsChanged, object: self)
            }
        } catch {
            print("[SettingsService] Failed to persist app settings: \(error)")
        }
    }

    private static func voiceInputShortcutMigrationState(
        _ data: Data
    ) -> (needsDefaultSelection: Bool, needsPersistence: Bool) {
        guard let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, false)
        }
        let needsPersistence = dictionary["voiceInputShortcutMigrationCompleted"] as? Bool != true
        let needsDefaultSelection = needsPersistence && !dictionary.keys.contains("voiceInputShortcut")
        return (needsDefaultSelection, needsPersistence)
    }
}
