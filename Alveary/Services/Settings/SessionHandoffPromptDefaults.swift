enum SessionHandoffPromptDefaults {
    static let defaultPrompt = #"""
Turn the current session into a prompt that another agent can use immediately.

The goal is not to summarize the entire conversation. The goal is to preserve only
the accurate and valuable context that will help the next session make progress
faster while minimizing the initial context window.

## Core Behavior

1. Identify the next-session goal.
2. Use that goal as the relevance filter for everything you include.
3. Review the current session and preserve only the facts that change how the
   next agent should act.
4. Omit instructions, workflow rules, or project conventions that the next
   agent can infer from existing `AGENTS.md` context in the target workspace.
5. Produce a prompt that is ready to send as the first user message in a fresh
   continuation session.

If the user already said what the next session should do, do not ask again. If
the goal is still ambiguous after reading the conversation, infer the most
likely next goal from the latest user request and active work.

## Relevance Rules

Pull forward details like these when they will save the next session from
rediscovering them:

- The user's current objective.
- Files, symbols, commands, URLs, PRs, errors, or branches that matter to the
  next step.
- Decisions that were already made.
- Constraints, preferences, or non-goals the user stated.
- Work that is already done.
- Work that was attempted but failed for a specific reason that still matters.
- Known risks, blockers, or unanswered questions.

Leave out details like these unless the user explicitly asks for a full history:

- A play-by-play of every step taken.
- Resolved dead ends that no longer affect the next session.
- Generic advice the next agent could infer on its own.
- Guidance already covered by relevant `AGENTS.md` files.
- Background context that is unrelated to the stated next goal.

If the user narrows the next-session goal, narrow the handoff aggressively too.

## Writing Guidance

Write for the next agent, not about the next agent.

- Prefer direct, concrete statements over narrative.
- Favor facts, decisions, and next steps over chronology.
- Mention exact file paths and identifiers when they matter.
- If code was changed, say what changed and what remains.
- If verification is still pending, mention what should be checked next.
- Keep the prompt as concise as possible without losing vital information.

When possible, present the handoff as if it were the opening prompt of the next
session rather than a retrospective summary.

## Output Format

Return only the handoff prompt.

Do not start the prompt with meta-commentary like "Continue this work in a fresh
session" - the prompt is already going into a new session, so that framing is
redundant. Jump straight into the substance.

Use this structure, omitting sections that truly do not apply:

Primary goal:
- ...

Current state:
- ...

Relevant files and areas:
- `path/to/file`: why it matters
- `path/to/other_file`: why it matters

Decisions and constraints to preserve:
- ...

Open questions or risks:
- ...

Recommended first steps:
1. ...
2. ...
3. ...
"""#
}
