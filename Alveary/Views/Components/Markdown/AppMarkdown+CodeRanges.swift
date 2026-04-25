import Foundation

enum AppMarkdownCodeBlockParser {
    static func containsCode(in markdown: String) -> Bool {
        let ranges = codeRanges(in: markdown)
        return !ranges.blockRanges.isEmpty || !ranges.inlineContentRanges.isEmpty
    }

    static func codeRanges(in markdown: String) -> AppMarkdownCodeRanges {
        let blockRanges = blockRanges(in: markdown)
        let inlineRanges = inlineRanges(in: markdown, excluding: blockRanges)
        return AppMarkdownCodeRanges(
            blockRanges: blockRanges,
            inlineFullRanges: inlineRanges.map(\.fullRange),
            inlineContentRanges: inlineRanges.map(\.contentRange),
            inlineDelimiterRanges: inlineRanges.flatMap(\.delimiterRanges)
        )
    }

    static func blockRanges(in markdown: String) -> [NSRange] {
        let nsMarkdown = markdown as NSString
        guard nsMarkdown.length > 0 else {
            return []
        }

        var ranges: [NSRange] = []
        var activeBlockStart: Int?
        var location = 0

        while location < nsMarkdown.length {
            let lineRange = nsMarkdown.lineRange(for: NSRange(location: location, length: 0))
            let line = nsMarkdown.substring(with: lineRange)
            if isFenceLine(line) {
                if let blockStart = activeBlockStart {
                    ranges.append(NSRange(location: blockStart, length: NSMaxRange(lineRange) - blockStart))
                    activeBlockStart = nil
                } else {
                    activeBlockStart = lineRange.location
                }
            }
            location = NSMaxRange(lineRange)
        }

        if let activeBlockStart {
            ranges.append(NSRange(location: activeBlockStart, length: nsMarkdown.length - activeBlockStart))
        }

        return ranges
    }

    private static func isFenceLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```")
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
    let inlineFullRanges: [NSRange]
    let inlineContentRanges: [NSRange]
    let inlineDelimiterRanges: [NSRange]

    var allRanges: [NSRange] {
        blockRanges + inlineFullRanges + inlineContentRanges + inlineDelimiterRanges
    }
}

private struct AppMarkdownInlineCodeRange {
    let fullRange: NSRange
    let contentRange: NSRange
    let delimiterRanges: [NSRange]
}
