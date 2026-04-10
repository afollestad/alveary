import Knit

final class GitHubAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] {
        [ShellAssembly.self]
    }

    @MainActor
    func assemble(container: Container<Resolver>) {
        container.register(GitHubCLIService.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            return DefaultGitHubCLIService(
                shell: unsafeResolver.resolve(ShellRunner.self) ?? {
                    fatalError("ShellRunner was not registered before GitHubCLIService")
                }()
            )
        }
        .inObjectScope(.container)

        container.register(GitHubService.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            return CLIGitHubService(
                ghCLI: unsafeResolver.resolve(GitHubCLIService.self) ?? {
                    fatalError("GitHubCLIService was not registered before GitHubService")
                }()
            )
        }
        .inObjectScope(.container)
    }
}
