import Foundation

/// Escapes colliding or trim-sensitive native names so generic settings normalization cannot change variant identity.
extension AppSettings {
    static let openCodeDefaultEffort = "alveary.opencode.configured"
    private static let openCodeVariantEscapePrefix = "alveary.opencode.variant:"

    static func openCodeStoredEffort(nativeVariant: String) -> String {
        if nativeVariant == openCodeDefaultEffort || nativeVariant == inheritedSelectionValue || nativeVariant.hasPrefix(openCodeVariantEscapePrefix)
            || nativeVariant.isEmpty || nativeVariant.trimmingCharacters(in: .whitespacesAndNewlines) != nativeVariant {
            return openCodeVariantEscapePrefix + Data(nativeVariant.utf8).base64EncodedString()
        }
        return nativeVariant
    }

    /// Older raw saved variants must match escaped menu identities without rewriting the saved selection during rendering.
    static func openCodePickerEffort(stored: String) -> String {
        openCodeNativeEffort(stored: stored).map(openCodeStoredEffort) ?? openCodeDefaultEffort
    }

    /// Unknown native values survive decoding so execution validation can reject them without silently changing the request.
    static func openCodeNativeEffort(stored: String?) -> String? {
        guard let stored, !stored.isEmpty, stored != openCodeDefaultEffort else { return nil }
        if stored.hasPrefix(openCodeVariantEscapePrefix),
           let data = Data(base64Encoded: String(stored.dropFirst(openCodeVariantEscapePrefix.count))),
           let variant = String(data: data, encoding: .utf8) {
            return variant
        }
        return stored
    }
}
