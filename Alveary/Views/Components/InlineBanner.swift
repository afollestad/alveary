import SwiftUI

struct InlineBanner: View {
    let message: String
    let severity: Severity
    let autoDismissAfter: Duration?
    let actionTitle: String?
    let onAction: (() -> Void)?
    // When nil the X affordance is hidden — useful for banners whose dismissal
    // is driven by surrounding buttons instead of the banner itself.
    let onDismiss: (() -> Void)?

    @State private var dismissTask: Task<Void, Never>?

    init(
        message: String,
        severity: Severity,
        autoDismissAfter: Duration?,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.message = message
        self.severity = severity
        self.autoDismissAfter = autoDismissAfter
        self.actionTitle = actionTitle
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    enum Severity: Sendable {
        case warning
        case error
        case info

        var iconName: String {
            switch self {
            case .warning:
                return "exclamationmark.triangle.fill"
            case .error:
                return "xmark.octagon.fill"
            case .info:
                return "info.circle.fill"
            }
        }

        var accentColor: Color {
            switch self {
            case .warning:
                return .orange
            case .error:
                return .red
            case .info:
                return .blue
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: severity.iconName)
                .foregroundStyle(severity.accentColor)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let onAction {
                Button(actionTitle, action: onAction)
                    .secondaryActionButtonStyle()
                    .controlSize(.small)
            }

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(severity.accentColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(severity.accentColor.opacity(0.3), lineWidth: 1)
        )
        .onAppear(perform: scheduleDismissIfNeeded)
        .onChange(of: autoDismissAfter) { _, _ in
            scheduleDismissIfNeeded()
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }
}

private extension InlineBanner {
    func scheduleDismissIfNeeded() {
        dismissTask?.cancel()
        guard let autoDismissAfter else {
            dismissTask = nil
            return
        }

        dismissTask = Task {
            try? await Task.sleep(for: autoDismissAfter)
            guard !Task.isCancelled else {
                return
            }
            onDismiss?()
        }
    }
}
