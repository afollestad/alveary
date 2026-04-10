@MainActor
protocol SettingsService: AnyObject {
    var current: AppSettings { get }
    func update(_ transform: (inout AppSettings) -> Void)
}
