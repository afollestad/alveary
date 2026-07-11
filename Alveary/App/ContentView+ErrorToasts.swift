import AppKit
import SwiftUI

private let appErrorToastAutoDismissDelay: Duration = .seconds(8)
private let appErrorToastBackground = Color(red: 0.28, green: 0.05, blue: 0.06)
private let appSuccessToastBackground = Color(red: 0.04, green: 0.25, blue: 0.13)
private let appErrorToastBottomOffset: CGFloat = 30
private let appErrorToastMaxWidth: CGFloat = 520
private let appErrorToastSpacing: CGFloat = 8

extension ContentView {
    @ViewBuilder
    func errorToastOverlay() -> some View {
        if !appState.unexpectedErrorToasts.isEmpty {
            AppErrorToastStack(
                toasts: appState.unexpectedErrorToasts,
                onDismiss: appState.dismissUnexpectedErrorToast
            )
        }
    }
}

struct AppErrorToastStack: View {
    let toasts: [AppState.UnexpectedErrorToast]
    let onDismiss: @MainActor (AppState.UnexpectedErrorToast.ID) -> Void

    var displayToasts: [AppState.UnexpectedErrorToast] {
        toasts.reversed()
    }

    var body: some View {
        VStack(spacing: appErrorToastSpacing) {
            ForEach(displayToasts) { toast in
                AppErrorToast(toast: toast, onDismiss: onDismiss)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: appErrorToastMaxWidth)
        .padding(.horizontal, 24)
        .padding(.bottom, appErrorToastBottomOffset)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: toasts)
    }
}

private struct AppErrorToast: View {
    let toast: AppState.UnexpectedErrorToast
    let onDismiss: @MainActor (AppState.UnexpectedErrorToast.ID) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: toast.kind == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .accessibilityHidden(true)

            Text(toast.message)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("\(toast.kind.accessibilityPrefix): \(toast.message)")

            Button {
                onDismiss(toast.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(toast.kind == .success ? "Dismiss success toast" : "Dismiss error toast")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(toast.kind == .success ? appSuccessToastBackground : appErrorToastBackground)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 8)
        .task(id: toast.id) {
            NSAccessibility.post(
                element: NSApplication.shared,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: "\(toast.kind.accessibilityPrefix): \(toast.message)",
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue
                ]
            )
            try? await Task.sleep(for: appErrorToastAutoDismissDelay)
            guard !Task.isCancelled else {
                return
            }
            onDismiss(toast.id)
        }
    }
}

private extension AppState.AppToastKind {
    var accessibilityPrefix: String {
        switch self {
        case .error:
            return "Unexpected error"
        case .success:
            return "Success"
        }
    }
}
