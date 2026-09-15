protocol HarnessDetectionService: Actor {
    func resolvedPath(for harnessId: String) -> String?
    func status(for harnessId: String) -> HarnessStatus
    func checkAllHarnesses() async
    func checkHarness(_ harnessId: String) async
}

enum HarnessStatus: Sendable, Equatable {
    case unchecked
    case connected(path: String, version: String)
    case missing
    case needsKey
    case error(String)
}
