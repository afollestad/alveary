import SwiftUI

extension ThreadsSettingsTabView {
    var archivedTasksSection: some View {
        ArchivedTasksSettingsSection(
            items: archivedTasksViewModel?.items ?? [],
            busyTaskIDs: archivedTasksViewModel?.busyTaskIDs ?? [],
            errorMessage: archivedTasksViewModel?.errorMessage,
            onDismissError: { archivedTasksViewModel?.dismissError() },
            onRestore: { item in
                guard let archivedTasksViewModel else {
                    return
                }
                Task { await archivedTasksViewModel.restore(item) }
            },
            onDelete: { item in
                archivedTasksViewModel?.requestPermanentDeletion(item)
            }
        )
    }

    var archivedTaskDeleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { archivedTasksViewModel?.pendingPermanentDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    archivedTasksViewModel?.cancelPermanentDeletion()
                }
            }
        )
    }
}

struct ArchivedTasksSettingsSection: View {
    let items: [ArchivedTaskSettingsItem]
    let busyTaskIDs: Set<ArchivedTaskSettingsItem.ID>
    let errorMessage: String?
    let onDismissError: () -> Void
    let onRestore: (ArchivedTaskSettingsItem) -> Void
    let onDelete: (ArchivedTaskSettingsItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            if let errorMessage {
                InlineBanner(
                    message: errorMessage,
                    severity: .error,
                    autoDismissAfter: nil,
                    onDismiss: onDismissError
                )
            }

            SettingsFormSection("Archived Tasks") {
                if items.isEmpty {
                    SettingsFormRow(showsDivider: false) {
                        Text("No archived tasks")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(items) { item in
                        ArchivedTaskSettingsRow(
                            item: item,
                            isBusy: busyTaskIDs.contains(item.id),
                            showsDivider: item.id != items.last?.id,
                            onRestore: { onRestore(item) },
                            onDelete: { onDelete(item) }
                        )
                    }
                }
            }
        }
    }
}

private struct ArchivedTaskSettingsRow: View {
    let item: ArchivedTaskSettingsItem
    let isBusy: Bool
    let showsDivider: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsFormRow(showsDivider: showsDivider) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .lineLimit(1)

                    Text(
                        "Archived \(item.archivedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())"
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    Button("Restore", action: onRestore)
                        .secondaryActionButtonStyle()

                    Button("Delete", action: onDelete)
                        .destructiveActionButtonStyle()
                }
                .controlSize(.small)
                .disabled(isBusy)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
