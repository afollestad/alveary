import Knit

final class GitAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] {
        [SettingsAssembly.self, ShellAssembly.self]
    }

    @MainActor
    func assemble(container: Container<Resolver>) {
        container.register(GitService.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            return CLIGitService(
                shell: unsafeResolver.resolve(ShellRunner.self) ?? {
                    fatalError("ShellRunner was not registered before GitService")
                }()
            )
        }
        .inObjectScope(.container)

        container.register(WorktreeManager.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            return DefaultWorktreeManager(
                settingsService: unsafeResolver.resolve(SettingsService.self) ?? {
                    fatalError("SettingsService was not registered before WorktreeManager")
                }(),
                shell: unsafeResolver.resolve(ShellRunner.self) ?? {
                    fatalError("ShellRunner was not registered before WorktreeManager")
                }()
            )
        }
        .inObjectScope(.container)

        container.register(FileListManager.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            return GitFileListManager(
                gitService: unsafeResolver.resolve(GitService.self) ?? {
                    fatalError("GitService was not registered before FileListManager")
                }()
            )
        }
        .inObjectScope(.container)

        container.register(DiffWorkspaceStore.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            return DiffWorkspaceStore(
                gitService: unsafeResolver.resolve(GitService.self) ?? {
                    fatalError("GitService was not registered before DiffWorkspaceStore")
                }()
            )
        }
        .inObjectScope(.container)
    }
}
