# Pull requests

## Ignoring pull requests

Right-click a row on the Pull requests screen, or use the bell button in a pull request's detail pane, to ignore it. That hides it from the list and unsubscribes you from its GitHub notifications. **Show ignored** in the filter menu brings ignored pull requests back, dimmed, so you can stop ignoring them and resubscribe.

Unsubscribing needs the GitHub CLI's `notifications` permission, which `gh auth login` doesn't grant. The first ignore explains why, then shows a one-time code to approve on GitHub, which adds the permission to your existing `gh` sign-in.

GitHub can't list the pull requests you've unsubscribed from, so Alveary keeps the ignore list itself and checks it against GitHub when the list refreshes, at most every five minutes or whenever you press refresh. A pull request leaves the list once it's merged or closed, or once you resubscribe on GitHub.

## Reviews

Reviews use a single agent by default. Choose **Review team** in **Settings → Git → Pull requests** to have 2–5 different models review independently and cross-check each other's findings, proposing only comments a majority supports, with a lead consolidating them. **Manage** edits the lead and peers together, and **Address feedback** has its own agent and permission settings. Nothing is submitted without your confirmation.

Reviews requested through Alveary's MCP tools follow the same setting. A single-agent review stays in the current task, while a team review gets its own task, linked from the conversation.

That task shows the team's progress, failures, and votes. If a reviewer fails, the review pauses before proposing anything: retry the failed reviewers, or continue with the majority that remains. A paused review stays paused after relaunch. **Run details** shows each reviewer's attempts, prompts, responses, and votes, and is kept with the task until you delete it.

A team won't launch if one of its models is unavailable, and checking doesn't spend a paid prompt. If GitHub rate-limits a review, it waits for the reset and resumes where it left off, even after a relaunch, and five limits in a row need a manual retry. The limit is shared with every other tool acting as you. When GitHub refuses a large pull request's full diff, Alveary fetches it through a temporary bare Git repository instead, which can take several minutes. Review tasks don't need a local checkout.

### What reviewers can reach

Review tasks reach GitHub only through Alveary's pull request tools. Your harness connectors, plugins, and MCP servers are withheld, and on Codex and Claude, shell commands have no network access. **Address feedback** tasks are the same, except that they keep network access so they can push. Team workers also run read-only, without your hooks or extra arguments, from a packet Alveary prepares with the full diff and published feedback. The OS doesn't confine them to that packet, and their network isolation isn't guaranteed.

## Attachments

Comment and review attachments need GitHub CLI 2.99.0 or newer and write access to the repository, and upload images and videos through your existing `gh` sign-in. [GitHub comment attachments](github-attachments.md) covers formats, limits, and troubleshooting.
