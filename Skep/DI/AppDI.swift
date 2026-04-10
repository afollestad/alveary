import Knit

@MainActor
enum AppDI {
    static let assembler = ScopedModuleAssembler<Resolver>([
        AppAssembly(),
        DataAssembly()
    ])

    static let resolver = assembler.resolver
}
