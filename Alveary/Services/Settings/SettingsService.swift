@MainActor
protocol SettingsService: AnyObject, Sendable {
    var current: AppSettings { get }
    func update(_ transform: (inout AppSettings) -> Void)
}
