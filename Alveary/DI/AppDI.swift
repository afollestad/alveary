@MainActor
enum AppDI {
    static let component: AppComponent = {
        registerNeedleProviders()
        return AppComponent()
    }()

    static func makeTestComponent(isStoredInMemoryOnly: Bool) -> AppComponent {
        registerNeedleProviders()
        return AppComponent(isStoredInMemoryOnly: isStoredInMemoryOnly)
    }

    private static func registerNeedleProviders() {
        _ = providerRegistration
    }

    private static let providerRegistration: Void = {
        registerProviderFactories()
    }()
}
