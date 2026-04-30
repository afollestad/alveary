import Foundation

@MainActor
protocol SettingsService: AnyObject, Sendable {
    var current: AppSettings { get }
    func update(_ transform: (inout AppSettings) -> Void)
}

extension Notification.Name {
    static let appSettingsChanged = Notification.Name("appSettingsChanged")
}
