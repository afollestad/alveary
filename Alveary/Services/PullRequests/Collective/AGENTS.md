## Collective Review

- Keep worker inputs and quorum fixed for a run; settings changes apply only to subsequent runs.
- Stage only through `PullRequestCollectiveReviewStagingService`; workers cannot call host tools or write GitHub state.
- Register collective work in `ConversationWorkActivity` and app shutdown; provider-turn activity does not own these workers.
