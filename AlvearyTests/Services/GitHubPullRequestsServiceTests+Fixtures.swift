enum PullRequestsServiceFixtures {
    // PR 1 appears in both `authored` and `requested` so the merge must OR its flags. The
    // `authored` bucket carries an unmappable edge of each kind — an empty node and a null edge —
    // so the row cursors have to stay aligned with the summaries that survived. `requested` is the
    // only bucket with a next page, so a paging assertion has exactly one bucket to follow.
    static let list = """
{
  "data": {
    "authored": {
      "edges": [
        {
          "cursor": "authored-1",
          "node": {
            "number": 1,
            "title": "Add feature one",
            "url": "https://github.com/octo/alpha/pull/1",
            "state": "OPEN",
            "isDraft": false,
            "author": { "login": "alice", "avatarUrl": "https://avatars.example.com/alice" },
            "headRefName": "feat/one",
            "baseRefName": "main",
            "updatedAt": "2026-07-01T10:00:00Z",
            "additions": 5,
            "deletions": 2,
            "reviewDecision": "REVIEW_REQUIRED",
            "repository": { "nameWithOwner": "octo/alpha" }
          }
        },
        { "cursor": "authored-2", "node": {} },
        null
      ],
      "pageInfo": { "endCursor": "authored-2", "hasNextPage": false }
    },
    "requested": {
      "edges": [
        {
          "cursor": "requested-1",
          "node": {
            "number": 2,
            "title": "Draft work",
            "state": "OPEN",
            "isDraft": true,
            "author": null,
            "updatedAt": "2026-07-10T10:00:00Z",
            "repository": { "nameWithOwner": "octo/beta" }
          }
        },
        {
          "cursor": "requested-2",
          "node": {
            "number": 1,
            "title": "Add feature one (stale)",
            "state": "OPEN",
            "isDraft": false,
            "author": { "login": "alice", "avatarUrl": "https://avatars.example.com/alice" },
            "updatedAt": "2026-07-01T09:00:00Z",
            "repository": { "nameWithOwner": "octo/alpha" }
          }
        }
      ],
      "pageInfo": { "endCursor": "requested-2", "hasNextPage": true }
    },
    "reviewed": {
      "edges": [
        {
          "cursor": "reviewed-1",
          "node": {
            "number": 3,
            "title": "Merged cleanup",
            "state": "MERGED",
            "isDraft": false,
            "author": { "login": "carol", "avatarUrl": null },
            "updatedAt": "2026-06-01T00:00:00Z",
            "repository": { "nameWithOwner": "octo/alpha" }
          }
        }
      ],
      "pageInfo": { "endCursor": "reviewed-1", "hasNextPage": false }
    }
  }
}
"""

    static let samlPartial = """
{
  "data": {
    "authored": {
      "edges": [
        {
          "cursor": "authored-1",
          "node": {
            "number": 1,
            "title": "Add feature one",
            "state": "OPEN",
            "isDraft": false,
            "updatedAt": "2026-07-01T10:00:00Z",
            "repository": { "nameWithOwner": "octo/alpha" }
          }
        },
        null
      ],
      "pageInfo": { "endCursor": "authored-1", "hasNextPage": false }
    },
    "requested": null,
    "reviewed": { "edges": [ null, null ], "pageInfo": { "endCursor": null, "hasNextPage": false } }
  },
  "errors": [
    { "type": "FORBIDDEN", "message": "Resource protected by organization SAML enforcement." },
    { "type": "FORBIDDEN", "message": "Resource protected by organization SAML enforcement." }
  ]
}
"""

    static let detail = """
{
  "data": {
    "viewer": { "login": "afollestad", "avatarUrl": "https://avatars.example.com/afollestad" },
    "repository": {
      "pullRequest": {
        "number": 7,
        "title": "Improve parser",
        "url": "https://github.com/octo/alpha/pull/7",
        "state": "OPEN",
        "isDraft": false,
        "body": "## Summary\\nBetter parsing.",
        "createdAt": "2026-07-01T09:00:00Z",
        "updatedAt": "2026-07-02T09:00:00Z",
        "author": { "login": "alice", "avatarUrl": "https://avatars.example.com/alice" },
        "headRefName": "feat/parser",
        "baseRefName": "main",
        "headRef": { "name": "feat/parser" },
        "additions": 40,
        "deletions": 9,
        "changedFiles": 3,
        "reviewDecision": "REVIEW_REQUIRED",
        "commits": {
          "nodes": [
            {
              "commit": {
                "statusCheckRollup": {
                  "state": "FAILURE",
                  "contexts": {
                    "nodes": [
                      {
                        "__typename": "CheckRun",
                        "name": "build",
                        "status": "COMPLETED",
                        "conclusion": "SUCCESS",
                        "detailsUrl": "https://ci.example.com/build"
                      },
                      {
                        "__typename": "CheckRun",
                        "name": "test",
                        "status": "IN_PROGRESS",
                        "conclusion": null,
                        "detailsUrl": null
                      },
                      {
                        "__typename": "StatusContext",
                        "context": "ci/lint",
                        "state": "FAILURE",
                        "targetUrl": "https://ci.example.com/lint"
                      }
                    ]
                  }
                }
              }
            }
          ]
        },
        "comments": {
          "nodes": [
            {
              "id": "IC_bot1",
              "databaseId": 321,
              "viewerCanUpdate": false,
              "viewerCanDelete": true,
              "author": { "__typename": "Bot", "login": "helper-bot", "avatarUrl": null },
              "body": "Looks promising",
              "createdAt": "2026-07-01T12:00:00Z",
              "reactionGroups": [
                { "content": "HEART", "viewerHasReacted": false, "reactors": { "totalCount": 3 } }
              ]
            }
          ]
        },
        "reviews": {
          "nodes": [
            {
              "id": "PRR_1",
              "databaseId": 555,
              "viewerCanUpdate": true,
              "author": { "__typename": "User", "login": "carol", "avatarUrl": null },
              "state": "APPROVED",
              "body": "Ship it",
              "submittedAt": "2026-07-02T08:00:00Z",
              "reactionGroups": [
                { "content": "ROCKET", "viewerHasReacted": true, "reactors": { "totalCount": 1 } }
              ]
            },
            {
              "id": "PRR_draft",
              "databaseId": 556,
              "viewerCanUpdate": true,
              "author": { "__typename": "User", "login": "viewer", "avatarUrl": null },
              "state": "PENDING",
              "body": "",
              "submittedAt": null,
              "reactionGroups": []
            }
          ]
        },
        "pendingReview": { "nodes": [{ "id": "PRR_draft" }] },
        "reviewRequests": {
          "nodes": [
            {
              "requestedReviewer": { "__typename": "Bot", "login": "copilot", "avatarUrl": null }
            },
            null
          ]
        },
        "timelineItems": {
          "nodes": [
            {
              "__typename": "ConvertToDraftEvent",
              "actor": { "login": "alice", "avatarUrl": null },
              "createdAt": "2026-07-01T08:00:00Z"
            },
            {
              "__typename": "ReadyForReviewEvent",
              "actor": { "login": "alice", "avatarUrl": null },
              "createdAt": "2026-07-02T10:00:00Z"
            },
            {
              "__typename": "PullRequestCommit",
              "commit": {
                "abbreviatedOid": "abc1234",
                "messageHeadline": "Tighten parser bounds",
                "committedDate": "2026-07-02T11:00:00Z",
                "author": { "name": "Alice", "user": { "login": "alice", "avatarUrl": null } }
              }
            },
            {
              "__typename": "ClosedEvent",
              "actor": { "login": "alice", "avatarUrl": null },
              "createdAt": "2026-07-02T12:00:00Z"
            },
            {
              "__typename": "ReopenedEvent",
              "actor": { "login": "alice", "avatarUrl": null },
              "createdAt": "2026-07-02T13:00:00Z"
            },
            {
              "__typename": "ReviewRequestedEvent",
              "actor": { "login": "alice", "avatarUrl": null },
              "createdAt": "2026-07-02T14:00:00Z",
              "requestedReviewer": { "__typename": "User", "login": "carol", "avatarUrl": null }
            },
            null
          ]
        },
        "reviewThreads": {
          "nodes": [
            {
              "id": "PRT_1",
              "path": "Sources/Parser.swift",
              "line": 12,
              "diffSide": "RIGHT",
              "isResolved": false,
              "isOutdated": true,
              "comments": {
                "nodes": [
                  {
                    "id": "PRRC_abc123",
                    "databaseId": 987,
                    "viewerCanUpdate": true,
                    "viewerCanDelete": false,
                    "state": "SUBMITTED",
                    "pullRequestReview": { "id": "PRR_1" },
                    "author": { "login": "carol", "avatarUrl": null },
                    "body": "Handle empty input here.",
                    "createdAt": "2026-07-01T13:00:00Z",
                    "reactionGroups": [
                      { "content": "THUMBS_UP", "viewerHasReacted": true, "reactors": { "totalCount": 2 } },
                      { "content": "EYES", "viewerHasReacted": false, "reactors": { "totalCount": 0 } }
                    ]
                  }
                ]
              }
            },
            {
              "id": "PRT_draft",
              "path": "Sources/Lexer.swift",
              "line": 4,
              "diffSide": "LEFT",
              "isResolved": false,
              "isOutdated": false,
              "comments": {
                "nodes": [
                  {
                    "id": "PRRC_draft",
                    "databaseId": 988,
                    "viewerCanUpdate": true,
                    "viewerCanDelete": true,
                    "state": "PENDING",
                    "pullRequestReview": { "id": "PRR_draft" },
                    "author": { "login": "viewer", "avatarUrl": null },
                    "body": "Not submitted yet.",
                    "createdAt": "2026-07-03T09:00:00Z",
                    "reactionGroups": []
                  }
                ]
              }
            }
          ]
        }
      }
    }
  }
}
"""
}
