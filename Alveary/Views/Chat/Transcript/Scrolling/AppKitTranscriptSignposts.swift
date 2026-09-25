import OSLog

/// Instruments intervals for the transcript's hot paths, so a profile shows which of a bridge
/// update, row build, document layout, viewport hydration, or streaming tick is paying for a
/// long transcript. Names are static and nothing is formatted, so a disabled signposter costs
/// only the `isEnabled` check.
enum AppKitTranscriptSignposts {
    struct Interval {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState?
    }

    private static let signposter = OSSignposter(subsystem: "Alveary", category: "Transcript")

    static func begin(_ name: StaticString) -> Interval {
        guard signposter.isEnabled else {
            return Interval(name: name, state: nil)
        }
        return Interval(name: name, state: signposter.beginInterval(name, id: signposter.makeSignpostID()))
    }

    static func end(_ interval: Interval) {
        guard let state = interval.state else {
            return
        }
        signposter.endInterval(interval.name, state)
    }
}
