import AgentCLIKit
import AppKit
import SwiftUI

struct AgentsSettingsTabView: View {
    let viewModel: SettingsViewModel
    let harnessIDs: [String]

    @State private var gridColumnCount = 2

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                ForEach(harnessIDs, id: \.self) { harnessID in
                    SettingsAgentCard(
                        viewModel: viewModel,
                        harnessID: harnessID
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
            await viewModel.refreshHarnessStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await viewModel.refreshHarnessStatusesAfterActivation() }
        }
    }

    private var gridColumns: [GridItem] {
        AdaptiveCardGridLayout.columns(count: gridColumnCount, alignment: .top)
    }
}
