// Generated using Knit
// Do not edit directly!

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
