import SwiftUI

struct ScheduledTasksScreenHeader: View {
    @Binding var selectedFilter: ScheduledTasksFilter
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduled")
                        .font(.largeTitle.weight(.bold))
                    Text("Create and manage local tasks that run while Alveary and your Mac are awake.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onCreate) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("New scheduled task")
                    }
                }
                .primaryActionButtonStyle()
            }

            Picker("Scheduled task filter", selection: $selectedFilter) {
                ForEach(ScheduledTasksFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 360, alignment: .leading)
        }
    }
}
