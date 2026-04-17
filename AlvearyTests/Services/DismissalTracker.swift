import Foundation

@MainActor
final class DismissalTracker {
    private(set) var ids: [String] = []
    var onRecord: ((String) -> Void)?

    func record(_ id: String) {
        ids.append(id)
        onRecord?(id)
    }
}
