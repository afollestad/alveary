import Foundation

struct PaneSessionDismissalRequest<Target: Hashable>: Hashable {
    let target: Target
    let generation: UUID
}
