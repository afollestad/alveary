

import AgentCLIKit
import Foundation
import NeedleFoundation
import SwiftData

// swiftlint:disable unused_declaration
private let needleDependenciesHash : String? = nil

// MARK: - Traversal Helpers

private func parent1(_ component: NeedleFoundation.Scope) -> NeedleFoundation.Scope {
    return component.parent
}

// MARK: - Providers

#if !NEEDLE_DYNAMIC


#else
extension NotificationComponent: NeedleFoundation.Registration {
    public func registerItems() {

    }
}
extension DetectionComponent: NeedleFoundation.Registration {
    public func registerItems() {

    }
}
extension PowerComponent: NeedleFoundation.Registration {
    public func registerItems() {

    }
}
extension AgentComponent: NeedleFoundation.Registration {
    public func registerItems() {

    }
}
extension GitComponent: NeedleFoundation.Registration {
    public func registerItems() {

    }
}
extension GitHubComponent: NeedleFoundation.Registration {
    public func registerItems() {

    }
}
extension SkillsComponent: NeedleFoundation.Registration {
    public func registerItems() {

    }
}
extension MCPComponent: NeedleFoundation.Registration {
    public func registerItems() {

    }
}
extension AppComponent: NeedleFoundation.Registration {
    public func registerItems() {


    }
}
extension DataComponent: NeedleFoundation.Registration {
    public func registerItems() {

    }
}
extension SettingsComponent: NeedleFoundation.Registration {
    public func registerItems() {

    }
}
extension ShellComponent: NeedleFoundation.Registration {
    public func registerItems() {

    }
}
extension SessionComponent: NeedleFoundation.Registration {
    public func registerItems() {

    }
}


#endif

private func factoryEmptyDependencyProvider(_ component: NeedleFoundation.Scope) -> AnyObject {
    return EmptyDependencyProvider(component: component)
}

// MARK: - Registration
private func registerProviderFactory(_ componentPath: String, _ factory: @escaping (NeedleFoundation.Scope) -> AnyObject) {
    __DependencyProviderRegistry.instance.registerDependencyProviderFactory(for: componentPath, factory)
}

#if !NEEDLE_DYNAMIC

@inline(never) private func register1() {
    registerProviderFactory("^->AppComponent->NotificationComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->DetectionComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->PowerComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->AgentComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->GitComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->GitHubComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->SkillsComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->MCPComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->DataComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->DataComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->SettingsComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->ShellComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->SessionComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->SessionComponent", factoryEmptyDependencyProvider)
    registerProviderFactory("^->AppComponent->SessionComponent", factoryEmptyDependencyProvider)
}
#endif

public func registerProviderFactories() {
#if !NEEDLE_DYNAMIC
    register1()
#endif
}
