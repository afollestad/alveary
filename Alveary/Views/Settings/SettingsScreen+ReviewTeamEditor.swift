import SwiftUI

struct PullRequestReviewTeamEditorSheet: View {
    let viewModel: SettingsViewModel
    let onCancel: () -> Void
    let onSave: (AppSettings) -> Void

    @State private var draft: AppSettings
    @State private var gridColumnCount = 2

    init(
        viewModel: SettingsViewModel,
        draft: AppSettings,
        onCancel: @escaping () -> Void,
        onSave: @escaping (AppSettings) -> Void
    ) {
        self.viewModel = viewModel
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review team")
                        .font(.title3.weight(.semibold))

                    Text("A strict majority must agree before feedback is proposed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                teamStatus
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PullRequestReviewLeadEditor(viewModel: viewModel, draft: $draft)

                    HStack {
                        Text("Peer reviewers")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        Spacer()

                        Text("\(peers.count) of 4")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if peers.isEmpty {
                        Text("Add at least one reviewer with a concrete model before saving.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        LazyVGrid(
                            columns: AdaptiveCardGridLayout.columns(count: gridColumnCount, alignment: .top),
                            alignment: .leading,
                            spacing: 16
                        ) {
                            ForEach(peers) { peer in
                                if let index = peers.firstIndex(where: { $0.id == peer.id }) {
                                    peerSection(index: index)
                                }
                            }
                        }
                        .adaptiveCardGridReflow(columnCount: gridColumnCount)
                        .adaptiveCardGridColumnCount($gridColumnCount, spansMainPane: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Add reviewer", action: addPeer)
                    .secondaryActionButtonStyle()
                    .disabled(peers.count >= 4 || nextPeer == nil)

                Spacer()

                Button("Cancel", action: onCancel)
                    .secondaryActionButtonStyle()
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(draft)
                }
                .primaryActionButtonStyle()
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 580, idealHeight: 760)
    }
}

private extension PullRequestReviewTeamEditorSheet {
    var peers: [PullRequestReviewPeer] {
        get { draft.pullRequestReviewPeers }
        nonmutating set { draft.pullRequestReviewPeers = newValue }
    }

    @ViewBuilder
    var teamStatus: some View {
        switch viewModel.pullRequestReviewTeamSettingsStatus(peers: peers, settings: draft) {
        case .checking:
            Label("Checking", systemImage: "clock")
                .foregroundStyle(.secondary)
        case .ready:
            Label(teamSummary, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needsAttention(let message):
            VStack(alignment: .trailing, spacing: 3) {
                Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 300, alignment: .trailing)
            }
        }
    }

    func peerSection(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            peerHeader(index: index)

            SettingsFormSection {
                SettingsFormRow {
                    SettingsResponsiveControlRow("Harness", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Reviewer \(index + 2) harness",
                            selection: harnessBinding(index: index),
                            options: viewModel.pullRequestReviewPeerHarnessOptions(
                                including: peers[index].harnessID
                            ),
                            label: { viewModel.harnessDisplayName(for: $0) }
                        )
                    }
                }

                SettingsFormRow {
                    SettingsResponsiveControlRow("Model", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Reviewer \(index + 2) model",
                            selection: modelBinding(index: index),
                            options: viewModel.pullRequestReviewPeerModelOptions(peers[index]),
                            label: { value in
                                viewModel.pullRequestReviewPeerModelLabel(
                                    value,
                                    harnessID: peers[index].harnessID
                                )
                            }
                        )
                    }
                }

                SettingsFormRow(showsDivider: false) {
                    SettingsResponsiveControlRow("Effort", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Reviewer \(index + 2) effort",
                            selection: effortBinding(index: index),
                            options: viewModel.pullRequestReviewPeerEffortOptions(peers[index]),
                            label: { value in
                                viewModel.pullRequestReviewPeerEffortLabel(value, peer: peers[index])
                            }
                        )
                    }
                }
            }
        }
    }

    func peerHeader(index: Int) -> some View {
        HStack {
            Text("Reviewer \(index + 2)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                peers.remove(at: index)
            } label: {
                Image(systemName: "trash")
            }
            .destructiveIconActionButtonStyle()
            .help("Remove reviewer \(index + 2)")
            .accessibilityLabel("Remove reviewer \(index + 2)")
        }
    }

    var teamSummary: String {
        let count = peers.count + 1
        return "\(count) reviewers · \(ReviewTeamConsensus.requiredVotes(teamSize: count)) required"
    }

    var canSave: Bool {
        viewModel.pullRequestReviewTeamSettingsStatus(peers: peers, settings: draft) == .ready
    }

    var nextPeer: PullRequestReviewPeer? {
        viewModel.nextPullRequestReviewPeer(excluding: peers, settings: draft)
    }

    func addPeer() {
        guard peers.count < 4, let peer = nextPeer else {
            return
        }
        peers.append(peer)
    }

    func harnessBinding(index: Int) -> Binding<String> {
        Binding(
            get: { peers[index].harnessID },
            set: { harnessID in
                if let replacement = viewModel.defaultPullRequestReviewPeer(
                    harnessID: harnessID,
                    excluding: peers.enumerated().compactMap { $0.offset == index ? nil : $0.element },
                    settings: draft
                ) {
                    peers[index].harnessID = harnessID
                    peers[index].model = replacement.model
                    peers[index].effort = replacement.effort
                } else {
                    peers[index].harnessID = harnessID
                    peers[index].model = ""
                    peers[index].effort = AppSettings.defaultEffortLevel
                }
            }
        )
    }

    func modelBinding(index: Int) -> Binding<String> {
        Binding(
            get: { viewModel.pullRequestReviewPeerModelSelection(peers[index]) },
            set: { selection in
                let model = viewModel.pullRequestReviewPeerStoredModel(
                    harnessID: peers[index].harnessID,
                    selection: selection
                )
                peers[index].model = model
                peers[index].effort = viewModel.pullRequestReviewPeerDefaultEffort(
                    harnessID: peers[index].harnessID,
                    model: model
                )
            }
        )
    }

    func effortBinding(index: Int) -> Binding<String> {
        Binding(
            get: { peers[index].effort },
            set: { peers[index].effort = $0 }
        )
    }
}
