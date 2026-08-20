// Check-rollup fixtures, split out of `GitHubPullRequestsServiceTests+Fixtures.swift` to keep
// that enum under the body-length limit.
extension PullRequestsServiceFixtures {
    /// A rollup shaped like the ones that put repeated rows in the pane, modelled on the live
    /// `cli/cli#14204` payload. `Release` arrives three times from three runs of one workflow with
    /// **ascending `workflowRun.databaseId` but deliberately scrambled `startedAt`**, so any mapper
    /// that orders by time picks the wrong survivor. `Release` also exists under a *second*
    /// workflow, which must survive as its own row rather than collapsing into the first. `flaky`
    /// re-ran inside a single workflow run, so only the check run ids separate its two nodes.
    /// `legacy/status` is posted twice and has no run ids at all.
    ///
    /// The `startedAt` values are deliberately present but unselected by the query, so nothing
    /// decodes them today. They arm the trap: reintroduce time ordering and the wrong run wins.
    static let detailDuplicateChecks = """
{
  "data": {
    "repository": {
      "pullRequest": {
        "id": "PR_dupe",
        "number": 7,
        "title": "Duplicated checks",
        "state": "OPEN",
        "isDraft": false,
        "body": "",
        "commits": {
          "nodes": [
            {
              "commit": {
                "statusCheckRollup": {
                  "state": "SUCCESS",
                  "contexts": {
                    "nodes": [
                      {
                        "__typename": "CheckRun",
                        "name": "Release",
                        "status": "COMPLETED",
                        "conclusion": "SUCCESS",
                        "detailsUrl": "https://ci.example.com/release/run-2416",
                        "databaseId": 96453362035,
                        "startedAt": "2026-08-20T14:03:07Z",
                        "checkSuite": {
                          "app": { "name": "GitHub Actions" },
                          "workflowRun": { "databaseId": 2416, "workflow": { "name": "PR-Auto-Merge" } }
                        }
                      },
                      {
                        "__typename": "CheckRun",
                        "name": "Release",
                        "status": "COMPLETED",
                        "conclusion": "FAILURE",
                        "detailsUrl": "https://ci.example.com/release/run-2417",
                        "databaseId": 96453367805,
                        "startedAt": "2026-08-20T14:03:09Z",
                        "checkSuite": {
                          "app": { "name": "GitHub Actions" },
                          "workflowRun": { "databaseId": 2417, "workflow": { "name": "PR-Auto-Merge" } }
                        }
                      },
                      {
                        "__typename": "CheckRun",
                        "name": "Release",
                        "status": "COMPLETED",
                        "conclusion": "SUCCESS",
                        "detailsUrl": "https://ci.example.com/release/run-2420",
                        "databaseId": 96453317127,
                        "startedAt": "2026-08-20T14:03:00Z",
                        "checkSuite": {
                          "app": { "name": "GitHub Actions" },
                          "workflowRun": { "databaseId": 2420, "workflow": { "name": "PR-Auto-Merge" } }
                        }
                      },
                      {
                        "__typename": "CheckRun",
                        "name": "Release",
                        "status": "COMPLETED",
                        "conclusion": "SUCCESS",
                        "detailsUrl": "https://ci.example.com/nightly/release",
                        "databaseId": 96453300001,
                        "startedAt": "2026-08-20T14:03:01Z",
                        "checkSuite": {
                          "app": { "name": "GitHub Actions" },
                          "workflowRun": { "databaseId": 2401, "workflow": { "name": "Nightly" } }
                        }
                      },
                      {
                        "__typename": "CheckRun",
                        "name": "flaky",
                        "status": "COMPLETED",
                        "conclusion": "FAILURE",
                        "detailsUrl": "https://ci.example.com/flaky/attempt-1",
                        "databaseId": 100,
                        "startedAt": "2026-08-20T15:00:00Z",
                        "checkSuite": {
                          "app": { "name": "GitHub Actions" },
                          "workflowRun": { "databaseId": 2420, "workflow": { "name": "PR-Auto-Merge" } }
                        }
                      },
                      {
                        "__typename": "CheckRun",
                        "name": "flaky",
                        "status": "COMPLETED",
                        "conclusion": "SUCCESS",
                        "detailsUrl": "https://ci.example.com/flaky/attempt-2",
                        "databaseId": 200,
                        "startedAt": "2026-08-20T14:00:00Z",
                        "checkSuite": {
                          "app": { "name": "GitHub Actions" },
                          "workflowRun": { "databaseId": 2420, "workflow": { "name": "PR-Auto-Merge" } }
                        }
                      },
                      {
                        "__typename": "CheckRun",
                        "name": "mergeability_check",
                        "status": "COMPLETED",
                        "conclusion": "SUCCESS",
                        "detailsUrl": "https://graphite.example.com/mergeability",
                        "databaseId": 300,
                        "startedAt": "2026-08-20T14:00:00Z",
                        "checkSuite": {
                          "app": { "name": "Graphite" },
                          "workflowRun": null
                        }
                      },
                      {
                        "__typename": "StatusContext",
                        "context": "legacy/status",
                        "state": "FAILURE",
                        "targetUrl": "https://ci.example.com/legacy/old",
                        "createdAt": "2026-08-20T14:00:00Z"
                      },
                      {
                        "__typename": "StatusContext",
                        "context": "legacy/status",
                        "state": "SUCCESS",
                        "targetUrl": "https://ci.example.com/legacy/new",
                        "createdAt": "2026-08-20T16:00:00Z"
                      }
                    ]
                  }
                }
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
