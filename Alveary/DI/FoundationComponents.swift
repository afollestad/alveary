import Foundation
import NeedleFoundation

final class SettingsComponent: Component<EmptyDependency> {}

final class ShellComponent: Component<EmptyDependency> {}

final class SessionComponent: Component<EmptyDependency> {
    static var appSupportDirectory: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL.appendingPathComponent("com.afollestad.alveary", isDirectory: true)
    }

    static var agentCLIKitSupportDirectory: URL {
        appSupportDirectory.appendingPathComponent("AgentCLIKit", isDirectory: true)
    }
}
