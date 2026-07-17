@preconcurrency import AppKit
import Carbon
import Foundation

struct AppShotKeyboardShortcut: Codable, Hashable, Identifiable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case bothCommand
        case keyChord
    }

    typealias KeyChord = PhysicalKeyboardShortcut

    var kind: Kind
    var keyChord: KeyChord?

    var id: String {
        switch kind {
        case .bothCommand:
            return "bothCommand"
        case .keyChord:
            guard let keyChord else {
                return "invalid"
            }
            return "keyChord-\(keyChord.keyCode)-\(keyChord.modifiers.rawValue)"
        }
    }

    var label: String {
        switch kind {
        case .bothCommand:
            return "Both Command keys"
        case .keyChord:
            return "Keyboard shortcut"
        }
    }

    var displayString: String {
        switch kind {
        case .bothCommand:
            return "⌘⌘"
        case .keyChord:
            guard let keyChord else { return "" }
            // App Shot historically displayed the recorded key equivalent
            // verbatim (including the visible space glyph).
            return keyChord.modifiers.displayPrefix + keyChord.keyEquivalent
        }
    }

    var modifierCount: Int {
        keyChord?.modifierCount ?? 0
    }

    var normalized: AppShotKeyboardShortcut? {
        switch kind {
        case .bothCommand:
            return .bothCommand
        case .keyChord:
            guard let keyChord = keyChord?.normalized else {
                return nil
            }
            return AppShotKeyboardShortcut(keyChord: keyChord)
        }
    }

    static let bothCommand = AppShotKeyboardShortcut(kind: .bothCommand)
    static let controlShiftS = AppShotKeyboardShortcut(
        keyCode: UInt16(kVK_ANSI_S),
        modifiers: [.control, .shift],
        keyEquivalent: "S"
    )
    static let commandShiftS = AppShotKeyboardShortcut(
        keyCode: UInt16(kVK_ANSI_S),
        modifiers: [.command, .shift],
        keyEquivalent: "S"
    )

    init(kind: Kind, keyChord: KeyChord? = nil) {
        self.kind = kind
        self.keyChord = keyChord
    }

    init(keyChord: KeyChord) {
        self.init(kind: .keyChord, keyChord: keyChord)
    }

    init(keyCode: UInt16, modifiers: AppShotKeyboardShortcutModifiers, keyEquivalent: String) {
        self.init(
            keyChord: KeyChord(
                keyCode: keyCode,
                modifiers: modifiers,
                keyEquivalent: keyEquivalent
            )
        )
    }

    init(from decoder: any Decoder) throws {
        if let legacyShortcut = try Self.decodeLegacyShortcut(from: decoder) {
            self = legacyShortcut
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        keyChord = try container.decodeIfPresent(KeyChord.self, forKey: .keyChord)

        if normalized == nil {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid app-shot keyboard shortcut."
                )
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        if self == .bothCommand {
            var container = encoder.singleValueContainer()
            try container.encode("bothCommand")
            return
        }
        if self == .controlShiftS {
            var container = encoder.singleValueContainer()
            try container.encode("controlShiftS")
            return
        }
        if self == .commandShiftS {
            var container = encoder.singleValueContainer()
            try container.encode("commandShiftS")
            return
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(keyChord, forKey: .keyChord)
    }

    func matches(event: NSEvent) -> Bool {
        guard case .keyChord = kind,
              let keyChord else {
            return false
        }
        return keyChord.matches(event: event)
    }

    static func recorded(from event: NSEvent) -> AppShotKeyboardShortcut? {
        guard let shortcut = PhysicalKeyboardShortcut.recorded(from: event, allowsModifierKey: true) else {
            return nil
        }
        return AppShotKeyboardShortcut(keyChord: shortcut)
    }

    static func validationMessage(
        for shortcut: AppShotKeyboardShortcut,
        currentShortcut: AppShotKeyboardShortcut,
        voiceInputShortcut: PhysicalKeyboardShortcut? = nil
    ) -> String? {
        guard case .keyChord = shortcut.kind,
              let keyChord = shortcut.keyChord else {
            return nil
        }
        if let message = PhysicalKeyboardShortcutValidation.message(
            for: keyChord,
            assignment: .appShot,
            appShotShortcut: nil,
            voiceInputShortcut: voiceInputShortcut,
            displayString: shortcut.displayString
        ) {
            return message
        }
        if shortcut != currentShortcut,
           !canRegisterGlobally(keyChord: keyChord) {
            return "\(shortcut.displayString) is already used by another app."
        }
        return nil
    }

    private static func decodeLegacyShortcut(from decoder: any Decoder) throws -> AppShotKeyboardShortcut? {
        let container = try decoder.singleValueContainer()
        guard let rawValue = try? container.decode(String.self) else {
            return nil
        }
        switch rawValue {
        case "bothCommand":
            return .bothCommand
        case "controlShiftS":
            return .controlShiftS
        case "commandShiftS":
            return .commandShiftS
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown app-shot keyboard shortcut."
            )
        }
    }

    private static func canRegisterGlobally(keyChord: KeyChord) -> Bool {
        let hotKeyID = EventHotKeyID(signature: appShotValidationHotKeySignature, id: appShotValidationHotKeyID)
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyChord.keyCode),
            keyChord.modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        return status == noErr
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case keyChord
    }
}

typealias AppShotKeyboardShortcutModifiers = PhysicalKeyboardShortcutModifiers

private let appShotValidationHotKeySignature = OSType(0x41505648) // APVH
private let appShotValidationHotKeyID: UInt32 = 1
