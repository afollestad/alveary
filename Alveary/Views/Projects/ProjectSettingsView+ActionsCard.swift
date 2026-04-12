import SwiftUI

struct ProjectSettingsActionsCard: View {
    let actions: [AlvearyProjectConfig.ProjectAction]

    var body: some View {
        GroupBox {
            if actions.isEmpty {
                Text("No custom project actions are configured yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(actions, id: \.name) { action in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(action.name)
                                .font(.headline)
                            Text(action.command)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Label("Actions", systemImage: "play.square")
        }
    }
}
