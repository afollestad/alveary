import Knit

@MainActor
enum AppDI {
    static let assembler = ScopedModuleAssembler<Resolver>([
        AppAssembly(),
        DataAssembly(),
        SettingsAssembly(),
        ShellAssembly(),
        NotificationAssembly(),
        DetectionAssembly(),
        AgentAssembly(),
        SessionAssembly(),
        GitAssembly(),
        GitHubAssembly()
    ])

    static let resolver = assembler.resolver
}
