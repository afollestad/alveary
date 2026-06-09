import Foundation
import Observation

@testable import Alveary

@MainActor
@Observable
final class InMemorySettingsService: SettingsService {
    private(set) var current: AppSettings
    private(set) var updateCount = 0

    init(current: AppSettings = AppSettings()) {
        self.current = current.normalized()
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        updateCount += 1
        transform(&current)
        current = current.normalized()
        NotificationCenter.default.post(name: .appSettingsChanged, object: self)
    }
}
