@preconcurrency import AppKit
import Carbon
import Foundation

struct AppShotKeyboardShortcut: Codable, Hashable, Identifiable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case bothCommand
        case keyChord
    }

    struct KeyChord: Codable, Hashable, Sendable {
        var keyCode: UInt16
        var modifiers: AppShotKeyboardShortcutModifiers
        var keyEquivalent: String

        var displayString: String {
            modifiers.displayPrefix + keyEquivalent
        }

        static func == (lhs: KeyChord, rhs: KeyChord) -> Bool {
            lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(keyCode)
            hasher.combine(modifiers)
        }
    }

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
            return keyChord?.displayString ?? ""
        }
    }

    var modifierCount: Int {
        guard let keyChord else {
            return 0
        }
        return keyChord.modifiers.count
    }

    var normalized: AppShotKeyboardShortcut? {
        switch kind {
        case .bothCommand:
            return .bothCommand
        case .keyChord:
            guard let keyChord else {
                return nil
            }
            let normalizedModifiers = keyChord.modifiers.normalized
            guard normalizedModifiers.count >= 2,
                  !keyChord.keyEquivalent.isEmpty else {
                return nil
            }
            return AppShotKeyboardShortcut(
                keyCode: keyChord.keyCode,
                modifiers: normalizedModifiers,
                keyEquivalent: keyChord.keyEquivalent
            )
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

    init(keyCode: UInt16, modifiers: AppShotKeyboardShortcutModifiers, keyEquivalent: String) {
        self.kind = .keyChord
        self.keyChord = KeyChord(
            keyCode: keyCode,
            modifiers: modifiers,
            keyEquivalent: keyEquivalent
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

        return keyChord.keyCode == UInt16(event.keyCode)
            && keyChord.modifiers == AppShotKeyboardShortcutModifiers(event.modifierFlags)
    }

    static func recorded(from event: NSEvent) -> AppShotKeyboardShortcut? {
        let modifiers = AppShotKeyboardShortcutModifiers(event.modifierFlags)
        guard modifiers.containsAnyActivationModifier,
              let keyEquivalent = keyEquivalent(for: UInt16(event.keyCode), event: event) else {
            return nil
        }
        return AppShotKeyboardShortcut(
            keyCode: UInt16(event.keyCode),
            modifiers: modifiers,
            keyEquivalent: keyEquivalent
        )
    }

    static func validationMessage(
        for shortcut: AppShotKeyboardShortcut,
        currentShortcut: AppShotKeyboardShortcut
    ) -> String? {
        guard case .keyChord = shortcut.kind,
              let keyChord = shortcut.keyChord else {
            return nil
        }
        if knownSystemShortcutNames[keyChord] != nil || SystemKeyboardShortcutStore.hasEnabledShortcut(matching: keyChord) {
            return "\(shortcut.displayString) conflicts with a macOS keyboard shortcut."
        }
        if shortcut.modifierCount < 2 {
            return "Use at least two modifier keys."
        }
        if let conflict = reservedShortcutNames[keyChord] {
            return "\(shortcut.displayString) is already used by \(conflict)."
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

    private static func keyEquivalent(for keyCode: UInt16, event: NSEvent) -> String? {
        if let symbol = specialKeySymbols[keyCode] {
            return symbol
        }
        guard let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
              !characters.isEmpty else {
            return nil
        }
        return characters.uppercased()
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

struct AppShotKeyboardShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt8

    static let command = AppShotKeyboardShortcutModifiers(rawValue: 1 << 0)
    static let control = AppShotKeyboardShortcutModifiers(rawValue: 1 << 1)
    static let option = AppShotKeyboardShortcutModifiers(rawValue: 1 << 2)
    static let shift = AppShotKeyboardShortcutModifiers(rawValue: 1 << 3)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(_ flags: NSEvent.ModifierFlags) {
        var result = AppShotKeyboardShortcutModifiers()
        let normalized = flags.intersection(.deviceIndependentFlagsMask)
        if normalized.contains(.command) { result.insert(.command) }
        if normalized.contains(.control) { result.insert(.control) }
        if normalized.contains(.option) { result.insert(.option) }
        if normalized.contains(.shift) { result.insert(.shift) }
        self = result
    }

    var containsAnyActivationModifier: Bool {
        contains(.command) || contains(.control) || contains(.option)
    }

    var count: Int {
        var result = 0
        if contains(.command) { result += 1 }
        if contains(.control) { result += 1 }
        if contains(.option) { result += 1 }
        if contains(.shift) { result += 1 }
        return result
    }

    var normalized: AppShotKeyboardShortcutModifiers {
        intersection([.command, .control, .option, .shift])
    }

    var displayPrefix: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    var carbonFlags: UInt32 {
        var result: UInt32 = 0
        if contains(.command) { result |= UInt32(cmdKey) }
        if contains(.control) { result |= UInt32(controlKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

private let appShotValidationHotKeySignature = OSType(0x41505648) // APVH
private let appShotValidationHotKeyID: UInt32 = 1

private let specialKeySymbols: [UInt16: String] = [
    UInt16(kVK_Return): "↩",
    UInt16(kVK_Tab): "⇥",
    UInt16(kVK_Space): "␣",
    UInt16(kVK_Delete): "⌫",
    UInt16(kVK_Escape): "⎋",
    UInt16(kVK_Command): "⌘",
    UInt16(kVK_Shift): "⇧",
    UInt16(kVK_CapsLock): "⇪",
    UInt16(kVK_Option): "⌥",
    UInt16(kVK_Control): "⌃",
    UInt16(kVK_RightCommand): "⌘",
    UInt16(kVK_RightShift): "⇧",
    UInt16(kVK_RightOption): "⌥",
    UInt16(kVK_RightControl): "⌃",
    UInt16(kVK_F1): "F1",
    UInt16(kVK_F2): "F2",
    UInt16(kVK_F3): "F3",
    UInt16(kVK_F4): "F4",
    UInt16(kVK_F5): "F5",
    UInt16(kVK_F6): "F6",
    UInt16(kVK_F7): "F7",
    UInt16(kVK_F8): "F8",
    UInt16(kVK_F9): "F9",
    UInt16(kVK_F10): "F10",
    UInt16(kVK_F11): "F11",
    UInt16(kVK_F12): "F12",
    UInt16(kVK_Home): "↖",
    UInt16(kVK_PageUp): "⇞",
    UInt16(kVK_ForwardDelete): "⌦",
    UInt16(kVK_End): "↘",
    UInt16(kVK_PageDown): "⇟",
    UInt16(kVK_LeftArrow): "←",
    UInt16(kVK_RightArrow): "→",
    UInt16(kVK_DownArrow): "↓",
    UInt16(kVK_UpArrow): "↑"
]

private let knownSystemShortcutNames: [AppShotKeyboardShortcut.KeyChord: String] = [
    .init(keyCode: UInt16(kVK_Space), modifiers: [.command], keyEquivalent: "␣"): "Spotlight",
    .init(keyCode: UInt16(kVK_Space), modifiers: [.command, .option], keyEquivalent: "␣"): "Finder search",
    .init(keyCode: UInt16(kVK_Space), modifiers: [.command, .control], keyEquivalent: "␣"): "Character Viewer",
    .init(keyCode: UInt16(kVK_Tab), modifiers: [.command], keyEquivalent: "⇥"): "application switcher",
    .init(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift], keyEquivalent: "⇥"): "application switcher",
    .init(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.command], keyEquivalent: "`"): "window switcher",
    .init(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.command, .shift], keyEquivalent: "`"): "window switcher",
    .init(keyCode: UInt16(kVK_Escape), modifiers: [.command, .option], keyEquivalent: "⎋"): "Force Quit",
    .init(keyCode: UInt16(kVK_Escape), modifiers: [.command, .option, .shift], keyEquivalent: "⎋"): "Force Quit",
    .init(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command, .control], keyEquivalent: "Q"): "screen lock",
    .init(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command, .shift], keyEquivalent: "Q"): "log out",
    .init(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command, .option, .shift], keyEquivalent: "Q"): "log out immediately",
    .init(keyCode: UInt16(kVK_ANSI_D), modifiers: [.command, .option], keyEquivalent: "D"): "Dock hide/show",
    .init(keyCode: UInt16(kVK_ANSI_3), modifiers: [.command, .shift], keyEquivalent: "3"): "screenshot",
    .init(keyCode: UInt16(kVK_ANSI_4), modifiers: [.command, .shift], keyEquivalent: "4"): "screenshot",
    .init(keyCode: UInt16(kVK_ANSI_5), modifiers: [.command, .shift], keyEquivalent: "5"): "screenshot",
    .init(keyCode: UInt16(kVK_ANSI_3), modifiers: [.command, .control, .shift], keyEquivalent: "3"): "screenshot to clipboard",
    .init(keyCode: UInt16(kVK_ANSI_4), modifiers: [.command, .control, .shift], keyEquivalent: "4"): "screenshot to clipboard",
    .init(keyCode: UInt16(kVK_ANSI_5), modifiers: [.command, .control, .shift], keyEquivalent: "5"): "screenshot to clipboard"
]

private let reservedShortcutNames: [AppShotKeyboardShortcut.KeyChord: String] = [
    .init(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command], keyEquivalent: "Q"): "Quit",
    .init(keyCode: UInt16(kVK_ANSI_H), modifiers: [.command], keyEquivalent: "H"): "Hide",
    .init(keyCode: UInt16(kVK_ANSI_M), modifiers: [.command], keyEquivalent: "M"): "Minimize",
    .init(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command], keyEquivalent: "A"): "Select All",
    .init(keyCode: UInt16(kVK_ANSI_C), modifiers: [.command], keyEquivalent: "C"): "Copy",
    .init(keyCode: UInt16(kVK_ANSI_X), modifiers: [.command], keyEquivalent: "X"): "Cut",
    .init(keyCode: UInt16(kVK_ANSI_V), modifiers: [.command], keyEquivalent: "V"): "Paste",
    .init(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.command], keyEquivalent: "Z"): "Undo",
    .init(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.command, .shift], keyEquivalent: "Z"): "Redo",
    .init(keyCode: UInt16(kVK_ANSI_S), modifiers: [.command], keyEquivalent: "S"): "Save",
    .init(keyCode: UInt16(kVK_ANSI_S), modifiers: [.command, .shift], keyEquivalent: "S"): "Save As",
    .init(keyCode: UInt16(kVK_ANSI_P), modifiers: [.command], keyEquivalent: "P"): "Print",
    .init(keyCode: UInt16(kVK_ANSI_F), modifiers: [.command], keyEquivalent: "F"): "Find",
    .init(keyCode: UInt16(kVK_ANSI_O), modifiers: [.command], keyEquivalent: "O"): "Add Project",
    .init(keyCode: UInt16(kVK_ANSI_N), modifiers: [.command], keyEquivalent: "N"): "New Thread",
    .init(keyCode: UInt16(kVK_ANSI_T), modifiers: [.command], keyEquivalent: "T"): "New Conversation",
    .init(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command], keyEquivalent: "W"): "Close Conversation",
    .init(keyCode: UInt16(kVK_ANSI_Comma), modifiers: [.command], keyEquivalent: ","): "Settings",
    .init(keyCode: UInt16(kVK_ANSI_D), modifiers: [.command, .shift], keyEquivalent: "D"): "Toggle Diff Viewer",
    .init(keyCode: UInt16(kVK_ANSI_T), modifiers: [.command, .shift], keyEquivalent: "T"): "Toggle Terminal",
    .init(keyCode: UInt16(kVK_ANSI_1), modifiers: [.command], keyEquivalent: "1"): "Conversation Tab 1",
    .init(keyCode: UInt16(kVK_ANSI_2), modifiers: [.command], keyEquivalent: "2"): "Conversation Tab 2",
    .init(keyCode: UInt16(kVK_ANSI_3), modifiers: [.command], keyEquivalent: "3"): "Conversation Tab 3",
    .init(keyCode: UInt16(kVK_ANSI_4), modifiers: [.command], keyEquivalent: "4"): "Conversation Tab 4",
    .init(keyCode: UInt16(kVK_ANSI_5), modifiers: [.command], keyEquivalent: "5"): "Conversation Tab 5",
    .init(keyCode: UInt16(kVK_ANSI_6), modifiers: [.command], keyEquivalent: "6"): "Conversation Tab 6",
    .init(keyCode: UInt16(kVK_ANSI_7), modifiers: [.command], keyEquivalent: "7"): "Conversation Tab 7",
    .init(keyCode: UInt16(kVK_ANSI_8), modifiers: [.command], keyEquivalent: "8"): "Conversation Tab 8",
    .init(keyCode: UInt16(kVK_ANSI_9), modifiers: [.command], keyEquivalent: "9"): "Conversation Tab 9"
]

private enum SystemKeyboardShortcutStore {
    static func hasEnabledShortcut(matching keyChord: AppShotKeyboardShortcut.KeyChord) -> Bool {
        guard let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let hotKeys = domain["AppleSymbolicHotKeys"] as? [String: Any] else {
            return false
        }

        return hotKeys.values.contains { value in
            guard let dictionary = value as? [String: Any],
                  boolValue(dictionary["enabled"]) == true,
                  let shortcutValue = dictionary["value"] as? [String: Any],
                  let parameters = shortcutValue["parameters"] as? [Any],
                  parameters.count >= 3,
                  let keyCode = uint16Value(parameters[1]),
                  let modifierRawValue = uintValue(parameters[2]) else {
                return false
            }
            let modifiers = AppShotKeyboardShortcutModifiers(NSEvent.ModifierFlags(rawValue: modifierRawValue)).normalized
            return keyCode == keyChord.keyCode && modifiers == keyChord.modifiers
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        return (value as? NSNumber)?.boolValue
    }

    private static func uint16Value(_ value: Any?) -> UInt16? {
        guard let value = uintValue(value),
              value <= UInt(UInt16.max) else {
            return nil
        }
        return UInt16(value)
    }

    private static func uintValue(_ value: Any?) -> UInt? {
        if let value = value as? UInt {
            return value
        }
        if let value = value as? Int {
            return value >= 0 ? UInt(value) : nil
        }
        return (value as? NSNumber)?.uintValue
    }
}
