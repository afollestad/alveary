import Foundation

enum AppMarkdownCodeBlockParser {
    static func containsCode(in markdown: String) -> Bool {
        let ranges = codeRanges(in: markdown)
        return !ranges.blockRanges.isEmpty || !ranges.inlineContentRanges.isEmpty
    }

    static func codeRanges(in markdown: String) -> AppMarkdownCodeRanges {
        let blockCodeRanges = blockCodeRanges(in: markdown)
        let blockRanges = blockCodeRanges.map(\.fullRange)
        let inlineRanges = inlineRanges(in: markdown, excluding: blockRanges)
        return AppMarkdownCodeRanges(
            blockRanges: blockRanges,
            blockContentRanges: blockCodeRanges.map(\.contentRange),
            blockDelimiterRanges: blockCodeRanges.flatMap(\.delimiterRanges),
            inlineFullRanges: inlineRanges.map(\.fullRange),
            inlineContentRanges: inlineRanges.map(\.contentRange),
            inlineDelimiterRanges: inlineRanges.flatMap(\.delimiterRanges)
        )
    }

    static func blockRanges(in markdown: String) -> [NSRange] {
        blockCodeRanges(in: markdown).map(\.fullRange)
    }

    static func blockContentRanges(in markdown: String) -> [NSRange] {
        blockCodeRanges(in: markdown).map(\.contentRange)
    }

    static func blockDelimiterRanges(in markdown: String) -> [NSRange] {
        blockCodeRanges(in: markdown).flatMap(\.delimiterRanges)
    }

    private static func isFenceLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```")
    }

    static func blockCodeRanges(in markdown: String) -> [AppMarkdownBlockCodeRange] {
        let nsMarkdown = markdown as NSString
        guard nsMarkdown.length > 0 else {
            return []
        }

        var ranges: [AppMarkdownBlockCodeRange] = []
        var activeOpeningLineRange: NSRange?
        var activeContentStart: Int?
        var location = 0

        while location < nsMarkdown.length {
            let lineRange = nsMarkdown.lineRange(for: NSRange(location: location, length: 0))
            let line = nsMarkdown.substring(with: lineRange)
            if isFenceLine(line) {
                if let openingLineRange = activeOpeningLineRange,
                   let contentStart = activeContentStart {
                    ranges.append(AppMarkdownBlockCodeRange(
                        contentRange: NSRange(location: contentStart, length: max(lineRange.location - contentStart, 0)),
                        delimiterRanges: [openingLineRange, lineRange]
                    ))
                    activeOpeningLineRange = nil
                    activeContentStart = nil
                } else {
                    activeOpeningLineRange = lineRange
                    activeContentStart = NSMaxRange(lineRange)
                }
            }
            location = NSMaxRange(lineRange)
        }

        if let openingLineRange = activeOpeningLineRange,
           let contentStart = activeContentStart {
            ranges.append(AppMarkdownBlockCodeRange(
                contentRange: NSRange(location: contentStart, length: max(nsMarkdown.length - contentStart, 0)),
                delimiterRanges: [openingLineRange]
            ))
        }

        return ranges
    }

    static func blockCodeRanges(in markdown: String, matching fullRanges: [NSRange]) -> [AppMarkdownBlockCodeRange] {
        guard !fullRanges.isEmpty else {
            return []
        }

        return blockCodeRanges(in: markdown).filter { blockRange in
            fullRanges.contains(blockRange.fullRange)
        }
    }

    private static func inlineRanges(in markdown: String, excluding excludedRanges: [NSRange]) -> [AppMarkdownInlineCodeRange] {
        let nsMarkdown = markdown as NSString
        guard nsMarkdown.length > 0 else {
            return []
        }

        var ranges: [AppMarkdownInlineCodeRange] = []
        var location = 0

        while location < nsMarkdown.length {
            if let excludedRange = excludedRanges.first(where: { NSLocationInRange(location, $0) }) {
                location = NSMaxRange(excludedRange)
                continue
            }

            guard nsMarkdown.character(at: location) == 0x60 else {
                location += 1
                continue
            }

            let delimiterLength = consecutiveBackticks(in: nsMarkdown, from: location)
            let openingLocation = location
            location += delimiterLength

            if let closingLocation = matchingInlineCodeClosingLocation(
                in: nsMarkdown,
                from: location,
                delimiterLength: delimiterLength,
                excluding: excludedRanges
            ) {
                let openingDelimiterRange = NSRange(location: openingLocation, length: delimiterLength)
                let closingDelimiterRange = NSRange(location: closingLocation - delimiterLength, length: delimiterLength)
                let contentRange = NSRange(
                    location: openingLocation + delimiterLength,
                    length: (closingLocation - delimiterLength) - (openingLocation + delimiterLength)
                )
                ranges.append(
                    AppMarkdownInlineCodeRange(
                        fullRange: NSRange(location: openingLocation, length: closingLocation - openingLocation),
                        contentRange: contentRange,
                        delimiterRanges: [openingDelimiterRange, closingDelimiterRange]
                    )
                )
                location = closingLocation
            }

            if location >= nsMarkdown.length || nsMarkdown.character(at: max(location - 1, 0)) != 0x60 {
                location = openingLocation + delimiterLength
            }
        }

        return ranges
    }

    private static func consecutiveBackticks(in markdown: NSString, from location: Int) -> Int {
        var length = 0
        while location + length < markdown.length,
              markdown.character(at: location + length) == 0x60 {
            length += 1
        }
        return max(length, 1)
    }

    private static func matchingInlineCodeClosingLocation(
        in markdown: NSString,
        from startLocation: Int,
        delimiterLength: Int,
        excluding excludedRanges: [NSRange]
    ) -> Int? {
        var location = startLocation

        while location < markdown.length {
            if let excludedRange = excludedRanges.first(where: { NSLocationInRange(location, $0) }) {
                location = NSMaxRange(excludedRange)
                continue
            }

            guard markdown.character(at: location) == 0x60 else {
                location += 1
                continue
            }

            let closingLength = consecutiveBackticks(in: markdown, from: location)
            guard closingLength == delimiterLength else {
                location += max(closingLength, 1)
                continue
            }

            return location + delimiterLength
        }

        return nil
    }
}

struct AppMarkdownCodeRanges {
    let blockRanges: [NSRange]
    let blockContentRanges: [NSRange]
    let blockDelimiterRanges: [NSRange]
    let inlineFullRanges: [NSRange]
    let inlineContentRanges: [NSRange]
    let inlineDelimiterRanges: [NSRange]
}

struct AppMarkdownBlockCodeRange {
    let contentRange: NSRange
    let delimiterRanges: [NSRange]

    var fullRange: NSRange {
        let start = delimiterRanges.first?.location ?? contentRange.location
        let end = max(delimiterRanges.last.map(NSMaxRange) ?? NSMaxRange(contentRange), NSMaxRange(contentRange))
        return NSRange(location: start, length: max(end - start, 0))
    }
}

private struct AppMarkdownInlineCodeRange {
    let fullRange: NSRange
    let contentRange: NSRange
    let delimiterRanges: [NSRange]
}
