import AgentCLIKit
import SwiftUI

struct AgentsSettingsTabView: View {
    let viewModel: SettingsViewModel
    let providerIDs: [String]
    let providerExtraArgsBinding: (String) -> Binding<String>

    @State private var gridColumnCount = 2

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                ForEach(providerIDs, id: \.self) { providerID in
                    SettingsAgentCard(
                        viewModel: viewModel,
                        providerID: providerID,
                        extraArgs: providerExtraArgsBinding(providerID)
                    )
                }
            }
            .onGeometryChange(for: Int.self) { proxy in
                proxy.size.width >= 544 ? 2 : 1
            } action: { newValue in
                gridColumnCount = newValue
            }

            AgentsInstructionsSection(model: viewModel.instructionsEditor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await viewModel.refreshProviderStatuses()
        }
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 240), spacing: 16, alignment: .top),
            count: gridColumnCount
        )
    }
}
