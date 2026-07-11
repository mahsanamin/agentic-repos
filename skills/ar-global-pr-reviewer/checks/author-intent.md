# Author-intent check

Before posting a finding, check whether the author already considered the topic. Findings that ignore author intent burn reviewer credibility and produce litigation in PR comments.

## Procedure

For each surviving finding (post-classifier in `classifier.md`):

1. **Read the PR body** for any mention of the topic, the symbol, or the design choice:

   ```bash
   echo "$PR_META" | jq -r '.body'
   ```

   Look for phrases like "skipped X because Y", "intentional, Z", "follow-up in PROJ-XXX", "see ticket comment".

2. **Read commit messages on the branch**:

   ```bash
   git -C "$WORKTREE_DIR" log "origin/$BASE_BRANCH..HEAD" --format='%B'
   ```

   A commit titled `fix(PROJ-123): handle null case but skip empty-list, see ticket` is the author flagging that they considered an edge case and made a deliberate choice.

3. **Look for referenced tickets**, grep PR body + commits for ticket-key patterns:

   ```bash
   grep -oE '[A-Z]{2,}-[0-9]+' <<< "$PR_BODY $COMMIT_MESSAGES" | sort -u
   ```

   For each ticket key, if `gh issue view` or atlassian MCP is available, fetch the ticket and scan for relevant context (acceptance criteria, comments mentioning the design choice).

## How to reframe when author intent is found

Default to a question, not a finding.

**Before** (finding): "Missing null check on `package.getCustomer()`, will NPE if customer is null."

**After** (question): "You mentioned in the PR body that the upstream service guarantees a non-null customer, is that contract documented somewhere? A one-line code comment referencing the invariant would help future readers who can't see the PR description."

## When intent is unclear but plausible

If the topic isn't explicitly addressed but a careful reader could see why the author might have chosen this path: default to **question form**.

- Before: "Should use immutable list here, not `ArrayList`."
- After: "Was `ArrayList` chosen deliberately here (e.g., for downstream mutation), or would `List.copyOf` work?"

## When intent is absent

If no evidence the author considered the topic, the finding stands as-is, assuming the classifier (`classifier.md`) tagged it as PR-INTRODUCED or PR-EXPOSED.

## What this check is NOT

- It is NOT a license for the author to dismiss any finding by claiming "I considered that". The author has to have left a trace, PR body, commit message, ticket comment, code comment. Verbal "I considered it" doesn't count.
- It is NOT a softener for hard bugs. A null-pointer crash is a finding regardless of whether the author "considered" it. Use judgment: if the finding is high-confidence and high-impact, the question form is condescending; just post it.

## When to skip this check

- The finding is high-confidence + high-impact (NPE, security, data corruption). Don't soften.
- The author is a bot (Renovate, Dependabot). Author intent is mechanical; no need to grep ticket comments.
