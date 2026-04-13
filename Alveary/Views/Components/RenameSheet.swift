import SwiftUI

protocol RenameDraft: Identifiable {
    var currentDisplayName: String { get }
    var title: String { get set }
    var canSave: Bool { get }
}

struct RenameSheet<Draft: RenameDraft>: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: Draft

    let heading: String
    let placeholder: String
    let closeLabel: String
    let onSave: (Draft) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(heading)
                        .font(.title2.weight(.semibold))

                    Text("Current label: \(draft.currentDisplayName)")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ModalCloseButton(closeLabel) {
                    dismiss()
                }
            }

            AppTextField(placeholder, text: $draft.title)
                .onSubmit(save)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .secondaryActionButtonStyle()

                Spacer()

                Button("Save", action: save)
                    .primaryActionButtonStyle()
                    .disabled(!draft.canSave)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}

private extension RenameSheet {
    func save() {
        guard onSave(draft) else {
            return
        }

        dismiss()
    }
}
