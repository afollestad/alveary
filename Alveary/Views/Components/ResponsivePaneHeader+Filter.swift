import SwiftUI

/// One selectable option in a pane header's filter control, erased from its source enum so
/// the header can carry both fixed `CaseIterable` tabs and options computed from live data.
struct PaneHeaderFilterItem: Identifiable {
    let id: AnyHashable
    let title: String
    let isSelected: Bool
    let select: () -> Void
}

struct PaneHeaderFilter {
    let items: [PaneHeaderFilterItem]
    let accessibilityLabel: String

    init<Option: Hashable>(
        options: [Option],
        selection: Binding<Option>,
        title: (Option) -> String,
        accessibilityLabel: String
    ) {
        items = options.map { option in
            PaneHeaderFilterItem(
                id: AnyHashable(option),
                title: title(option),
                isSelected: selection.wrappedValue == option,
                select: { selection.wrappedValue = option }
            )
        }
        self.accessibilityLabel = accessibilityLabel
    }

    var selectedTitle: String {
        items.first(where: \.isSelected)?.title ?? ""
    }
}

/// The preferred arrangement: every option as its own chip.
struct PaneHeaderFilterChipRow: View {
    let filter: PaneHeaderFilter

    var body: some View {
        HStack(spacing: 6) {
            ForEach(filter.items) { item in
                PaneFilterChip(
                    title: item.title,
                    isSelected: item.isSelected,
                    onSelect: item.select
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(filter.accessibilityLabel)
        .accessibilityValue(filter.selectedTitle)
    }
}

/// The fallback once the chips stop fitting: one chip-shaped menu naming the selection.
/// `menuStyle(.button)`
/// lets the ambient `ButtonStyle` draw the capsule, the same way the Archived screen's project
/// menu wears `secondaryActionButtonStyle()`.
struct PaneHeaderFilterDropdown: View {
    let filter: PaneHeaderFilter

    var body: some View {
        Menu {
            ForEach(filter.items) { item in
                Button(action: item.select) {
                    if item.isSelected {
                        Label(item.title, systemImage: "checkmark")
                    } else {
                        Text(item.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                // Truncate rather than size to content: the dropdown holds the leading
                // edge, so a label that refuses to compress pushes the whole row past the
                // pane and the enclosing clip cuts the control the user navigates with.
                Text(filter.selectedTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .menuStyle(.button)
        .buttonStyle(TabChipButtonStyle(isSelected: true))
        .menuIndicator(.hidden)
        // Claim the label's ideal width ahead of the trailing spacer, so it compresses
        // only once the pane genuinely cannot hold it.
        .layoutPriority(1)
        .accessibilityLabel(filter.accessibilityLabel)
        .accessibilityValue(filter.selectedTitle)
    }
}
