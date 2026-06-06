import SwiftUI

extension ChatView {
    var selectedUseWorktreeBinding: Binding<Bool> {
        Binding(
            get: { threadPresentation.selectedUseWorktree },
            set: { viewModel.applyWorktreePreferenceChange($0) }
        )
    }

    var selectedPlanModeBinding: Binding<Bool> {
        Binding(
            get: { threadPresentation.selectedPlanModeEnabled },
            set: { viewModel.applyPlanModeChange($0) }
        )
    }
}
