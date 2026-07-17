import Foundation

enum VoiceInputPlatform {
    static var isSupported: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }
}

enum VoiceInputShortcutUnavailableReason: Equatable, Sendable {
    case unsupportedArchitecture
    case notConfigured
    case conflict(String)

    var message: String {
        switch self {
        case .unsupportedArchitecture:
            return "Voice input requires a Mac with Apple silicon. Mouse and keyboard dictation are unavailable on Intel."
        case .notConfigured:
            return "No keyboard shortcut is configured. Mouse dictation remains available."
        case let .conflict(message):
            return message + " Choose a different shortcut to use keyboard dictation."
        }
    }
}

enum VoiceInputShortcutAvailability: Equatable, Sendable {
    case available(PhysicalKeyboardShortcut)
    case unavailable(VoiceInputShortcutUnavailableReason)

    var descriptor: PhysicalKeyboardShortcut? {
        guard case let .available(descriptor) = self else {
            return nil
        }
        return descriptor
    }

    var displayString: String? {
        descriptor?.displayString
    }

    var unavailableReason: VoiceInputShortcutUnavailableReason? {
        guard case let .unavailable(reason) = self else {
            return nil
        }
        return reason
    }
}

extension AppSettings {
    mutating func normalizeAppShotDefaults() {
        guard let normalizedShortcut = appShotShortcut.normalized,
              normalizedShortcut != .bothCommand else {
            appShotShortcut = Self.defaultAppShotShortcut
            return
        }
        appShotShortcut = normalizedShortcut
    }

    mutating func normalizeVoiceInputShortcut() {
        voiceInputShortcut = voiceInputShortcut?.voiceInputNormalized
        voiceInputShortcutMigrationCompleted = true
    }

    static func normalizedAppShotShortcut(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> AppShotKeyboardShortcut {
        guard let shortcut = try? container.decodeIfPresent(
            AppShotKeyboardShortcut.self,
            forKey: .appShotShortcut
        )?.normalized,
            shortcut != .bothCommand else {
            return defaultAppShotShortcut
        }
        return shortcut
    }

    mutating func decodeVoiceInputShortcut(from container: KeyedDecodingContainer<CodingKeys>) {
        let migrationCompleted = (try? container.decode(Bool.self, forKey: .voiceInputShortcutMigrationCompleted)) == true
        if migrationCompleted || container.contains(.voiceInputShortcut) {
            voiceInputShortcut = (try? container.decode(PhysicalKeyboardShortcut.self, forKey: .voiceInputShortcut))?.voiceInputNormalized
        } else {
            voiceInputShortcut = Self.migratedVoiceInputShortcut(appShotShortcut: appShotShortcut)
        }
        voiceInputShortcutMigrationCompleted = true
    }

    static func migratedVoiceInputShortcut(
        appShotShortcut: AppShotKeyboardShortcut,
        hasEnabledSystemConflict: ((PhysicalKeyboardShortcut) -> Bool)? = nil
    ) -> PhysicalKeyboardShortcut? {
        let appShotDescriptor = appShotShortcut.keyChord
        for candidate in [defaultVoiceInputShortcut, fallbackVoiceInputShortcut]
        where PhysicalKeyboardShortcutValidation.message(
            for: candidate,
            assignment: .voiceInput,
            appShotShortcut: appShotDescriptor,
            voiceInputShortcut: nil,
            hasEnabledSystemConflict: hasEnabledSystemConflict
        ) == nil {
            return candidate
        }
        return nil
    }

    /// Re-evaluate this when `.appSettingsChanged` or `NSApplication.didBecomeActiveNotification` fires.
    func voiceInputShortcutAvailability(
        supportsVoiceInput: Bool = VoiceInputPlatform.isSupported,
        hasEnabledSystemConflict: ((PhysicalKeyboardShortcut) -> Bool)? = nil
    ) -> VoiceInputShortcutAvailability {
        guard supportsVoiceInput else {
            return .unavailable(.unsupportedArchitecture)
        }
        guard let shortcut = voiceInputShortcut else {
            return .unavailable(.notConfigured)
        }
        if let message = PhysicalKeyboardShortcutValidation.message(
            for: shortcut,
            assignment: .voiceInput,
            appShotShortcut: appShotShortcut.keyChord,
            voiceInputShortcut: nil,
            hasEnabledSystemConflict: hasEnabledSystemConflict
        ) {
            return .unavailable(.conflict(message))
        }
        return .available(shortcut)
    }
}
