import Foundation

/// A shared cooldown uses GitHub's resource bucket; secondary limits apply across buckets.
struct GitHubRateLimit: Codable, Equatable, Sendable {
    let resource: String
    let isSecondary: Bool
    let retryAt: Date
    var isResponse = true
    /// Alveary's share of the exhausted window. Optional so waits persisted before the ledger still decode.
    var appUsage: GitHubAppUsage?

    var message: String {
        "\(reason). Try again after \(retryAt.formatted(date: .omitted, time: .shortened)).\(usageSentence)"
    }

    var waitingMessage: String {
        "\(reason). Resuming at \(retryAt.formatted(date: .omitted, time: .shortened)).\(usageSentence)"
    }

    private var reason: String { isSecondary ? "GitHub is temporarily limiting requests" : "GitHub's API quota is exhausted" }

    /// Every tool acting as the user shares one budget, so saying how much of it Alveary spent is what tells the user
    /// whether to look elsewhere.
    private var usageSentence: String {
        guard let usage = appUsage else {
            return ""
        }
        let unit = resource == "graphql" ? "points" : "requests"
        let spent = usage.accountUsed.map { " of the \($0.formatted()) \(unit) spent this hour" } ?? " \(unit) this hour"
        let since = usage.countedSince.map { " (counting since \($0.formatted(date: .omitted, time: .shortened)))" } ?? ""
        return " Alveary used \(usage.appUsed.formatted())\(spent)\(since)."
    }
}

/// Removes `gh api --include` headers before callers decode JSON or parse a diff.
struct GitHubAPIResponse: Sendable {
    let result: ShellResult
    let status: Int?
    let headers: [String: String]
    let queryCost: Int?
    let isRateLimited: Bool
    let isSecondary: Bool

    init(_ raw: ShellResult) {
        var body = raw.stdoutData
        var headers: [String: String] = [:]
        var status: Int?
        while body.starts(with: Data("HTTP/".utf8)) {
            let separator = body.range(of: Data("\r\n\r\n".utf8)) ?? body.range(of: Data("\n\n".utf8))
            guard let separator else { break }
            let lines = (String(data: body[..<separator.lowerBound], encoding: .utf8) ?? "").components(separatedBy: .newlines)
            status = lines.first?.split(separator: " ").dropFirst().first.flatMap { Int($0) }
            headers = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            body = Data(body[separator.upperBound...])
        }
        self.status = status
        self.headers = headers
        result = ShellResult(stdout: (String(data: body, encoding: .utf8) ?? ""), stdoutData: body, stderr: raw.stderr,
                             exitCode: raw.exitCode, stdoutWasTruncated: raw.stdoutWasTruncated,
                             stderrWasTruncated: raw.stderrWasTruncated)
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let data = json?["data"] as? [String: Any]
        queryCost = (data?["rateLimit"] as? [String: Any])?["cost"] as? Int
        let errors = json?["errors"] as? [[String: Any]] ?? []
        let messages = errors.compactMap { $0["message"] as? String } + [json?["message"] as? String ?? "", raw.stderr]
        let message = messages.joined(separator: " ").lowercased()
        isSecondary = message.contains("secondary rate") || message.contains("abuse detection")
        isRateLimited = status == 429 || GitHubPullRequestsService.httpStatusCode(in: raw.stderr) == 429
            || message.contains("rate limit") || isSecondary
            || errors.contains { ($0["type"] as? String).map(Self.rateLimitErrorTypes.contains) == true }
    }

    /// GitHub's GraphQL has reported both spellings; `RATE_LIMIT` (code `graphql_rate_limit`) is current. The type
    /// is what still identifies a limit if GitHub rewords the message the check above relies on.
    private static let rateLimitErrorTypes: Set<String> = ["RATE_LIMITED", "RATE_LIMIT"]

    func cooldown(resource: String, now: Date, consecutiveFailures: Int) -> GitHubRateLimit? {
        let exhausted = headers["x-ratelimit-remaining"] == "0"
        guard isRateLimited || exhausted else { return nil }
        let reset = headers["x-ratelimit-reset"].flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        let retry = headers["retry-after"].flatMap(TimeInterval.init).map { now.addingTimeInterval(max(0, $0)) }
        let retryAt = [retry, exhausted ? reset : nil].compactMap { $0 }.max()
            ?? now.addingTimeInterval(60 * pow(2, Double(min(max(0, consecutiveFailures - 1), 4))))
        return GitHubRateLimit(resource: headers["x-ratelimit-resource"] ?? resource,
                               isSecondary: isSecondary || !exhausted, retryAt: max(now, retryAt))
    }
}
