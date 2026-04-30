import Foundation

@testable import Alveary

@MainActor
final class RecordingKeepAwakeService: KeepAwakeService {
    private(set) var activeSources = Set<KeepAwakeActivitySource>()
    private(set) var calls: [(source: KeepAwakeActivitySource, active: Bool)] = []

    func setActive(_ active: Bool, for source: KeepAwakeActivitySource) {
        calls.append((source, active))
        if active {
            activeSources.insert(source)
        } else {
            activeSources.remove(source)
        }
    }

    func isActive(_ source: KeepAwakeActivitySource) -> Bool {
        activeSources.contains(source)
    }
}
