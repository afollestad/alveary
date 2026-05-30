import BlockInputKit
import Foundation

let appMarkdownImageDefaultAspectRatio: CGFloat = 16.0 / 9.0
let appMarkdownImageMinimumDisplayDimension: CGFloat = 24

extension AppMarkdownParser {
    func appMarkdownDocumentBlocks(
        for input: String,
        fullContent: AttributedString? = nil
    ) throws -> [AppMarkdownDocumentBlock] {
        let matches = AppMarkdownImageSyntaxParser.imageMatchesOutsideCode(in: input)
        guard !matches.isEmpty else {
            if let fullContent {
                return [.markdown(fullContent)]
            }
            return [.markdown(try attributedString(for: input))]
        }

        let source = input as NSString
        var blocks: [AppMarkdownDocumentBlock] = []
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                var fragment = source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                if NSMaxRange(match.range) < source.length {
                    fragment = fragment.appMarkdownDroppingOneTrailingSeparator()
                }
                try appendMarkdownBlock(fragment, to: &blocks)
            }

            blocks.append(.image(AppMarkdownImageBlock(image: match.image)))
            cursor = NSMaxRange(match.range)
            if cursor < source.length,
               let scalar = UnicodeScalar(source.character(at: cursor)),
               CharacterSet.whitespacesAndNewlines.contains(scalar) {
                cursor += 1
            }
        }

        if cursor < source.length {
            try appendMarkdownBlock(source.substring(from: cursor), to: &blocks)
        }

        if blocks.isEmpty {
            if let fullContent {
                return [.markdown(fullContent)]
            }
            return [.markdown(try attributedString(for: input))]
        }
        return blocks
    }

    func appMarkdownDocumentBlocksPreservingSource(
        for input: String,
        fullContent: AttributedString
    ) -> [AppMarkdownDocumentBlock] {
        do {
            return try appMarkdownDocumentBlocks(for: input, fullContent: fullContent)
        } catch {
            return [.markdown(fullContent)]
        }
    }

    private func appendMarkdownBlock(
        _ fragment: String,
        to blocks: inout [AppMarkdownDocumentBlock]
    ) throws {
        guard fragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }
        blocks.append(.markdown(try attributedString(for: fragment)))
    }
}

func appMarkdownByReplacingImageSyntaxWithFallback(in input: String) -> String {
    let matches = AppMarkdownImageSyntaxParser.imageMatchesOutsideCode(in: input).reversed()
    guard !matches.isEmpty else {
        return input
    }

    let result = NSMutableString(string: input)
    for match in matches {
        let fallback = match.image.altText.isEmpty ? match.image.source : match.image.altText
        result.replaceCharacters(in: match.range, with: fallback)
    }
    return result as String
}

func appMarkdownImageDisplaySize(
    for image: BlockInputImage,
    constrainedTo width: CGFloat,
    defaultAspectRatio: CGFloat = appMarkdownImageDefaultAspectRatio
) -> CGSize {
    let availableWidth = max(width, appMarkdownImageMinimumDisplayDimension)
    let aspectRatio = max(defaultAspectRatio, 0.01)
    let sourceWidth: CGFloat
    let sourceHeight: CGFloat

    switch (image.width, image.height) {
    case let (width?, height?):
        sourceWidth = CGFloat(width)
        sourceHeight = CGFloat(height)
    case let (width?, nil):
        sourceWidth = CGFloat(width)
        sourceHeight = sourceWidth / aspectRatio
    case let (nil, height?):
        sourceHeight = CGFloat(height)
        sourceWidth = sourceHeight * aspectRatio
    case (nil, nil):
        sourceWidth = availableWidth
        sourceHeight = availableWidth / aspectRatio
    }

    return appMarkdownConstrainedImageSize(
        width: sourceWidth,
        height: sourceHeight,
        availableWidth: availableWidth
    )
}

enum AppMarkdownImageSourceResolver {
    static func resolvedURL(for source: String, baseURL: URL?) -> URL? {
        if let absoluteURL = URL(string: source), absoluteURL.scheme != nil {
            return absoluteURL
        }

        let decodedSource = source.removingPercentEncoding ?? source
        if decodedSource.hasPrefix("~") {
            let expanded = (decodedSource as NSString).expandingTildeInPath
            guard expanded != decodedSource else {
                return URL(string: source, relativeTo: baseURL)?.absoluteURL
            }
            return URL(fileURLWithPath: expanded)
        }

        if decodedSource.hasPrefix("/") {
            return URL(fileURLWithPath: decodedSource)
        }

        if let baseURL {
            return URL(string: source, relativeTo: baseURL)?.absoluteURL
        }

        return URL(string: source)
    }
}

enum AppMarkdownImageSyntaxParser {
    static func imageMatchesOutsideCode(in text: String) -> [AppMarkdownImageMatch] {
        let codeRanges = AppMarkdownCodeBlockParser.codeRanges(in: text)
        let excludedRanges = codeRanges.blockRanges + codeRanges.inlineFullRanges
        return imageMatches(in: text).filter { match in
            !excludedRanges.contains { NSIntersectionRange($0, match.range).length > 0 }
        }
    }

    private static func imageMatches(in text: String) -> [AppMarkdownImageMatch] {
        let markdownMatches = markdownImageMatches(in: text)
        let htmlMatches = htmlImageMatches(in: text)
        return (markdownMatches + htmlMatches)
            .sorted { $0.range.location < $1.range.location }
            .appMarkdownNonOverlapping()
    }

    private static func markdownImageMatches(in text: String) -> [AppMarkdownImageMatch] {
        markdownImageMatches(in: text, pattern: #"!\[((?:\\.|[^\]\n])*)\]\(<((?:\\.|[^>\n])+)>\)"#) +
            markdownImageMatches(in: text, pattern: #"!\[((?:\\.|[^\]\n])*)\]\(((?:\\.|[^)\n])+)\)"#)
    }

    private static func markdownImageMatches(
        in text: String,
        pattern: String
    ) -> [AppMarkdownImageMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard match.numberOfRanges == 3 else {
                return nil
            }
            let altText = source.substring(with: match.range(at: 1)).appMarkdownUnescapedImageComponent
            let imageSource = source.substring(with: match.range(at: 2))
                .appMarkdownUnescapedImageComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !imageSource.isEmpty else {
                return nil
            }
            return AppMarkdownImageMatch(
                range: match.range,
                image: BlockInputImage(source: imageSource, altText: altText, sourceStyle: .markdown)
            )
        }
    }

    private static func htmlImageMatches(in text: String) -> [AppMarkdownImageMatch] {
        let pattern = #"<img\b([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard match.numberOfRanges == 2 else {
                return nil
            }
            let attributes = attributes(in: source.substring(with: match.range(at: 1)))
            guard let imageSource = attributes["src"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !imageSource.isEmpty else {
                return nil
            }
            return AppMarkdownImageMatch(
                range: match.range,
                image: BlockInputImage(
                    source: imageSource,
                    altText: attributes["alt"] ?? "",
                    width: attributes["width"].flatMap(Int.init),
                    height: attributes["height"].flatMap(Int.init),
                    sourceStyle: .html
                )
            )
        }
    }

    private static func attributes(in source: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }
        let nsSource = source as NSString
        var attributes: [String: String] = [:]
        for match in regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length)) where match.numberOfRanges == 3 {
            let name = nsSource.substring(with: match.range(at: 1)).lowercased()
            var value = nsSource.substring(with: match.range(at: 2))
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            attributes[name] = value.appMarkdownUnescapedHTMLAttribute
        }
        return attributes
    }
}

struct AppMarkdownImageMatch {
    let range: NSRange
    let image: BlockInputImage
}

private func appMarkdownConstrainedImageSize(
    width: CGFloat,
    height: CGFloat,
    availableWidth: CGFloat
) -> CGSize {
    let safeWidth = max(width, appMarkdownImageMinimumDisplayDimension)
    let safeHeight = max(height, appMarkdownImageMinimumDisplayDimension)
    let scale = min(1, availableWidth / safeWidth)
    return CGSize(
        width: ceil(max(appMarkdownImageMinimumDisplayDimension, safeWidth * scale)),
        height: ceil(max(appMarkdownImageMinimumDisplayDimension, safeHeight * scale))
    )
}

private extension Array where Element == AppMarkdownImageMatch {
    func appMarkdownNonOverlapping() -> [AppMarkdownImageMatch] {
        var output: [AppMarkdownImageMatch] = []
        var upperBound = 0
        for match in self where match.range.location >= upperBound {
            output.append(match)
            upperBound = NSMaxRange(match.range)
        }
        return output
    }
}

private extension String {
    var appMarkdownUnescapedImageComponent: String {
        var result = ""
        var escaping = false
        for character in self {
            if escaping {
                result.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        if escaping {
            result.append("\\")
        }
        return result
    }

    var appMarkdownUnescapedHTMLAttribute: String {
        replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    func appMarkdownDroppingOneTrailingSeparator() -> String {
        guard let last = unicodeScalars.last,
              CharacterSet.whitespacesAndNewlines.contains(last) else {
            return self
        }
        return String(dropLast())
    }
}
