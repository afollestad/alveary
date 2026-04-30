import Foundation
import Observation

@MainActor
@Observable
final class UserDefaultsSettingsService: SettingsService {
    static let storageKey = "appSettings"

    private let defaults: UserDefaults
    private let encode: @Sendable (AppSettings) throws -> Data
    private(set) var current: AppSettings

    init(
        defaults: UserDefaults = .standard,
        encode: @escaping @Sendable (AppSettings) throws -> Data = { try JSONEncoder().encode($0) }
    ) {
        self.defaults = defaults
        self.encode = encode

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            current = decoded.normalized()
        } else {
            current = AppSettings()
        }
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        var updated = current
        transform(&updated)
        updated = updated.normalized()

        do {
            let data = try encode(updated)
            defaults.set(data, forKey: Self.storageKey)
            current = updated
            NotificationCenter.default.post(name: .appSettingsChanged, object: self)
        } catch {
            print("[SettingsService] Failed to persist app settings: \(error)")
        }
    }
}
