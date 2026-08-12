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
            .adaptiveCardGridReflow(columnCount: gridColumnCount)
            // The grid sits behind the settings side list, inset from the lane's slot,
            // so it cannot follow the published settled width — see the modifier's doc.
            .adaptiveCardGridColumnCount($gridColumnCount, spansMainPane: false)

            AgentsInstructionsSection(model: viewModel.instructionsEditor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await viewModel.refreshProviderStatuses()
        }
    }

    private var gridColumns: [GridItem] {
        AdaptiveCardGridLayout.columns(count: gridColumnCount, alignment: .top)
    }
}
