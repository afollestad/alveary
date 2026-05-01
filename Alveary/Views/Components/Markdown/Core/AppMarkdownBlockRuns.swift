import Foundation

struct AppMarkdownBlockRun {
    let intent: PresentationIntent.IntentType?
    let range: Range<AttributedString.Index>
}

extension AttributedStringProtocol {
    func appMarkdownBlockRuns(parent: PresentationIntent.IntentType? = nil) -> [AppMarkdownBlockRun] {
        var boundaries: [(index: AttributedString.Runs.Index, intent: PresentationIntent.IntentType?)] = []
        var lastIntent: PresentationIntent.IntentType?

        for index in runs.indices {
            let intent = runs[index].presentationIntent?.appMarkdownIntent(before: parent)
            if boundaries.isEmpty || intent != lastIntent {
                boundaries.append((index, intent))
                lastIntent = intent
            }
        }

        return boundaries.indices.map { position in
            let boundary = boundaries[position]
            let nextRunIndex = position + 1 < boundaries.count
                ? boundaries[position + 1].index
                : runs.endIndex
            let lastRunIndex = runs.index(before: nextRunIndex)
            let lowerBound = runs[boundary.index].range.lowerBound
            let upperBound = runs[lastRunIndex].range.upperBound
            return AppMarkdownBlockRun(intent: boundary.intent, range: lowerBound..<upperBound)
        }
    }
}

private extension PresentationIntent {
    func appMarkdownIntent(before intent: PresentationIntent.IntentType?) -> PresentationIntent.IntentType? {
        guard let intent else {
            return components.last
        }
        guard let index = components.firstIndex(of: intent),
              index != components.startIndex else {
            return nil
        }
        return components[components.index(before: index)]
    }
}
