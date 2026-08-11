@preconcurrency import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import Observation

struct PreparedAppShotCapture: Equatable, Sendable {
    let appName: String
    let bundleIdentifier: String
    let windowTitle: String
    let screenshotPNGData: Data
    let axTreeText: String
    let focusedElementSummary: String

    func store(
        in attachmentStore: any ConversationAttachmentStore,
        conversationId: String
    ) async throws -> AppShotAttachment {
        let screenshot = try await attachmentStore.storeAppShotScreenshot(
            screenshotPNGData,
            conversationId: conversationId,
            label: "Appshot screenshot.png"
        )
        return AppShotAttachment(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            screenshot: screenshot,
            axTreeText: axTreeText,
            focusedElementSummary: focusedElementSummary,
            attachmentStoreRoot: attachmentStore.conversationRootDirectory(conversationId: conversationId)
        )
    }
}

@MainActor
@Observable
final class AppShotCoordinator {
    private let targetTracker: AppShotTargetTracker
    /// The capture shortcut is registered with the *system*, so a second Alveary-hosted process
    /// steals it from the one the developer is using. Hosted test runs pass `false`; everything
    /// else about the coordinator still runs, the same way the status item suppresses only its
    /// chrome (`Alveary/DI/AppComponent+AppShots.swift`).
    private let installsGlobalShortcut: Bool
    private let presentMainWindowIfClosed: @MainActor () -> Void
    private var localKeyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var carbonHotKey: EventHotKeyRef?
    private var carbonHotKeyEventHandler: EventHandlerRef?
    private var modifierEventTap: CFMachPort?
    private var modifierEventTapSource: CFRunLoopSource?
    private var settingsObserver: NSObjectProtocol?
    private var isLeftCommandDown = false
    private var isRightCommandDown = false
    private var didFireBothCommandChord = false
    private var currentSettings = AppShotsRuntimeSettings()

    /// A capture request waiting for `ContentView` to route it, because destination resolution and
    /// staging need `AppState` and the mounted conversation. Non-nil until the root drains it, so
    /// a press taken with the window closed still lands once the window mounts — `.onChange` alone
    /// cannot fire retroactively.
    private(set) var pendingTriggerID: UUID?

    /// The app a capture would target right now, or `nil` when nothing can be attached.
    ///
    /// Observation propagates transitively: `currentSettings` is tracked on this type and
    /// `attachableApp` is tracked on the observable tracker.
    var attachableApp: AppShotAttachableApp? {
        guard currentSettings.enabled else {
            return nil
        }
        return targetTracker.attachableApp
    }

    init(
        targetTracker: AppShotTargetTracker = AppShotTargetTracker(),
        installsGlobalShortcut: Bool = true,
        presentMainWindowIfClosed: @escaping @MainActor () -> Void = {}
    ) {
        self.targetTracker = targetTracker
        self.installsGlobalShortcut = installsGlobalShortcut
        self.presentMainWindowIfClosed = presentMainWindowIfClosed
    }

    /// True while any of the shortcut's monitors are installed. The primary registrations — the
    /// Carbon hot key, the event tap, the global monitor — are system-wide, which is why hosted
    /// runs suppress them; this is how that suppression is asserted rather than taken on faith.
    /// A new monitor belongs here as well as in `removeMonitors()`.
    var hasInstalledShortcutMonitors: Bool {
        carbonHotKey != nil
            || modifierEventTap != nil
            || globalKeyMonitor != nil
            || localKeyMonitor != nil
            || localFlagsMonitor != nil
    }

    /// Requests a capture from UI that is not the global shortcut, such as the composer `+` menu.
    ///
    /// This only raises the pending trigger; `ContentView` remains the sole trigger observer and
    /// destination router.
    func requestCapture() {
        raiseTrigger()
    }

    /// Drops a request the root has acted on. A stale id is a no-op, so a drain racing a fresh
    /// press cannot swallow the newer one.
    func clearPendingTrigger(_ id: UUID) {
        guard pendingTriggerID == id else {
            return
        }
        pendingTriggerID = nil
    }

    private func raiseTrigger() {
        guard currentSettings.enabled else {
            return
        }
        pendingTriggerID = UUID()
        // Only when the scene is closed: routing lives in `ContentView`, so with no window there
        // is nothing to route into. A capture taken while Alveary is merely behind another app
        // must not steal focus, which is why this is not a plain `activate()`.
        presentMainWindowIfClosed()
    }

    func start(settingsService: any SettingsService) {
        targetTracker.start()
        configure(settings: settingsService.current)
        guard settingsObserver == nil else {
            return
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .appSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self, weak settingsService] _ in
            guard let settingsService else {
                return
            }
            Task { @MainActor in
                self?.configure(settings: settingsService.current)
            }
        }
    }

    func stop() {
        removeMonitors()
        targetTracker.stop()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        settingsObserver = nil
    }

    func prepareCapture() async throws -> PreparedAppShotCapture {
        guard currentSettings.enabled else {
            throw AppShotCaptureError.disabled
        }
        guard AppShotPermission.accessibility.isAllowed else {
            throw AppShotCaptureError.accessibilityPermissionMissing
        }
        guard let target = targetTracker.targetForCapture() else {
            throw AppShotCaptureError.noTargetWindow
        }
        let axSnapshot = try AppShotAXTreeFormatter.snapshot(for: target)
        let screenshotPNGData = try await AppShotScreenshotCapturer.captureScreenshotData(for: target)
        return PreparedAppShotCapture(
            appName: target.appName,
            bundleIdentifier: target.bundleIdentifier,
            windowTitle: target.windowTitle,
            screenshotPNGData: screenshotPNGData,
            axTreeText: axSnapshot.treeText,
            focusedElementSummary: axSnapshot.focusedElementSummary
        )
    }

    private func configure(settings: AppSettings) {
        currentSettings = AppShotsRuntimeSettings(
            enabled: settings.appShotsEnabled,
            shortcut: settings.appShotShortcut
        )
        removeMonitors()
        guard currentSettings.enabled, installsGlobalShortcut else {
            return
        }
        installMonitors()
    }

    private func installMonitors() {
        switch currentSettings.shortcut.kind {
        case .keyChord:
            if !installCarbonHotKey(for: currentSettings.shortcut) {
                localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handleKeyDown(event)
                    return event
                }
                globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handleKeyDown(event)
                }
            }
        case .bothCommand:
            if !installModifierEventTap() {
                localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                    self?.handleFlagsChanged(keyCode: event.keyCode, commandIsDown: event.modifierFlags.contains(.command))
                    return event
                }
            }
        }
    }

    private func removeMonitors() {
        [localKeyMonitor, localFlagsMonitor, globalKeyMonitor].forEach { monitor in
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        if let modifierEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), modifierEventTapSource, .commonModes)
        }
        if let modifierEventTap {
            CGEvent.tapEnable(tap: modifierEventTap, enable: false)
        }
        if let carbonHotKey {
            UnregisterEventHotKey(carbonHotKey)
        }
        if let carbonHotKeyEventHandler {
            RemoveEventHandler(carbonHotKeyEventHandler)
        }
        localKeyMonitor = nil
        localFlagsMonitor = nil
        globalKeyMonitor = nil
        carbonHotKey = nil
        carbonHotKeyEventHandler = nil
        modifierEventTap = nil
        modifierEventTapSource = nil
        isLeftCommandDown = false
        isRightCommandDown = false
        didFireBothCommandChord = false
    }

    private func installCarbonHotKey(for shortcut: AppShotKeyboardShortcut) -> Bool {
        guard case .keyChord = shortcut.kind,
              let keyChord = shortcut.keyChord else {
            return false
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var eventHandler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            appShotCarbonHotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            return false
        }

        let hotKeyID = EventHotKeyID(signature: appShotHotKeySignature, id: appShotHotKeyID)
        var hotKey: EventHotKeyRef?
        let registrationStatus = RegisterEventHotKey(
            UInt32(keyChord.keyCode),
            keyChord.modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registrationStatus == noErr, let hotKey else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
            }
            return false
        }

        carbonHotKeyEventHandler = eventHandler
        carbonHotKey = hotKey
        return true
    }

    private func installModifierEventTap() -> Bool {
        guard AppShotPermission.inputMonitoring.isAllowed else {
            return false
        }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: appShotModifierEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CGEvent.tapEnable(tap: tap, enable: false)
            return false
        }
        modifierEventTap = tap
        modifierEventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard currentSettings.shortcut.matches(event: event) else {
            return
        }
        raiseTrigger()
    }

    fileprivate func handleCarbonHotKeyPressed() {
        guard currentSettings.shortcut.kind == .keyChord else {
            return
        }
        raiseTrigger()
    }

    fileprivate func handleFlagsChanged(keyCode: UInt16, commandIsDown: Bool) {
        guard currentSettings.enabled,
              currentSettings.shortcut == .bothCommand else {
            return
        }

        switch keyCode {
        case 54:
            isRightCommandDown = updatedCommandSideState(
                current: isRightCommandDown,
                other: isLeftCommandDown,
                commandIsDown: commandIsDown
            )
        case 55:
            isLeftCommandDown = updatedCommandSideState(
                current: isLeftCommandDown,
                other: isRightCommandDown,
                commandIsDown: commandIsDown
            )
        default:
            break
        }

        if isLeftCommandDown && isRightCommandDown {
            guard !didFireBothCommandChord else {
                return
            }
            didFireBothCommandChord = true
            raiseTrigger()
        } else {
            didFireBothCommandChord = false
        }
    }

    private func updatedCommandSideState(current: Bool, other: Bool, commandIsDown: Bool) -> Bool {
        guard commandIsDown else {
            return false
        }
        // `NSEvent.ModifierFlags.command` is unified across both Command keys. When one Command
        // key is released while the other remains down, the event still contains `.command`, so
        // use the previous per-side state to distinguish that release from a press.
        return !(current && other)
    }
}

private struct AppShotsRuntimeSettings {
    var enabled = true
    var shortcut = AppSettings.defaultAppShotShortcut
}

private let appShotHotKeySignature = OSType(0x41505348) // APSH
private let appShotHotKeyID: UInt32 = 1

private func appShotCarbonHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event,
          let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let parameterStatus = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard parameterStatus == noErr,
          hotKeyID.signature == appShotHotKeySignature,
          hotKeyID.id == appShotHotKeyID else {
        return OSStatus(eventNotHandledErr)
    }

    let coordinator = Unmanaged<AppShotCoordinator>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        coordinator.handleCarbonHotKeyPressed()
    }
    return noErr
}

private func appShotModifierEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard type == .flagsChanged,
          let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let coordinator = Unmanaged<AppShotCoordinator>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let commandIsDown = event.flags.contains(.maskCommand)
    Task { @MainActor in
        coordinator.handleFlagsChanged(keyCode: keyCode, commandIsDown: commandIsDown)
    }
    return Unmanaged.passUnretained(event)
}
