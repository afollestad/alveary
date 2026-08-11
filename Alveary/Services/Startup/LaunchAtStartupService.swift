import ServiceManagement

/// Alveary's macOS login-item registration.
///
/// macOS owns this state — the user can switch the item off in System Settings > General >
/// Login Items without the app running — so nothing mirrors it into `AppSettings`. Callers read
/// the registration back after every write instead of trusting a copy of their own.
@MainActor
protocol LaunchAtStartupService {
    var status: LaunchAtStartupStatus { get }
    func setEnabled(_ isEnabled: Bool) throws
}

enum LaunchAtStartupStatus: Sendable, Equatable {
    /// Registered and allowed to launch.
    case enabled
    /// Not registered.
    case disabled
    /// Registered, but switched off in System Settings; only the user can turn it back on.
    case requiresApproval

    var isEnabled: Bool {
        self == .enabled
    }
}

@MainActor
struct DefaultLaunchAtStartupService: LaunchAtStartupService {
    private let appService: SMAppService

    init(appService: SMAppService = .mainApp) {
        self.appService = appService
    }

    var status: LaunchAtStartupStatus {
        switch appService.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        default:
            return .disabled
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        guard isEnabled else {
            // `unregister()` fails when nothing is registered, and "already off" is not a failure
            // worth showing the user.
            guard status != .disabled else {
                return
            }
            try appService.unregister()
            return
        }
        try appService.register()
    }
}

/// The default everywhere the real service is not injected, so a test or preview can never add
/// its own build to the developer's login items. Production injects the real one in
/// `ContentView+Factories.makeSettingsViewModel(dependencies:)`.
@MainActor
struct InertLaunchAtStartupService: LaunchAtStartupService {
    var status: LaunchAtStartupStatus {
        .disabled
    }

    func setEnabled(_ isEnabled: Bool) throws {}
}
