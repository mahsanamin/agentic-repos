# Cross-Team Framing

Rules for how AI-written content references other teams in internal docs, status reports, weekly reports, and PR discussions. Applies whenever the document might be read by leadership, peer teams, or the CEO/CTO.

These rules exist because political framing in written status, naming peer teams as the gap, the blocker, or the reason, leaks into management copy and creates friction that's not in the team's interest. Honest neutral framing protects credibility and keeps cross-team relationships intact.

## What to avoid

- **Don't name another team as the owner of a gap, blocker, or missing process.**
  - ❌ "Products team hasn't delivered the upstream endpoint"
  - ❌ "Blocked on infrastructure"
  - ❌ "Waiting on backoffice"
  - ❌ "Items' system has not been reported yet"
- **Don't reference unrelated prior incidents from other teams** to strengthen a point against a currently named team. ("X had a similar incident" used as ammunition is a giveaway.)
- **Don't write `Need from: [team X]` / `blocked on [team X]` / `pending [team X] action`** as the framing.

## What to do instead

Frame cross-team situations abstractly. The leadership audience already knows the company context, they don't need names to understand the situation.

- "cross-system API change-notification gap"
- "upstream systems"
- "platform-wide environment setup"
- "a lightweight process across teams would reduce risk"
- "pending platform-wide rollout"
- "upstream domain experts are involved during planning"
- "follow-ups pending, staging proof-of-concept planned"

## Check before writing "blocked on" anything

Before writing "blocked on [team X]" or "pending [team X] action", verify whether your own team has actually raised the ask:

- Was a ticket filed?
- Was a Slack message sent?
- Was a meeting requested?

If no, the next step is yours, not theirs. Write it that way:

- "next step is to raise the ask"
- "pending Example-side initiation"
- "code is ready; no ticket raised yet"

## Company-wide causes

When a slowdown's underlying cause is company-wide (restructuring, cross-team staffing transitions, shared environment issues), describe it that way rather than picking a single team to attribute it to. The CEO and CTO know the company context; honest neutral framing protects credibility without throwing anyone under the bus.

## Why this matters

A status report or PR description that names a peer team as the blocker, when read by leadership, reads as political even when the team did nothing wrong by raising it. The neutral framing, same underlying facts, different lens, surfaces the same engineering reality without the political shape. Both audiences (your leadership and the peer team) come out informed and unembarrassed.
