import Foundation
import NeedleFoundation

final class SettingsComponent: Component<EmptyDependency> {}

final class ShellComponent: Component<EmptyDependency> {}

final class SessionComponent: Component<EmptyDependency> {
    static var appSupportDirectory: URL {
        AppRuntimeProfile.current.storageProfile.appSupportDirectory
    }

    static var agentCLIKitSupportDirectory: URL {
        AppRuntimeProfile.current.storageProfile.agentCLIKitSupportDirectory
    }
}
