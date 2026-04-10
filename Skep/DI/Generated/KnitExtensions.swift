// Generated using Knit
// Do not edit directly!

import Foundation
import Knit
import SwiftData

// The correct resolution of each of these types is enforced by a matching automated unit test
// If a type registration is missing or broken then the automated tests will fail for that PR
/// Generated from ``NotificationAssembly``
extension Resolver {
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
