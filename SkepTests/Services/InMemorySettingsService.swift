import Observation

@testable import Skep

@MainActor
@Observable
final class InMemorySettingsService: SettingsService {
    private(set) var current: AppSettings

    init(current: AppSettings = AppSettings()) {
        self.current = current.normalized()
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        transform(&current)
        current = current.normalized()
    }
}
