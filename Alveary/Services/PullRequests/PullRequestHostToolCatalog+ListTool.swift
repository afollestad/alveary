import AgentCLIKit
import Foundation

// `list_involved_prs`' definition, split out because its description and its five optional inputs
// outgrew the file the rest of the catalog lives in. `internal` rather than `private` so the
// `tools` array in `PullRequestHostToolCatalog.swift` can still reach it.
extension PullRequestHostToolCatalog {
    static let listTool = AgentCLIKit.AgentHostToolDefinition(
        name: listToolName,
        title: "List the GitHub pull requests the user is involved in",
        description: """
        Search GitHub for the pull requests the signed-in user is involved in, newest activity first. This is the tool \
        for "what pull requests am I working on" or "what needs my review": it queries GitHub live, across every \
        repository. These are not only the user's own pull requests — the reviewing side returns other people's, opened \
        by their authors and waiting on this user. Called with no arguments it returns open pull requests only, so it \
        cannot answer a question about a finished one unless status says so. filter narrows to "authored", "reviewing" \
        (asked to review or already reviewed), or "all" (the default). status picks exactly one of open (the default), \
        draft, merged, or closed — GitHub search cannot combine them, so ask for one per call. updated_after and \
        updated_before are UTC YYYY-MM-DD bounds on last activity. limit sets rows per call, 1 to 50 (the default). \
        Involvement is the whole search, so it cannot list an arbitrary repository's pull requests, and it is not \
        list_linked_prs, which reads Alveary's local record of what was attached to one thread by hand. total_count \
        reports how many matched this call; when more remain, next_cursor comes back — call this tool again passing \
        only that cursor to get the next page, and do not repeat filter, status, limit, or the date bounds, which the \
        cursor already carries. warnings names organizations whose results were unavailable, usually because the \
        GitHub CLI token lacks their SSO authorization.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: [
                "filter": HostToolSchema.enumSchema(PullRequestHostToolListFilter.allCases.map(\.rawValue)),
                "status": statusSchema,
                "limit": HostToolSchema.integerSchema(minimum: 1, maximum: PullRequestHostToolLimits.maxListRows),
                "updated_after": HostToolSchema.nonEmptyStringSchema,
                "updated_before": HostToolSchema.nonEmptyStringSchema,
                "cursor": HostToolSchema.nonEmptyStringSchema
            ],
            required: []
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "filter": HostToolSchema.enumSchema(PullRequestHostToolListFilter.allCases.map(\.rawValue)),
                "pull_requests": HostToolSchema.arraySchema(items: listRowSchema),
                "total_count": HostToolSchema.integerSchema(minimum: 0),
                // Present only while a bucket has more to give, so its absence is what says the
                // list is complete.
                "next_cursor": HostToolSchema.stringSchema,
                "warnings": HostToolSchema.arraySchema(items: HostToolSchema.stringSchema)
            ],
            required: ["filter", "pull_requests", "total_count"]
        ),
        annotations: HostToolSchema.readOnlyAnnotations
    )
}
