import SwiftUI

struct AppOnboardingOverlay: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.46)
                    .ignoresSafeArea()

                panel(width: panelWidth(availableWidth: proxy.size.width))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(24)
            }
        }
        .zIndex(1000)
        .onDisappear {
            viewModel.cancelInstallersForDismissal()
        }
    }

    private func panel(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            dependencyList
                .padding(.top, 22)
            footer
                .padding(.top, 24)
        }
        .padding(.top, 28)
        .padding(.horizontal, 30)
        .padding(.bottom, 28)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.34), radius: 28, x: 0, y: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Alveary setup")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set up Alveary")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text("Install command-line tools for agent workflows. GitHub CLI is required.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dependencyList: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.dependencies) { dependency in
                AppOnboardingDependencyCard(
                    dependency: dependency,
                    state: viewModel.state(for: dependency),
                    isInstallEnabled: viewModel.canInstall(dependency),
                    onInstall: {
                        viewModel.install(dependency)
                    }
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Button {
                viewModel.continueOnboarding()
            } label: {
                Text(viewModel.isContinuing ? "Checking..." : "Continue")
            }
            .primaryActionButtonStyle()
            .disabled(!viewModel.canContinue)
            .accessibilityHint("Continues once the required GitHub CLI dependency is installed.")
        }
    }

    private func panelWidth(availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth - 72, 360), 680)
    }
}

struct AppOnboardingDependencyCard: View {
    let dependency: OnboardingDependency
    let state: OnboardingDependencyViewState
    let isInstallEnabled: Bool
    let interactionState: OnboardingInstallButtonInteractionState?
    let onInstall: () -> Void

    init(
        dependency: OnboardingDependency,
        state: OnboardingDependencyViewState,
        isInstallEnabled: Bool,
        interactionState: OnboardingInstallButtonInteractionState? = nil,
        onInstall: @escaping () -> Void
    ) {
        self.dependency = dependency
        self.state = state
        self.isInstallEnabled = isInstallEnabled
        self.interactionState = interactionState
        self.onInstall = onInstall
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(dependency.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(dependency.required ? "Required" : "Optional")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(dependency.required ? Color.primary.opacity(0.78) : Color.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(dependency.required ? AppAccentFill.primary.opacity(0.45) : Color.primary.opacity(0.08))
                        )
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(action: onInstall) {
                AppOnboardingInstallButtonIcon(state: state)
            }
            .buttonStyle(OnboardingInstallCircleButtonStyle(interactionState: interactionState))
            .disabled(!isInstallEnabled)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(statusText)
            .accessibilityHint(accessibilityHint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 78)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var statusText: String {
        switch state {
        case .checking:
            return "Checking..."
        case .missing(let error):
            return error ?? "Not installed"
        case .installing:
            return "Installing..."
        case .installed(let detail):
            return detail.map { "Installed: \($0)" } ?? "Installed"
        }
    }

    private var statusColor: Color {
        switch state {
        case .checking, .installing:
            return .secondary
        case .missing(let error):
            return error == nil ? .secondary : .red
        case .installed:
            return .green
        }
    }

    private var borderColor: Color {
        switch state {
        case .missing(let error) where error != nil:
            return .red.opacity(0.34)
        case .installed:
            return .green.opacity(0.26)
        default:
            return .primary.opacity(0.08)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .installed:
            return "\(dependency.displayName) installed"
        case .checking:
            return "Checking \(dependency.displayName)"
        case .installing:
            return "Installing \(dependency.displayName)"
        case .missing:
            return "Install \(dependency.displayName)"
        }
    }

    private var accessibilityHint: String {
        switch state {
        case .missing:
            return "Starts installation for \(dependency.displayName)."
        case .installed:
            return "\(dependency.displayName) is already installed."
        case .checking:
            return "\(dependency.displayName) availability is being checked."
        case .installing:
            return "\(dependency.displayName) installation is in progress."
        }
    }
}

struct AppOnboardingInstallButtonIcon: View {
    let state: OnboardingDependencyViewState

    var body: some View {
        Group {
            switch state {
            case .checking, .installing:
                StatusIndicatorSpinner(color: .primary.opacity(0.74), diameter: 15, lineWidth: 2)
            case .missing:
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
            case .installed:
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
            }
        }
        .frame(width: 18, height: 18)
    }
}

enum OnboardingInstallButtonInteractionState: Sendable, Equatable {
    case normal
    case focused
    case pressed
}

struct OnboardingInstallCircleButtonStyle: ButtonStyle {
    var interactionState: OnboardingInstallButtonInteractionState?

    func makeBody(configuration: Configuration) -> some View {
        OnboardingInstallCircleButtonBody(
            configuration: configuration,
            interactionState: interactionState
        )
    }
}

private struct OnboardingInstallCircleButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let interactionState: OnboardingInstallButtonInteractionState?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundStyle(Color.primary.opacity(foregroundOpacity))
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(backgroundColor)
            )
            .overlay(
                Circle()
                    .stroke(focusStrokeColor, lineWidth: 1.5)
            )
            .contentShape(Circle())
            .scaleEffect(isPressed && isEnabled ? 0.94 : 1)
            .focusEffectDisabled()
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }

    private var isPressed: Bool {
        if interactionState == .pressed {
            return true
        }
        return interactionState == nil && configuration.isPressed
    }

    private var showsFocused: Bool {
        if interactionState == .focused {
            return true
        }
        return interactionState == nil && isFocused
    }

    private var foregroundOpacity: Double {
        guard isEnabled else {
            return 0.56
        }
        return 0.92
    }

    private var backgroundColor: Color {
        guard isEnabled else {
            return Color.primary.opacity(0.07)
        }
        if isPressed {
            return Color.primary.opacity(0.18)
        }
        if showsFocused {
            return AppAccentFill.primary.opacity(0.42)
        }
        return Color.primary.opacity(0.10)
    }

    private var focusStrokeColor: Color {
        guard isEnabled, showsFocused else {
            return .clear
        }
        return AppAccentFill.primary.opacity(0.82)
    }
}
