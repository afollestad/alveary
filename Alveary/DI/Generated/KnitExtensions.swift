// Generated using Knit
// Do not edit directly!

import Foundation
import Knit
import SwiftData

// The correct resolution of each of these types is enforced by a matching automated unit test
// If a type registration is missing or broken then the automated tests will fail for that PR
/// Generated from ``NotificationAssembly``
extension Resolver {
    func notificationRouter(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> NotificationRouter {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(NotificationRouter.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func notificationManager(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> NotificationManager {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(NotificationManager.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
}
extension NotificationAssembly {
    public static var _assemblyFlags: [ModuleAssemblyFlags] {
        [.autoInit]
    }
    public static func _autoInstantiate() -> (any ModuleAssembly)? {
        NotificationAssembly()
    }
}
/// Generated from ``DataAssembly``
extension Resolver {
    func modelContainer(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> ModelContainer {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(ModelContainer.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func modelContext(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> ModelContext {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(ModelContext.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
}
extension DataAssembly {
    public static var _assemblyFlags: [ModuleAssemblyFlags] {
        [.autoInit]
    }
    public static func _autoInstantiate() -> (any ModuleAssembly)? {
        DataAssembly()
    }
}
/// Generated from ``AgentAssembly``
extension Resolver {
    func agentEnvironmentBuilder(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> AgentEnvironmentBuilder {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(AgentEnvironmentBuilder.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func claudeConfigStore(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> ClaudeConfigStore {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(ClaudeConfigStore.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func providerSetupService(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> ProviderSetupService {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(ProviderSetupService.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func contextWindowCache(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> ContextWindowCache {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(ContextWindowCache.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func claudeHookServer(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> ClaudeHookServer {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(ClaudeHookServer.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func defaultAgentsManager(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> DefaultAgentsManager {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(DefaultAgentsManager.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func agentsManager(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> AgentsManager {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(AgentsManager.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func conversationRuntimeStore(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> ConversationRuntimeStore {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(ConversationRuntimeStore.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
}
extension AgentAssembly {
    public static var _assemblyFlags: [ModuleAssemblyFlags] {
        [.autoInit]
    }
    public static func _autoInstantiate() -> (any ModuleAssembly)? {
        AgentAssembly()
    }
}
/// Generated from ``GitHubAssembly``
extension Resolver {
    func gitHubCLIService(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> GitHubCLIService {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(GitHubCLIService.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func gitHubService(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> GitHubService {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(GitHubService.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
}
extension GitHubAssembly {
    public static var _assemblyFlags: [ModuleAssemblyFlags] {
        [.autoInit]
    }
    public static func _autoInstantiate() -> (any ModuleAssembly)? {
        GitHubAssembly()
    }
}
/// Generated from ``GitAssembly``
extension Resolver {
    func gitService(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> GitService {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(GitService.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func worktreeManager(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> WorktreeManager {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(WorktreeManager.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func fileListManager(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> FileListManager {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(FileListManager.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func diffWorkspaceStore(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> DiffWorkspaceStore {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(DiffWorkspaceStore.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
}
extension GitAssembly {
    public static var _assemblyFlags: [ModuleAssemblyFlags] {
        [.autoInit]
    }
    public static func _autoInstantiate() -> (any ModuleAssembly)? {
        GitAssembly()
    }
}
/// Generated from ``DetectionAssembly``
extension Resolver {
    func agentRegistry(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> AgentRegistry {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(AgentRegistry.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func providerRegistry(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> ProviderRegistry {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(ProviderRegistry.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
    func providerDetectionService(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> ProviderDetectionService {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(ProviderDetectionService.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
}
extension DetectionAssembly {
    public static var _assemblyFlags: [ModuleAssemblyFlags] {
        [.autoInit]
    }
    public static func _autoInstantiate() -> (any ModuleAssembly)? {
        DetectionAssembly()
    }
}
/// Generated from ``SkillsAssembly``
extension Resolver {
    func skillsService(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> SkillsService {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(SkillsService.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
}
extension SkillsAssembly {
    public static var _assemblyFlags: [ModuleAssemblyFlags] {
        [.autoInit]
    }
    public static func _autoInstantiate() -> (any ModuleAssembly)? {
        SkillsAssembly()
    }
}
/// Generated from ``SettingsAssembly``
extension Resolver {
    func settingsService(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> SettingsService {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(SettingsService.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
}
extension SettingsAssembly {
    public static var _assemblyFlags: [ModuleAssemblyFlags] {
        [.autoInit]
    }
    public static func _autoInstantiate() -> (any ModuleAssembly)? {
        SettingsAssembly()
    }
}
/// Generated from ``SessionAssembly``
extension Resolver {
    func sessionManager(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> SessionManager {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(SessionManager.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
}
extension SessionAssembly {
    public static var _assemblyFlags: [ModuleAssemblyFlags] {
        [.autoInit]
    }
    public static func _autoInstantiate() -> (any ModuleAssembly)? {
        SessionAssembly()
    }
}
/// Generated from ``AppAssembly``
extension Resolver {
}
extension AppAssembly {
    public static var _assemblyFlags: [ModuleAssemblyFlags] {
        [.autoInit]
    }
    public static func _autoInstantiate() -> (any ModuleAssembly)? {
        AppAssembly()
    }
}
/// Generated from ``PowerAssembly``
extension Resolver {
    func keepAwakeService(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> KeepAwakeService {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(KeepAwakeService.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
}
extension PowerAssembly {
    public static var _assemblyFlags: [ModuleAssemblyFlags] {
        [.autoInit]
    }
    public static func _autoInstantiate() -> (any ModuleAssembly)? {
        PowerAssembly()
    }
}
/// Generated from ``ShellAssembly``
extension Resolver {
    func shellRunner(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> ShellRunner {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(ShellRunner.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
}
extension ShellAssembly {
    public static var _assemblyFlags: [ModuleAssemblyFlags] {
        [.autoInit]
    }
    public static func _autoInstantiate() -> (any ModuleAssembly)? {
        ShellAssembly()
    }
}
/// Generated from ``MCPAssembly``
extension Resolver {
    func mcpService(file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) -> MCPService {
        let resolver = unsafeResolver(file: file, function: function, line: line)
        return knitUnwrap(resolver.resolve(MCPService.self), callsiteFile: file, callsiteFunction: function, callsiteLine: line)
    }
}
extension MCPAssembly {
    public static var _assemblyFlags: [ModuleAssemblyFlags] {
        [.autoInit]
    }
    public static func _autoInstantiate() -> (any ModuleAssembly)? {
        MCPAssembly()
    }
}
