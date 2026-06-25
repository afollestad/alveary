@preconcurrency import AppKit
import SwiftUI

struct AppShotsSettingsTabView: View {
    @Binding var appShotsEnabled: Bool
    @Binding var appShotShortcut: AppShotKeyboardShortcut
    @State private var permissionSnapshot: AppShotPermissionSnapshot

    private let refreshesLivePermissions: Bool

    init(
        appShotsEnabled: Binding<Bool>,
        appShotShortcut: Binding<AppShotKeyboardShortcut>,
        accessibilityAllowed: Bool? = nil,
        keyboardMonitoringAllowed: Bool? = nil,
        screenRecordingAllowed: Bool? = nil
    ) {
        _appShotsEnabled = appShotsEnabled
        _appShotShortcut = appShotShortcut
        _permissionSnapshot = State(
            initialValue: AppShotPermissionSnapshot.makeCurrent(
                accessibilityAllowed: accessibilityAllowed,
                inputMonitoringAllowed: keyboardMonitoringAllowed,
                screenRecordingAllowed: screenRecordingAllowed
            )
        )
        refreshesLivePermissions = accessibilityAllowed == nil &&
            keyboardMonitoringAllowed == nil &&
            screenRecordingAllowed == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection("Capture") {
                SettingsToggleRow(
                    "Enable app shots",
                    helpText: AppShotsSettingsHelp.enabled,
                    isOn: $appShotsEnabled
                )

                SettingsFormRow(showsDivider: false) {
                    SettingsResponsiveControlRow(
                        "Shortcut",
                        helpText: AppShotsSettingsHelp.shortcut,
                        horizontalControlSizing: .fillsAvailableWidthFraction(0.62)
                    ) {
                        AppShotShortcutRecorder(
                            shortcut: $appShotShortcut
                        )
                    }
                }
            }

            SettingsFormSection("Permissions") {
                AppShotPermissionRow(
                    presentation: permissionPresentation(for: .accessibility),
                    request: { requestPermission(.accessibility, sourceFrameInScreen: $0) }
                )

                AppShotPermissionRow(
                    presentation: inputMonitoringPresentation,
                    request: { requestPermission(.inputMonitoring, sourceFrameInScreen: $0) }
                )

                AppShotPermissionRow(
                    presentation: permissionPresentation(for: .screenRecording),
                    request: { requestPermission(.screenRecording, sourceFrameInScreen: $0) },
                    showsDivider: false
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            refreshPermissions()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            refreshPermissions()
        }
    }

    private var inputMonitoringPresentation: AppShotPermissionRowPresentation {
        guard appShotShortcut == .bothCommand else {
            return AppShotPermissionRowPresentation(
                title: AppShotPermission.inputMonitoring.title,
                value: "Not needed for current shortcut",
                style: .secondary,
                requestTitle: nil
            )
        }

        return permissionPresentation(
            for: .inputMonitoring,
            missingValue: "Needed for ⌘⌘"
        )
    }

    private func permissionPresentation(
        for permission: AppShotPermission,
        missingValue: String = "Required"
    ) -> AppShotPermissionRowPresentation {
        if permissionSnapshot.isAllowed(permission) {
            return AppShotPermissionRowPresentation(
                title: permission.title,
                value: "Allowed",
                style: .secondary,
                requestTitle: nil
            )
        }

        return AppShotPermissionRowPresentation(
            title: permission.title,
            value: missingValue,
            style: .orange,
            requestTitle: "Allow"
        )
    }

    private func requestPermission(_ permission: AppShotPermission, sourceFrameInScreen: CGRect?) {
        AppShotPermissionDragGrantAssistant.shared.present(
            permission: permission,
            sourceFrameInScreen: sourceFrameInScreen
        )
        refreshPermissions()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            refreshPermissions()
        }
    }

    private func refreshPermissions() {
        guard refreshesLivePermissions else {
            return
        }
        permissionSnapshot = .current
    }
}

private struct AppShotPermissionRow: View {
    let presentation: AppShotPermissionRowPresentation
    let request: (CGRect?) -> Void
    var showsDivider = true

    @State private var requestFrameInScreen = CGRect.zero

    var body: some View {
        SettingsFormRow(showsDivider: showsDivider) {
            SettingsResponsiveControlRow(presentation.title, horizontalControlSizing: .intrinsicInline) {
                HStack(spacing: 8) {
                    Text(presentation.value)
                        .foregroundStyle(presentation.style)
                        .lineLimit(1)

                    if let requestTitle = presentation.requestTitle {
                        Button(requestTitle) {
                            request(requestFrameInScreen.isEmpty ? nil : requestFrameInScreen)
                        }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Allow \(presentation.title)")
                            .background(AppShotPermissionRequestFrameReader(frameInScreen: $requestFrameInScreen))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

private struct AppShotPermissionRowPresentation: Equatable {
    let title: String
    let value: String
    let style: Color
    let requestTitle: String?
}

private struct AppShotPermissionRequestFrameReader: NSViewRepresentable {
    @Binding var frameInScreen: CGRect

    func makeNSView(context: Context) -> AppShotPermissionFrameView {
        let view = AppShotPermissionFrameView()
        view.onFrameChange = { frame in
            frameInScreen = frame
        }
        return view
    }

    func updateNSView(_ nsView: AppShotPermissionFrameView, context: Context) {
        nsView.onFrameChange = { frame in
            frameInScreen = frame
        }
        nsView.updateFrameInScreen()
    }
}

private final class AppShotPermissionFrameView: NSView {
    var onFrameChange: ((CGRect) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateFrameInScreen()
    }

    override func layout() {
        super.layout()
        updateFrameInScreen()
    }

    func updateFrameInScreen() {
        guard let window else {
            return
        }
        onFrameChange?(window.convertToScreen(convert(bounds, to: nil)))
    }
}

private enum AppShotsSettingsHelp {
    static let enabled = "When enabled, Alveary can capture the last focused non-Alveary window and stage it in the selected conversation."
    static let shortcut = "Click the shortcut button to record a regular key chord, or restore the default shortcut. " +
        "Alveary rejects known conflicting shortcuts when macOS exposes the conflict."
}
