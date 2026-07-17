import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testChatComposerNativeActionControlInteractionStates() {
        assertMacSnapshot(
            nativeActionControlInteractionStates,
            size: CGSize(width: 770, height: 76),
            named: "chat_composer_native_action_control_interaction_states"
        )
    }

    func testChatComposerNativeActionControlInteractionStatesDark() {
        assertMacSnapshot(
            nativeActionControlInteractionStates,
            size: CGSize(width: 770, height: 76),
            named: "chat_composer_native_action_control_interaction_states_dark",
            colorScheme: .dark
        )
    }

    func testChatComposerWorktreeLocationButtonContent() {
        assertMacSnapshot(
            worktreeLocationButtonContent,
            size: CGSize(width: 340, height: 64),
            named: "chat_composer_worktree_location_button_content",
            colorScheme: .dark
        )
    }

    func testChatComposerReasoningButtonTruncatedModelSpacing() {
        assertMacSnapshot(
            reasoningButtonTruncatedModelSpacing,
            size: CGSize(width: 260, height: 64),
            named: "chat_composer_reasoning_button_truncated_model_spacing",
            colorScheme: .dark
        )
    }

    private var nativeActionControlInteractionStates: some View {
        HStack(spacing: 16) {
            ComposerReasoningButtonSnapshot(state: .hovered)
                .frame(width: 132, height: 24)
            ComposerPermissionButtonSnapshot(state: .hovered)
                .frame(width: 144, height: 24)
            ComposerVoiceInputButtonSnapshot(state: .hovered)
                .frame(width: 30, height: 30)
            ComposerVoiceInputButtonSnapshot(state: .pressed)
                .frame(width: 30, height: 30)
            ComposerVoiceInputButtonSnapshot(state: .focused)
                .frame(width: 30, height: 30)
            ComposerActionButtonSnapshot(style: .primary, title: "Send", symbolName: "paperplane.fill", state: .hovered)
                .frame(width: 76, height: 30)
            ComposerActionButtonSnapshot(style: .primary, title: "Send", symbolName: "paperplane.fill", state: .pressed)
                .frame(width: 76, height: 30)
            ComposerActionButtonSnapshot(style: .destructive, title: "Stop", symbolName: "stop.fill", state: .pressed)
                .frame(width: 76, height: 30)
        }
        .padding(20)
    }

    private var worktreeLocationButtonContent: some View {
        HStack(spacing: 16) {
            ComposerWorktreeLocationButtonSnapshot(useWorktree: false, state: .hovered)
                .frame(width: 140, height: 24)
            ComposerWorktreeLocationButtonSnapshot(useWorktree: true, state: .pressed)
                .frame(width: 150, height: 24)
        }
        .padding(20)
    }

    private var reasoningButtonTruncatedModelSpacing: some View {
        HStack {
            ReasoningButtonTruncationSnapshot()
                .frame(width: ComposerReasoningButton.maxWidth, height: 24)
        }
        .padding(20)
    }
}

private enum ComposerControlSnapshotState {
    case idle
    case hovered
    case pressed
}

private enum ComposerVoiceInputSnapshotState {
    case hovered
    case pressed
    case focused
}

private struct ComposerVoiceInputButtonSnapshot: NSViewRepresentable {
    let state: ComposerVoiceInputSnapshotState

    func makeNSView(context: Context) -> ComposerVoiceInputButton {
        let view = ComposerVoiceInputButton()
        configure(view)
        return view
    }

    func updateNSView(_ view: ComposerVoiceInputButton, context: Context) {
        configure(view)
    }

    private func configure(_ view: ComposerVoiceInputButton) {
        view.configure(ComposerVoiceInputConfiguration(
            phase: .ready,
            isEnabled: true,
            shortcutDisplay: "⌃⇧Space",
            unavailableHelp: nil,
            onPress: { true },
            onRelease: { _ in true },
            onAccessibilityToggle: {},
            onAccessibilityCancel: { true }
        ))
        switch state {
        case .hovered:
            view.mouseEntered(with: Self.event)
        case .pressed:
            view.isHighlighted = true
            view.needsDisplay = true
        case .focused:
            #if DEBUG
            view.debugSetFocusAppearance(true)
            #endif
        }
    }

    private static var event: NSEvent {
        NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ) ?? NSEvent()
    }
}

private struct ComposerReasoningButtonSnapshot: NSViewRepresentable {
    let state: ComposerControlSnapshotState

    func makeNSView(context: Context) -> ComposerReasoningButton {
        let view = ComposerReasoningButton()
        configure(view)
        return view
    }

    func updateNSView(_ view: ComposerReasoningButton, context: Context) {
        configure(view)
    }

    private func configure(_ view: ComposerReasoningButton) {
        view.configure(
            selection: makeReasoningConfiguration().selection,
            height: ChatComposerActionRowView.defaultSettingsControlHeight,
            isEnabled: true,
            showsProgress: false,
            actionHandler: {}
        )
        switch state {
        case .idle:
            break
        case .hovered:
            view.mouseEntered(with: Self.event)
        case .pressed:
            view.mouseEntered(with: Self.event)
            view.mouseDown(with: Self.event)
        }
    }

    private static var event: NSEvent {
        NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ) ?? NSEvent()
    }
}

private struct ReasoningButtonTruncationSnapshot: NSViewRepresentable {
    func makeNSView(context: Context) -> ComposerReasoningButton {
        let view = ComposerReasoningButton()
        configure(view)
        return view
    }

    func updateNSView(_ view: ComposerReasoningButton, context: Context) {
        configure(view)
    }

    private func configure(_ view: ComposerReasoningButton) {
        view.configure(
            selection: makeReasoningConfiguration(
                modelOptions: [.init(value: "codex-spark", title: "GPT-5.3-Codex-Spark-Extended-Context")],
                effortOptions: [.init(value: "high", title: "High")],
                selectedModel: "codex-spark",
                selectedEffort: "high",
                selectedSpeedMode: .fast,
                supportsSpeedMode: true
            ).selection,
            height: ChatComposerActionRowView.defaultSettingsControlHeight,
            isEnabled: true,
            showsProgress: false,
            actionHandler: {}
        )
        view.mouseEntered(with: Self.event)
    }

    private static var event: NSEvent {
        NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ) ?? NSEvent()
    }
}

private struct ComposerPermissionButtonSnapshot: NSViewRepresentable {
    let state: ComposerControlSnapshotState

    func makeNSView(context: Context) -> ComposerPermissionButton {
        let view = ComposerPermissionButton()
        configure(view)
        return view
    }

    func updateNSView(_ view: ComposerPermissionButton, context: Context) {
        configure(view)
    }

    private func configure(_ view: ComposerPermissionButton) {
        view.configure(
            option: .init(
                value: "never",
                title: "Full access",
                description: "Unrestricted access to the internet and any file on your computer.",
                symbolName: "exclamationmark.shield",
                isWarning: true
            ),
            height: ChatComposerActionRowView.defaultSettingsControlHeight,
            isEnabled: true,
            actionHandler: {}
        )
        switch state {
        case .idle:
            break
        case .hovered:
            view.mouseEntered(with: Self.event)
        case .pressed:
            view.mouseEntered(with: Self.event)
            view.mouseDown(with: Self.event)
        }
    }

    private static var event: NSEvent {
        NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ) ?? NSEvent()
    }
}

private struct ComposerWorktreeLocationButtonSnapshot: NSViewRepresentable {
    let useWorktree: Bool
    let state: ComposerControlSnapshotState

    func makeNSView(context: Context) -> ComposerWorktreeLocationButton {
        let view = ComposerWorktreeLocationButton()
        configure(view)
        return view
    }

    func updateNSView(_ view: ComposerWorktreeLocationButton, context: Context) {
        configure(view)
    }

    private func configure(_ view: ComposerWorktreeLocationButton) {
        view.configure(
            option: ChatComposerWorktreeLocationPresentation.selectedOption(usesWorktree: useWorktree),
            height: ChatComposerActionRowView.defaultSettingsControlHeight,
            isEnabled: true,
            actionHandler: {}
        )
        switch state {
        case .idle:
            break
        case .hovered:
            view.mouseEntered(with: Self.event)
        case .pressed:
            view.mouseEntered(with: Self.event)
            view.mouseDown(with: Self.event)
        }
    }

    private static var event: NSEvent {
        NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ) ?? NSEvent()
    }
}

private struct ComposerActionButtonSnapshot: NSViewRepresentable {
    let style: ComposerActionButton.Style
    let title: String
    let symbolName: String
    let state: ComposerControlSnapshotState

    func makeNSView(context: Context) -> ComposerActionButton {
        let view = ComposerActionButton(style: style)
        configure(view)
        return view
    }

    func updateNSView(_ view: ComposerActionButton, context: Context) {
        configure(view)
    }

    private func configure(_ view: ComposerActionButton) {
        view.configure(title: title, symbolName: symbolName, isEnabled: true, accessibilityLabel: title)
        switch state {
        case .idle:
            break
        case .hovered:
            view.mouseEntered(with: Self.event)
        case .pressed:
            view.mouseEntered(with: Self.event)
            view.mouseDown(with: Self.event)
        }
    }

    private static var event: NSEvent {
        NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ) ?? NSEvent()
    }
}
