import Knit

@MainActor
enum AppDI {
    static let assembler = ScopedModuleAssembler<Resolver>([
        AppAssembly(),
        DataAssembly(),
        SettingsAssembly(),
        ShellAssembly(),
        NotificationAssembly()
    ])

    static let resolver = assembler.resolver
}
