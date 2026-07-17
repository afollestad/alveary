@preconcurrency import AppKit
import Carbon

@MainActor
struct AppKitVoiceInputShortcutConfiguration {
    let descriptor: PhysicalKeyboardShortcut?
    let isEnabled: Bool
    let onEscape: () -> Bool
    let onPress: () -> Bool
    let onRelease: (Bool) -> Bool
    let onForcedStop: () -> Void
}

extension AppKitChatComposerPanelView {
    func notifyVoiceInputAvailabilityAfterMount() {
        Task { @MainActor [weak self] in
            guard let self, self.window != nil else { return }
            self.configuration?.bodyConfiguration.onVoiceInputAvailabilityChange()
        }
    }

    func installVoiceInputEventInfrastructure() {
        voiceInputKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleVoiceInputKeyEvent(event) ?? event
        }
        let notificationCenter = NotificationCenter.default
        lifecycleObservers.append(notificationCenter.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.forceVoiceInputReleaseAndStop() }
        })
        if let window {
            lifecycleObservers.append(notificationCenter.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.forceVoiceInputReleaseAndStop() }
            })
        }
        lifecycleObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.forceVoiceInputReleaseAndStop() }
        })
    }

    func removeVoiceInputEventInfrastructure() {
        if let voiceInputKeyMonitor {
            NSEvent.removeMonitor(voiceInputKeyMonitor)
            self.voiceInputKeyMonitor = nil
        }
        isVoiceInputEscapeKeyHeld = false
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        lifecycleObservers.removeAll()
    }

    func handleVoiceInputKeyEvent(
        _ event: NSEvent,
        keyWindow: NSWindow? = NSApp.keyWindow
    ) -> NSEvent? {
        if consumeVoiceInputEscapeIfNeeded(event, keyWindow: keyWindow) {
            return nil
        }
        if event.type == .keyDown,
           let trackedVoiceInputKeyCode,
           UInt16(event.keyCode) == trackedVoiceInputKeyCode {
            guard !event.isARepeat else { return nil }
            self.trackedVoiceInputKeyCode = nil
            _ = configuration?.voiceInputShortcutConfiguration?.onRelease(true)
            configuration?.voiceInputShortcutConfiguration?.onForcedStop()
            suppressedVoiceInputKeyUpCode = trackedVoiceInputKeyCode
            return nil
        }
        if event.type == .keyDown,
           let suppressedVoiceInputKeyUpCode,
           UInt16(event.keyCode) == suppressedVoiceInputKeyUpCode {
            guard !event.isARepeat else { return nil }
            self.suppressedVoiceInputKeyUpCode = nil
        }
        if event.type == .keyUp,
           let suppressedVoiceInputKeyUpCode,
           UInt16(event.keyCode) == suppressedVoiceInputKeyUpCode {
            self.suppressedVoiceInputKeyUpCode = nil
            return nil
        }
        if event.type == .keyUp,
           let trackedVoiceInputKeyCode,
           UInt16(event.keyCode) == trackedVoiceInputKeyCode {
            self.trackedVoiceInputKeyCode = nil
            _ = configuration?.voiceInputShortcutConfiguration?.onRelease(false)
            return nil
        }
        guard event.type == .keyDown,
              !event.isARepeat,
              trackedVoiceInputKeyCode == nil,
              suppressedVoiceInputKeyUpCode == nil,
              canHandleVoiceInputShortcut(keyWindow: keyWindow),
              let shortcut = configuration?.voiceInputShortcutConfiguration,
              shortcut.isEnabled,
              let descriptor = shortcut.descriptor,
              descriptor.matches(event: event),
              shortcut.onPress() else {
            return event
        }
        trackedVoiceInputKeyCode = descriptor.keyCode
        return nil
    }

    private func consumeVoiceInputEscapeIfNeeded(_ event: NSEvent, keyWindow: NSWindow?) -> Bool {
        let isBareEscape = UInt16(event.keyCode) == UInt16(kVK_Escape) &&
            PhysicalKeyboardShortcutModifiers(event.modifierFlags).isEmpty
        if isBareEscape, event.type == .keyUp, isVoiceInputEscapeKeyHeld {
            isVoiceInputEscapeKeyHeld = false
            return true
        }
        if isBareEscape, event.type == .keyDown {
            if isVoiceInputEscapeKeyHeld {
                return true
            }
            if canHandleVoiceInputEscape(keyWindow: keyWindow),
               configuration?.voiceInputShortcutConfiguration?.onEscape() == true {
                isVoiceInputEscapeKeyHeld = true
                return true
            }
        }
        return false
    }

    var canHandleVoiceInputShortcut: Bool {
        canHandleVoiceInputShortcut(keyWindow: NSApp.keyWindow)
    }

    var canActivateVoiceInputControl: Bool {
        canActivateVoiceInputControl(keyWindow: NSApp.keyWindow)
    }

    func canActivateVoiceInputControl(keyWindow: NSWindow?) -> Bool {
        trackedVoiceInputKeyCode == nil &&
            suppressedVoiceInputKeyUpCode == nil &&
            canHandleVoiceInputShortcut(keyWindow: keyWindow)
    }

    func canHandleVoiceInputShortcut(keyWindow: NSWindow?) -> Bool {
        guard let configuration,
              window === keyWindow,
              window?.attachedSheet == nil,
              !isHiddenOrHasHiddenAncestor,
              !isVoiceInteractionBlocked(configuration),
              editorController.view?.hasPresentedEditorInteractionUI != true,
              !actionRow.hasPresentedPopover else {
            return false
        }
        return true
    }

    func canHandleVoiceInputEscape(keyWindow: NSWindow?) -> Bool {
        guard configuration != nil,
              window === keyWindow,
              !isHiddenOrHasHiddenAncestor else {
            return false
        }
        return true
    }

    func reconcileHeldVoiceShortcut(next: AppKitVoiceInputShortcutConfiguration?) {
        guard let previous = configuration?.voiceInputShortcutConfiguration else {
            return
        }
        guard previous.descriptor?.keyCode != next?.descriptor?.keyCode ||
                previous.descriptor?.modifiers != next?.descriptor?.modifiers else {
            return
        }
        if let trackedVoiceInputKeyCode {
            self.trackedVoiceInputKeyCode = nil
            suppressedVoiceInputKeyUpCode = trackedVoiceInputKeyCode
            _ = previous.onRelease(true)
        }
        previous.onForcedStop()
    }

    func forceVoiceInputReleaseAndStop() {
        actionRow.forceVoiceInputMouseRelease()
        isVoiceInputEscapeKeyHeld = false
        if let trackedVoiceInputKeyCode {
            self.trackedVoiceInputKeyCode = nil
            suppressedVoiceInputKeyUpCode = trackedVoiceInputKeyCode
            _ = configuration?.voiceInputShortcutConfiguration?.onRelease(true)
        }
        configuration?.voiceInputShortcutConfiguration?.onForcedStop()
    }

    func isVoiceInteractionBlocked(_ configuration: AppKitChatComposerPanelConfiguration) -> Bool {
        if configuration.interactionOverlayConfiguration != nil ||
            configuration.bodyConfiguration.isProjectTrustBlocked {
            return true
        }
        if case .progressOnly = configuration.bodyConfiguration.mode {
            return true
        }
        return false
    }
}
