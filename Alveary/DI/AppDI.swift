@MainActor
enum AppDI {
    static let component: AppComponent = {
        registerNeedleProviders()
        return AppComponent(storageProfile: AppRuntimeProfile.current.storageProfile)
    }()

    static func makeTestComponent(
        isStoredInMemoryOnly: Bool,
        storageProfile: AppStorageProfile? = nil
    ) -> AppComponent {
        registerNeedleProviders()
        return AppComponent(
            storageProfile: storageProfile ?? AppRuntimeProfile.current.storageProfile,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
    }

    private static func registerNeedleProviders() {
        _ = providerRegistration
    }

    private static let providerRegistration: Void = {
        registerProviderFactories()
    }()
}
