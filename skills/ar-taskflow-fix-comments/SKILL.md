---
name: ar-taskflow-fix-comments
description: Aggregate and fix PR feedback from SonarQube, CodeRabbit, and human reviewers in priority order, then reply to and resolve the review threads. Standalone skill - run after PR feedback arrives. Say "ar-taskflow-fix-comments" or "fix comments".
disable-model-invocation: false
---

# Task Flow Fix Comments

Gather → Prioritize → Fix → Test → Report → Commit → (repeat)

## 🧭 Learning routing

Follow the rule at `<standards_location>/learning-routing.md` (resolve `standards_location` from `.claude/config_hints.json`): route any learning to a project rule (`docs/ai-rules/`), a framework improvement (`ar-record-improvement`), or conversational-only, never personal auto-memory.

## When to Run

- After CI runs on a PR (SonarQube, CodeRabbit)
- After human reviewers leave comments
- Developer says "ar-taskflow-fix-comments", "fix comments", or "fix PR feedback"
- Optionally with explicit PR number: `ar-taskflow-fix-comments 286`

## Pre-Product

```bash
# Detect PR number
if [ -n "$1" ]; then
  pr_number="$1"
else
  pr_number=$(gh pr view --json number -q '.number' 2>/dev/null)
fi

if [ -z "$pr_number" ]; then
  echo "No PR found for current branch. Provide PR number: ar-taskflow-fix-comments {number}"
  exit 1
fi

# Get repo info
repo_owner=$(gh repo view --json owner -q '.owner.login')
repo_name=$(gh repo view --json name -q '.name')

echo "Fixing feedback for PR #$pr_number ($repo_owner/$repo_name)"
```

## Phase 1, Gather Feedback

Fetch from all three sources in parallel. Each source is optional, skip gracefully if unavailable.

### Iteration Awareness

This skill supports multiple iterations. On each run, detect what was already handled in previous iterations by scanning for our own replies on the PR:

```bash
# Fetch ALL replies on the PR to find our previous "Fixed in {sha}" markers
gh api repos/$repo_owner/$repo_name/pulls/$pr_number/comments \
  --jq '[.[] | select(.body | test("Fixed in [a-f0-9]{7,40}|Acknowledged|Not fixing")) | {
    in_reply_to_id: .in_reply_to_id,
    body: .body
  }]'
```

Build a set of `already_handled_ids` from `in_reply_to_id` values. Any comment whose ID is in this set is **skipped**, it was resolved in a previous iteration.

For SonarQube: issues that no longer appear in `fetch-issues.sh` output are already resolved (SonarQube tracks this automatically on re-scan).

### Source A: SonarQube Issues

```bash
# Check if SonarQube is configured
if [ -n "$SONARQUBE_URL" ] && [ -n "$SONARQUBE_TOKEN" ]; then
  "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/scripts/ar-sonarqube/fetch-issues.sh" 2>/dev/null || echo '{"error": "fetch-issues.sh not found. Run ./install.sh from the framework repo to install framework scripts."}'
else
  echo "SonarQube not configured. Skipping SonarQube issues."
fi
```

**If SonarQube is not configured**, guide the user through setup:

```
SonarQube integration is not configured. To enable it:

1. Generate a token at: https://sonarqube.your-org.example/account/security
   → Click "Generate Tokens" → name it (e.g., "claude-code") → copy the token

2. Add these environment variables to your shell profile (~/.zshrc or ~/.bashrc):

   export SONARQUBE_URL="https://sonarqube.your-org.example"
   export SONARQUBE_TOKEN="your-token-here"

3. Reload your shell: source ~/.zshrc

4. Re-run ar-taskflow-fix-comments to include SonarQube issues.

Continuing without SonarQube for now...
```

Returns structured JSON with rule IDs, file paths, line numbers, severity. Only returns OPEN/CONFIRMED/REOPENED issues, previously fixed issues are automatically excluded.

### Source B: CodeRabbit Comments

```bash
gh api repos/$repo_owner/$repo_name/pulls/$pr_number/comments \
  --jq '[.[] | select(.user.login == "coderabbitai[bot]") | {
    id: .id,
    path: .path,
    line: .line,
    body: .body,
    in_reply_to_id: .in_reply_to_id,
    created_at: .created_at
  }]'
```

Parse each comment body to extract:
- **Severity** from CodeRabbit's markers: `Potential issue`, `Refactor`, `Nitpick`
- **Suggested fix** from `<details><summary>` blocks if present
- **Resolution status**, check if reply thread contains resolution

**Filter out already-handled comments:**
- Skip if comment ID is in `already_handled_ids` (we already replied)
- Skip if `in_reply_to_id` is set (it's a reply, not a top-level comment)
- Skip if the comment's `path:line` no longer exists in the current code (stale from old commit)

### Source C: Human Reviewer Comments

```bash
# Inline review comments (excluding bots)
gh api repos/$repo_owner/$repo_name/pulls/$pr_number/comments \
  --jq '[.[] | select(.user.login != "coderabbitai[bot]" and .user.type != "Bot") | {
    id: .id,
    user: .user.login,
    path: .path,
    line: .line,
    body: .body
  }]'

# Top-level review bodies
gh api repos/$repo_owner/$repo_name/pulls/$pr_number/reviews \
  --jq '[.[] | select(.body != "" and .body != null and .user.type != "Bot") | {
    id: .id,
    user: .user.login,
    state: .state,
    body: .body
  }]'
```

Filter out comments already in `already_handled_ids`.

### Unified Summary

After gathering and filtering, output:

```
## PR #${pr_number} Feedback Summary (Iteration {n})

- SonarQube: {n} new issues ({n} auto-fixable, {n} manual)
- CodeRabbit: {n} unresolved comments ({n} already handled in previous runs)
- Human reviewers: {n} new comments ({n} already handled)

{If all zero: "All feedback resolved! No new issues found."}

Processing in priority order...
```

**If no new issues found:** Skip to Phase 5 (integration tests) to do a final verification, then report clean.

## Phase 2, Fix in Priority Order

### Priority 1: SonarQube (highest confidence)

SonarQube issues have precise rule IDs and locations. Fix strategy by category:

| Category | Action |
|----------|--------|
| Unused imports, variables, fields | Auto-fix (remove) |
| Empty blocks (catch, if, etc.) | Auto-fix (add comment or remove) |
| Missing assertions in tests | Auto-fix (add meaningful assertion) |
| Code style (naming, formatting) | Auto-fix |
| Cognitive complexity (S3776) | Flag for manual review |
| Security issues | **NEVER auto-fix**, flag for manual review |
| Concurrency issues | Flag for manual review |

For each auto-fixable issue:
1. Read the affected file at the reported line
2. Apply the fix following project coding rules
3. Verify the fix doesn't break surrounding code

### Priority 2: CodeRabbit (verify before fixing)

CodeRabbit suggestions require validation, they can be wrong or stale.

For each unresolved comment:
1. Read the affected code at the reported line
2. Read surrounding context (the full method or class, not just the line)
3. Analyze whether the suggestion is valid against the **current** code (not the diff it reviewed)
4. Decision:
   - **Valid** → apply fix
   - **Invalid/Disagree** → draft a substantive reply explaining why
   - **Ambiguous** → flag for manual review

**CodeRabbit Reply Quality:**

Replies to CodeRabbit must be substantive, not just "noted" or "won't fix". Explain the reasoning so the comment thread serves as documentation:

| Scenario | Reply Format |
|----------|-------------|
| Fixed | "Fixed in {sha}, {what was changed}" |
| Intentional design | "This is intentional: {reason}. {context about why the current approach is correct}" |
| Already handled elsewhere | "This is handled by {class/method} at {file}:{line}, {brief explanation}" |
| Disagree with suggestion | "The suggested approach would {problem}. Current code {why it's better} because {reason}" |
| Will address separately | "Valid point, tracking as {ticket} to address in a dedicated PR" |

### Priority 3: Human Comments (mostly manual)

Parse comment intent:

| Intent | Action |
|--------|--------|
| Clear fix request with specific change | Attempt fix, verify |
| Question ("should we...?", "why...?") | Flag for developer to respond |
| Discussion / opinion | Skip |
| Approval / praise | Skip |

For fix requests: attempt the fix, but always present to user for approval before committing.

## Phase 3, Report

Output a structured summary:

```markdown
## PR Feedback Fix Summary, PR #{pr_number}

### SonarQube ({n} fixed, {n} manual)
{For each fixed issue:}
{status_emoji} {file}:{line} ({rule_id}), {description}

{For each manual issue:}
{warning_emoji} {file}:{line} ({rule_id}), {description} (needs manual review)

### CodeRabbit ({n} fixed, {n} replied, {n} manual)
{For each fixed:}
{status_emoji} {file}:{line}, {description}
{For each reply:}
{comment_emoji} {file}:{line}, Replied: {reason}
{For each manual:}
{warning_emoji} {file}:{line}, {description} (needs review)

### Human Reviews ({n} fixed, {n} flagged)
{For each:}
{status_emoji_or_warning} @{reviewer}: "{comment_summary}", {action_taken}

---

Ready to commit fixes? (y/n)
```

**Wait for user approval before committing.**

## Phase 4, Commit + Reply

On user approval:

### Commit

**ALWAYS create a NEW commit**, never amend the previous one.

```bash
git add {fixed_files}
git commit -m "[{namespace}-XXX] Fix PR feedback (iteration {n}): {n} SonarQube, {n} CodeRabbit, {n} reviewer issues"
git push
```

Follow the Post-Review Fix Commits rule from the ar-taskflow skill: no force push, no amend.

### Reply on PR

Replies serve as **iteration markers**, they let the next run know which comments are already handled.

| Source | Reply Strategy |
|--------|---------------|
| SonarQube | No reply needed, SonarQube re-scans automatically on push |
| CodeRabbit (fixed) | Reply: "Fixed in {commit_sha}, {brief description of what changed}" |
| CodeRabbit (disagree) | Substantive reply explaining why (see CodeRabbit Reply Quality table) |
| Human (fixed) | Reply: "Fixed in {commit_sha}, {brief description}" |
| Human (skipped) | No reply, developer handles manually |

```bash
# Reply to a PR comment
gh api repos/$repo_owner/$repo_name/pulls/$pr_number/comments/{comment_id}/replies \
  -f body="{reply_text}"
```

**Show all proposed replies to user before posting.** Wait for approval.

**Why replies matter for iterations:** Each reply creates a trace on the PR. On the next run, Phase 1 scans for replies containing "Fixed in" / "Acknowledged" / "Not fixing" to build the `already_handled_ids` set. Without replies, the same comments would be re-processed every iteration.

### Resolve the thread (after each reply)

A reply alone leaves the thread in GitHub's `isResolved: false` state, the PR UI surfaces it as an open / unaddressed comment, so reviewers read it as work not yet done even though you replied. After posting a reply, mark the thread **resolved** when the discussion is settled:

| Situation | Action |
|-----------|--------|
| Fixed in code + replied with the commit ref ("Fixed in {sha}") | **Auto-resolve**, the thread is settled |
| Skipped with substantive reasoning + reviewer/bot acknowledged it ("understood", "noted") | **Auto-resolve**, discussion closed |
| Skipped with substantive reasoning, no acknowledgment yet | **Leave open**, reviewer may push back |
| Open question to the reviewer (asking for clarification) | **Leave open**, waiting on their response |
| Reply still under discussion (back-and-forth in progress) | **Leave open** |

Thread IDs are different from comment IDs, threads are wrapper objects above comments. One lookup, one mutation:

```bash
# Get the unresolved thread id for a given comment
thread_id=$(gh api graphql -f query='
  query {
    repository(owner: "{owner}", name: "{repo}") {
      pullRequest(number: {pr_number}) {
        reviewThreads(first: 50) {
          nodes { id isResolved comments(first: 1) { nodes { databaseId } } }
        }
      }
    }
  }' | jq -r --argjson cid {comment_id} \
    '.data.repository.pullRequest.reviewThreads.nodes[]
       | select(.comments.nodes[0].databaseId == $cid and .isResolved == false)
       | .id')

# Resolve it
gh api graphql -f query="mutation { resolveReviewThread(input: { threadId: \"$thread_id\" }) { thread { isResolved } } }"
```

**CodeRabbit caveat:** the bot *sometimes* auto-resolves its own threads after acknowledging a reply (e.g. when its review-confirmation message lands) and sometimes doesn't, don't assume the bot's acknowledgment auto-resolves. Verify each thread's `isResolved` state rather than assuming.

## Phase 5, Integration Tests (MANDATORY)

**After all fixes are committed and pushed, run the project's integration/unit test suite to verify nothing is broken.**

```bash
# Use the project's test command: `verify.full_command` / `test_command` from
# config_hints.json (or .claude/skill.config), else the command documented in the repo.
# Prefer verify.full_command over the default test command, the default often SKIPS
# opt-in/guarded integration suites, giving a false green.
```

**INVOKE AGENT: a_sag_test_runner (background)**, it runs `verify.full_command` when set and flags any opt-in/tagged suite the command did not execute. A pass with a skipped-suite warning is **not** a clean green; run the named suite before declaring fixes verified.

1. Invoke `a_sag_test_runner` via the Task tool (subagent_type: `a_sag_test_runner`); its instructions load automatically (from agentic-devkit).
2. Run the full test suite
3. Review results:
   - **All pass** → proceed to iteration check
   - **Failures** → STOP. Show failing tests. Ask user:
     ```
     Integration tests failed after fixing PR feedback:

     {list failing tests with file:line}

     Options:
     1. Fix the failing tests now (then re-run)
     2. Revert the last commit and investigate
     3. Skip tests (proceed at your own risk)
     ```
   - If user chooses option 1: fix tests, create another commit, re-run tests
   - If user chooses option 2: `git revert HEAD` and stop

**Do NOT skip this phase.** PR feedback fixes (especially CodeRabbit suggestions) can introduce regressions.

## Phase 6, Iteration Check

After tests pass, check if new feedback has arrived (CI re-runs after push trigger new SonarQube/CodeRabbit comments):

```
All fixes committed, pushed, and tests passing.

Would you like to:
1. Wait for CI and run again → I'll re-gather feedback after CI completes
2. Done → All current feedback addressed
```

If user chooses option 1: wait for user to say "ready" or "run again", then restart from Phase 1. The iteration awareness in Phase 1 ensures previously handled comments are skipped.

**Typical iteration flow:**
```
Iteration 1: Fix SonarQube + CodeRabbit comments → commit → push → tests pass
                                                                      ↓
                                                            CI re-runs on new push
                                                                      ↓
Iteration 2: New SonarQube issues? New CodeRabbit comments? → fix → commit → push → tests pass
                                                                      ↓
Iteration 3: All clean → done
```

## Relationship to ar-taskflow

This skill is **standalone**, not embedded in ar-taskflow phases:

```
ar-taskflow (Phase 0-4) → commit → push → create PR
                                               |
                                     CI runs (SonarQube, CodeRabbit, reviews)
                                               |
                                     ar-taskflow-fix-comments  (iteration 1)
                                               |
                                     commit fixes → push → tests pass
                                               |
                                     CI re-runs → new feedback?
                                               |
                                     ar-taskflow-fix-comments  (iteration 2)
                                               |
                                     All clean → done
```

## Dependencies

- `gh` CLI, for fetching PR comments and posting replies
- `"${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/scripts/ar-sonarqube/fetch-issues.sh"`, for SonarQube (optional, installed globally by framework)
- `SONARQUBE_URL` + `SONARQUBE_TOKEN`, for SonarQube (optional, skip if not set)
- Project test suite, for Phase 5 integration tests

## Notes

- Each source is independent, skill works with any combination (SonarQube only, CodeRabbit only, human only, or all three)
- Batch similar issues (e.g., multiple "add null check" comments) into logical groups
- Stale CodeRabbit comments (from old commits) are filtered by checking against current file content
- All replies are shown to user for approval before posting, never auto-post
- **Iteration safety:** Replies on PR serve as the resolution trail, they prevent re-processing the same comments across iterations
- **Test safety:** Integration tests run after every iteration to catch regressions from feedback fixes
