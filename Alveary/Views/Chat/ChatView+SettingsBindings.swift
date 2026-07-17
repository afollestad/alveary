import SwiftUI

extension ChatView {
    var selectedUseWorktreeBinding: Binding<Bool> {
        Binding(
            get: { threadPresentation.selectedUseWorktree },
            set: {
                guard !voiceInputCoordinator.isDraftInteractionLocked else { return }
                viewModel.applyWorktreePreferenceChange($0)
            }
        )
    }

    var selectedPlanModeBinding: Binding<Bool> {
        Binding(
            get: { threadPresentation.selectedPlanModeEnabled },
            set: {
                guard !voiceInputCoordinator.isDraftInteractionLocked else { return }
                viewModel.applyPlanModeChange($0)
            }
        )
    }
}
