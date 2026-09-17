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

## Pre-Flight

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

# SAFETY: verify the current checkout matches the PR before any edit/commit.
# Without this, running with an explicit PR number from the wrong branch (e.g. main) would
# apply fixes and push them to whatever branch is checked out, not to the PR.
# Verify by COMMIT (headRefOid), not just branch name: a stale or same-named local
# branch can pass a name check while HEAD points at a different commit, so the later
# commit/push would run on the wrong checkout.
# Verify the PR's STATE too: headRefOid alone cannot catch a merged/closed PR, because a
# merged PR's head stays pinned at the merge-time commit, which is exactly what the local
# checkout still has, so the OID check below passes cleanly on a dead branch.
# ONE snapshot, five fields. Fetching them in five separate calls lets each observe a
# different revision of the PR, so the gates below would validate a tuple that never existed
# at any single moment: an OID from before a push checked against a state from after a merge.
pr_meta=$(gh pr view "$pr_number" --json headRefName,headRefOid,isCrossRepository,state,baseRefName 2>/dev/null)
if [ -z "$pr_meta" ]; then
  echo "Could not read PR #$pr_number metadata. Aborting before any change."
  exit 1
fi
pr_head_branch=$(printf '%s' "$pr_meta" | jq -r '.headRefName // empty')
pr_head_oid=$(printf '%s' "$pr_meta" | jq -r '.headRefOid // empty')
pr_is_cross_repo=$(printf '%s' "$pr_meta" | jq -r 'if .isCrossRepository == null then "" else (.isCrossRepository|tostring) end')
pr_state=$(printf '%s' "$pr_meta" | jq -r '.state // empty')
pr_base_branch=$(printf '%s' "$pr_meta" | jq -r '.baseRefName // empty')
current_branch=$(git branch --show-current 2>/dev/null)
current_oid=$(git rev-parse HEAD 2>/dev/null)

if [ -z "$pr_head_branch" ] || [ -z "$pr_head_oid" ]; then
  echo "Could not resolve head branch/commit for PR #$pr_number. Aborting before any change."
  exit 1
fi
# Both the MERGED and CLOSED paths below interpolate $pr_base_branch straight into git
# commands. An empty value silently produces `git fetch origin ` and `origin/`, which either
# errors confusingly or resolves to something unintended. Abort before either path can run.
if [ -z "$pr_base_branch" ]; then
  echo "Could not resolve the base branch for PR #$pr_number. Aborting before any change."
  exit 1
fi
if [ "$pr_is_cross_repo" = "true" ]; then
  # Fork PRs are unsupported: this skill pushes fix commits to the PR head, but the head lives
  # on the contributor's fork, not a branch this checkout can push to. Re-running would not help
  # (the PR stays cross-repository), so do not suggest it. Handle fork feedback manually.
  echo "PR #$pr_number is from a fork (cross-repository), unsupported by this skill."
  echo "Fixing fork-PR feedback requires push access to the contributor's fork branch, which"
  echo "this flow does not set up. Apply fixes manually, or ask the contributor to push them."
  exit 1
elif [ "$pr_is_cross_repo" != "false" ]; then
  # Fail closed: if the cross-repo lookup failed or returned an unexpected value, do NOT
  # assume same-repo. A fork PR could otherwise slip past and push to the local default target.
  echo "Could not determine whether PR #$pr_number is cross-repository. Aborting before any change."
  exit 1
fi
# ORDER MATTERS: resolve the PR's state BEFORE any assertion about the local checkout,
# the OID comparison included. Every check below this block compares local state against the
# PR head; on a MERGED/CLOSED PR the head branch is usually deleted, so those comparisons
# abort with advice that cannot be followed and the fix-forward guidance, the whole point of
# handling a merged PR, becomes unreachable.
#
# The concrete case: PR merges with auto-delete-head-branch on, the user runs
# `git checkout main && git pull`, an automated reviewer posts minutes later (normal, see
# "Post-merge feedback" below), and the user re-runs this skill. current_oid is now main's
# tip, not the merge-time head, so an OID check placed above this block fires first and says
# "git checkout <branch-that-no-longer-exists> && git pull". State depends only on `gh` data
# and no local state at all, so it is the correct first gate.
if [ -z "$pr_state" ]; then
  # Fail closed: an unknown state could be MERGED, and the same-branch push below would then
  # resurrect a deleted remote branch with no PR attached.
  echo "Could not determine the state of PR #$pr_number. Aborting before any change."
  exit 1
fi
# MERGED and CLOSED are NOT the same case and must not share a branch. `gh pr view --json
# state` returns OPEN | CLOSED | MERGED, where CLOSED means closed *without* merging.
# Only a MERGED PR's changes are in the base branch, so only MERGED justifies "the finding
# is now live in $pr_base_branch, fix forward from there". Telling that to someone on a
# closed-unmerged PR sends them to fix code that was never merged.
# Enumerate the states explicitly. `!= "OPEN"` as a catch-all folds every value GitHub might
# add, and any unexpected string, into the CLOSED branch, which then prints "(closed without
# merging)" about a state that is nothing of the kind and routes the run down advice that does
# not apply. Anything not in this list aborts, fail-closed: an unknown state could be MERGED.
case "$pr_state" in
  OPEN|MERGED|CLOSED) ;;
  *)
    echo "PR #$pr_number reports an unrecognised state '$pr_state'. Aborting rather than guessing which path applies."
    exit 1
    ;;
esac
if [ "$pr_state" = "MERGED" ]; then
  echo "PR #$pr_number is MERGED, this skill's same-branch push does not apply."
  echo "Its head branch '$pr_head_branch' was likely deleted on merge, so pushing would recreate"
  echo "a dead branch and strand the fixes on a branch with no open PR."
  echo "The feedback is not stale: any valid finding is now live in the base branch '$pr_base_branch'."
  echo "Fix forward instead, see 'Post-merge feedback (fix-forward)':"
  echo "  git fetch origin $pr_base_branch"
  echo "  git checkout -b {new-branch} origin/$pr_base_branch   # then re-run this skill there"
  echo "and open the follow-up PR back into '$pr_base_branch'. Aborting the same-branch path."
  exit 1
fi
if [ "$pr_state" = "CLOSED" ]; then
  # CLOSED means closed *without* merging (MERGED was handled above, and any other value
  # already aborted). The changes were never merged, so the findings are NOT live in the base
  # branch and fix-forward-from-base is wrong advice. The head branch often still exists here,
  # so the right move is a human decision about the PR itself, not an automated push.
  echo "PR #$pr_number is CLOSED (closed without merging), this skill does not apply."
  echo "Its changes were never merged, so the findings are NOT live in '$pr_base_branch' and"
  echo "fixing forward from the base branch would be fixing code this PR never landed."
  echo "Decide what the PR should be first:"
  echo "  - Still wanted? Reopen it (gh pr reopen $pr_number), then re-run this skill."
  echo "  - Superseded/abandoned? The feedback most likely dies with it, no action needed."
  echo "Aborting rather than guessing."
  exit 1
fi
# From here the PR is OPEN, so its head branch exists and comparing the local checkout
# against it is meaningful.
if [ "$pr_head_oid" != "$current_oid" ]; then
  # Behind the PR head is the ordinary state after a colleague's or a bot's commit, so a clean
  # tree that is a strict ancestor fast-forwards instead of aborting with advice nobody executes.
  git fetch --quiet origin "$pr_head_branch" 2>/dev/null
  if [ -z "$(git status --porcelain --untracked-files=no)" ] \
     && git merge-base --is-ancestor "$current_oid" "$pr_head_oid" 2>/dev/null; then
    git merge --ff-only "$pr_head_oid" && current_oid=$(git rev-parse HEAD)
    echo "Fast-forwarded to PR head ${pr_head_oid:0:7}."
  fi
fi
if [ "$pr_head_oid" != "$current_oid" ]; then
  echo "Checkout mismatch: PR #$pr_number head is '$pr_head_branch' @ ${pr_head_oid:0:7}"
  echo "but current branch is '$current_branch' @ ${current_oid:0:7} and cannot fast-forward."
  echo "Sync to the PR head first:  git checkout $pr_head_branch && git pull   (then re-run). Aborting."
  exit 1
fi
# Require a clean tree before editing anything. Matching the PR head proves WHICH commit is
# checked out, not that the working tree is clean. With unrelated edits already present in a
# file a fix touches, `git add {fixed_files}` sweeps them into the feedback commit.
# Tracked changes only: an untracked scratch file cannot be swept into `git add {fixed_files}`,
# and aborting on one stalled every run that had a stray note or an un-ignored build output.
dirty=$(git status --porcelain --untracked-files=no 2>/dev/null)
if [ -n "$dirty" ]; then
  echo "Working tree is not clean, refusing to edit before the state is resolved:"
  printf '%s\n' "$dirty"
  echo "Commit, stash, or discard these first, or run this skill in a fresh worktree. Aborting."
  exit 1
fi
# The OID match is necessary but NOT sufficient: a different local branch can point at the
# same commit. Assert the checked-out branch is the PR head branch by name, and that its
# upstream is that branch on origin; otherwise the push below can follow *that* branch's
# upstream and update the wrong remote ref.
if [ "$current_branch" != "$pr_head_branch" ]; then
  echo "Branch mismatch: HEAD matches PR #$pr_number's commit, but the checked-out branch is"
  echo "'$current_branch', not the PR head branch '$pr_head_branch'. A push from here could"
  echo "update the wrong remote branch. Run:  git checkout $pr_head_branch   (then re-run). Aborting."
  exit 1
fi
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
if [ -z "$upstream" ]; then
  # A worktree created with `git worktree add -b` has no upstream yet; the push below uses an
  # explicit refspec anyway, so set the tracking branch rather than aborting a fine state.
  git branch --set-upstream-to="origin/$pr_head_branch" >/dev/null 2>&1 && upstream="origin/$pr_head_branch"
fi
if [ "$upstream" != "origin/$pr_head_branch" ]; then
  echo "Upstream mismatch: '$current_branch' tracks '${upstream:-<none>}', expected 'origin/$pr_head_branch'."
  echo "Fix with:  git branch --set-upstream-to=origin/$pr_head_branch   (then re-run). Aborting."
  exit 1
fi
# Every check above is about the branch NAME; none of them establishes that the remote called
# `origin` is the repository this PR lives in. `git push origin "HEAD:$pr_head_branch"` makes
# that assumption load-bearing: a clone whose `origin` points at a personal fork, a mirror, or
# a renamed repo passes the branch and upstream checks and then pushes the fixes to the wrong
# repository entirely. The cross-repo gate above rules out fork *PRs*, not a misconfigured
# local remote. Compare the two directly.
#
# Check the PUSH urls, not the fetch url. `git remote get-url origin` returns the fetch URL,
# but `git push` uses `remote.origin.pushurl` when it is set, and a remote may carry several
# pushurls, in which case push writes to all of them. Validating only the fetch URL therefore
# validates a URL the push may never touch. `--push --all` yields exactly the set push will
# use (falling back to the fetch URL when no pushurl is configured), so every entry must match.
pr_head_repo=$(gh pr view "$pr_number" --json headRepositoryOwner,headRepository \
  -q '"\(.headRepositoryOwner.login)/\(.headRepository.name)"' 2>/dev/null)
if [ -z "$pr_head_repo" ]; then
  echo "Could not resolve the repository PR #$pr_number lives in."
  echo "Refusing to push without confirming the destination. Aborting."
  exit 1
fi
push_urls=$(git remote get-url --push --all origin 2>/dev/null)
if [ -z "$push_urls" ]; then
  echo "Could not resolve any push URL for 'origin'. Refusing to push blind. Aborting."
  exit 1
fi
while IFS= read -r push_url; do
  [ -z "$push_url" ] && continue
  # Compare case-INSENSITIVELY: GitHub owner/repo names are case-preserving but not
  # case-sensitive, so an origin of `Acme/repo` against a `gh` value of `acme/repo` is the
  # same repository and must not abort the run.
  push_repo=$(printf '%s\n' "$push_url" \
    | sed -E 's#^git@[^:]+:##; s#^ssh://git@[^/]+/##; s#^https?://[^/]+/##; s#\.git$##' \
    | tr '[:upper:]' '[:lower:]')
  if [ "$push_repo" != "$(printf '%s' "$pr_head_repo" | tr '[:upper:]' '[:lower:]')" ]; then
    echo "Remote mismatch: PR #$pr_number lives in '$pr_head_repo', but a push URL on 'origin'"
    echo "points at '$push_repo' ($push_url)."
    echo "Pushing would update the wrong repository. Point origin at '$pr_head_repo' (or run this"
    echo "skill from a clone of it) and re-run. Aborting."
    exit 1
  fi
done <<EOF
$push_urls
EOF

echo "Fixing feedback for PR #$pr_number ($repo_owner/$repo_name) on branch $current_branch @ ${current_oid:0:7}"
```

## Post-merge feedback (fix-forward)

Automated reviewers can post minutes **after** a merge, so feedback on a MERGED (or CLOSED) PR is normal and its findings are usually still valid, they are now live defects in the base branch. The Pre-Flight state gate stops only the **same-branch push**, never the work. Do not report a post-merge review as stale, and do not drop it.

When the gate fires, take the fix-forward route:

1. **Branch off the current base**, not the dead head: `git fetch origin {base_branch}` then `git checkout -b {new-branch} origin/{base_branch}`. Name the branch by the same ticket, marked as a follow-up.
2. **Gather and fix on that branch using the merged PR's comments.** Phases 1-3 (gather, prioritize, fix, report) apply unchanged, read them from the merged PR. The Pre-Flight gate will keep refusing the merged PR number, so drive these phases directly rather than re-invoking the skill against it; verify each finding still reproduces in the base before fixing it.
3. **Open the follow-up PR back into that same base branch**, the base the merged PR went into, not the repo default. The findings belong where the code landed. From then on this skill runs normally against the follow-up PR, whose own Pre-Flight passes.
4. **Never `git push` on the merged PR's head branch.** A deleted head branch that reappears with commits and no PR is invisible work; if a run already did this, delete the resurrected remote branch after moving the commits onto the follow-up branch.
5. **Reply on the original (merged) PR's threads anyway**, see Phase 4's merged-PR disposition. The reply points at the follow-up PR, so the trail is not lost.

Findings that a re-check proves genuinely obsolete (the merge itself resolved them) still get a "Stale / no longer applies (why)" reply; that is a verified disposition, not a skipped one.

## Phase 1, Gather Feedback

Fetch from all three sources in parallel. Each source is optional, skip gracefully if unavailable.

### Iteration Awareness

This skill supports multiple iterations. On each run, detect what was already handled in previous iterations by scanning for our own replies on the PR:

```bash
# Fetch ALL replies on the PR to find our previous disposition markers.
# This pattern MUST cover every reply shape this skill can emit: the Phase 4 marker line AND
# the Phase 2 "CodeRabbit Reply Quality" formats, which are prose-led ("This is intentional: …",
# "This is handled by …") rather than token-led. A shape the parser doesn't recognise reads as
# "never answered", so the next run re-processes the comment and posts a duplicate reply.
# The "i" flag is required: jq's test() is case-sensitive by default, so a bare "Intentional"
# alternative silently misses the table's lowercase "This is intentional:".
#
# TWO filters, and both are load-bearing:
#   1. AUTHOR. Only OUR replies count as a disposition. Without this the scan reads every
#      comment on the PR, so a reviewer writing "the suggested approach would break X" or
#      "I am tracking that separately" marks their own thread's parent as already handled, and
#      that finding is skipped silently on every later run. A missed finding is worse than
#      a duplicate reply: the duplicate is visible, the miss is not.
#   2. ANCHORED tokens. Every disposition this skill emits leads the body (see the Phase 4
#      reply table), so anchor each alternative with `^`. Matching "Deferred" or "handled by"
#      as a free-floating substring turns ordinary reviewer prose into a disposition marker.
# Every Bash call is a fresh shell, so re-derive the inputs here instead of trusting an earlier
# fence. An empty $me matches no reply and reads every run as round 1, which is how the cap
# never fires; an empty $pr_number hits the wrong endpoint.
pr_number=${pr_number:-$(gh pr view --json number -q .number)}
repo_owner=${repo_owner:-$(gh repo view --json owner -q .owner.login)}
repo_name=${repo_name:-$(gh repo view --json name -q .name)}
me=${me:-$(gh api user -q .login)}
# Pipe to a real jq: `gh api --jq` takes the expression only and does not accept --arg.
# `jq -s 'add'` merges the paginated pages into ONE array; without it each page arrives as
# its own JSON document and the filter emits a separate result per page. Do NOT reach for
# `gh api --slurp`: the flag is absent from older gh, and 2.46 aborts on it with
# `unknown flag`, which takes down the whole gather.
gh api repos/$repo_owner/$repo_name/pulls/$pr_number/comments --paginate \
  | jq -s --arg me "$me" 'add // [] | [.[]
    | select(.user.login == $me)
    | select((.body // "") | test("<!-- ar-fix round=|^(Fixed in [a-f0-9]{7,40}|Fixed forward in|Fixing forward in|Acknowledged|Not fixing|Intentional|Handled elsewhere|Deferred to follow-up|Stale / no longer applies|This is intentional|This is handled by|The suggested approach would|Valid point, tracking as|This belongs in its own PR|Needs human review|Same class as)"; "i")) | {
    in_reply_to_id: .in_reply_to_id,
    body: .body
  }]'
```

Build a set of `already_handled_ids` from `in_reply_to_id` values. Any comment whose ID is in this set is **skipped**, it was resolved in a previous iteration.

For SonarQube: issues that no longer appear in `fetch-issues.sh` output are already resolved (SonarQube tracks this automatically on re-scan).

### Round Number and Same-Class Detection

A fresh session remembers nothing about earlier runs on this PR, so both facts the round budget needs have to be read back off the PR itself: which round this is, and whether a finding is the third of a kind.

```bash
# ROUND NUMBER. Phase 6's round cap and the class rule below both read it.
#
# Count the DISTINCT fix commits our own dispositions name, then add one for the round about
# to happen. Only two dispositions name a commit, and the Phase 4 reply table gives each its
# own shape: `Fixed in {sha}` on an open PR, and `Fixed forward in #{pr} ({sha})` on a merged
# one, where the sha sits after the follow-up PR number rather than after the words. Matching
# the second as if it read `Fixed forward in {sha}` never matches it at all. Both are matched
# below; a round that fixed nothing and replied only "Not fixing" names no commit, consumed no
# fix round, and counting it would spend the budget on rounds that pushed nothing.
#
# Each alternative pins the sha's POSITION rather than hunting for the first hex-looking word.
# A follow-up PR number can itself be seven hex digits (#1234567), and a loose search finds it
# first, so the round would count a PR number as a commit.
#
# Read BOTH reply channels. Phase 4 posts inline dispositions to pulls/{n}/comments and
# top-level ones to issues/{n}/comments, so reading only the first undercounts a round whose
# findings all arrived as review bodies, which is the shape an automated reviewer posting one
# summary produces, and exactly the case the budget exists for.
#
# `--paginate` alone into a real `jq -s`, for the same reason as the disposition scan above:
# `gh api --slurp` is absent from older gh and 2.46 aborts on it with `unknown flag`.
# `test` before `capture`, because `capture` on a non-matching body raises and takes the whole
# count down to nothing, which reads as round 1 and silently restores the unbounded loop.
# `[(]` and `[)]` rather than escaped parens: jq reads `\(` inside a string as interpolation,
# so the escaped form is a different expression than it looks like.
# `ascii_downcase` before `unique` so `ABC1234` and `abc1234` count as one commit, not two.
# The `;` after each call and the line continuations are load-bearing: the two calls are
# separate commands feeding one `jq -s`, and a newline is the only separator a `{ }` group
# gets without them. Anything that folds this block onto one line then reads it as ONE `gh`
# call with the second call's words as arguments, which fails on an unhandled endpoint rather
# than counting rounds.
pr_number=${pr_number:-$(gh pr view --json number -q .number)}
repo_owner=${repo_owner:-$(gh repo view --json owner -q .owner.login)}
repo_name=${repo_name:-$(gh repo view --json name -q .name)}
me=${me:-$(gh api user -q .login)}
# Markers first: every reply this skill posts ends with `<!-- ar-fix round=N commit=SHA -->`
# (Phase 4), and a fix round is any marker naming a real commit, whoever posted it, a
# colleague's machine or a CI token counts the same. Only when no marker exists on the PR does
# the older prose form count, so PRs reviewed before this rule still get a number.
round_number=$( { gh api "repos/$repo_owner/$repo_name/pulls/$pr_number/comments" --paginate; \
                  gh api "repos/$repo_owner/$repo_name/issues/$pr_number/comments" --paginate; } \
  | jq -s --arg me "$me" 'add // []
      | ([.[] | (.body // "") | select(test("<!-- ar-fix round=[0-9]+ commit=[0-9a-fA-F]{7,40} -->"))
          | capture("<!-- ar-fix round=(?<r>[0-9]+) commit=") | .r | tonumber]) as $marked
      | if ($marked | length) > 0 then ($marked | max) + 1
        else ([.[]
          | select(.user.login == $me)
          | select((.body // "") | test("^Fixed (in [0-9a-f]{7,40}|forward in #[0-9]+ [(][0-9a-f]{7,40}[)])"; "i"))
          | .body | capture("^Fixed (in (?<a>[0-9a-f]{7,40})|forward in #[0-9]+ [(](?<b>[0-9a-f]{7,40})[)])"; "i")
          | (.a // .b) | ascii_downcase] | unique | length + 1) end')

# THE BUDGET. Default 3, per `<standards_location>/code-review.md` → "Round Budget for
# Agent-to-Agent Exchanges". A project raises or lowers it there without editing this skill.
# Validate the value: a non-numeric or absent setting must fall back to the default, not
# produce an empty string that every later `-ge` comparison then treats as a syntax error.
max_agent_rounds=$(jq -r '.review.max_agent_rounds // 3' .claude/config_hints.json 2>/dev/null)
case "$max_agent_rounds" in ''|*[!0-9]*) max_agent_rounds=3 ;; esac

echo "Round $round_number of $max_agent_rounds"
```

**Then group every finding on the PR by class, handled ones included, since the earlier rounds are the whole point.** Two findings are the same class when they share one of these shapes over the same underlying list, value or heuristic, in ANY files. A class is a shape, not a file: one count restated in four documents is one class, and requiring the same file made every file's instance a fresh finding.

| Shape | What it looks like across rounds |
|-------|----------------------------------|
| Same function or block | two findings on the same method |
| `X is missing from list Y` | another value the list does not cover |
| `the number in A disagrees with the number in B` | one count restated in two places |
| `case Z is not handled` | another input the pattern does not match |

Judge by shape, not by wording. An automated reviewer rephrases the same finding every round, so matching on text finds nothing.

**When a class already has two handled findings on this PR, do not fix the third as an instance.** Use the `Not fixing` disposition (Phase 4) in this form:

```
Not fixing as an instance. This is the third finding of the class "{class}" on this PR
({the two earlier comment ids}). The class does not close by adding instances; it needs
{an approach change | one source of truth for this value | a scope split}.
Proposed: {one line}. Tracked in {ticket or follow-up}.
```

Then record the class in the Phase 3 report under **Approach problems**, which is where Phase 6's round cap reads it.

The third finding is often correct, and that is not what this rule tests. It tests whether fixing one more instance changes the outcome. Where the answer is no, the reply above is the useful one and another fix is not.

**Several instances in one round are one class too.** When a single review delivers three or more findings of one shape, do not fix them one by one. Either make ONE structural fix (the list becomes a pattern, the restated number becomes a reference to its source, the special cases become a rule) and reply `Fixed in {sha} (structural: {what}; covers #{ids})` on the first with `Same class as #{first_id}` on the rest, or use the `Not fixing as an instance` reply on the first and `Same class as #{first_id}` on the rest. Nineteen findings of one shape answered with nineteen fixes is the failure this whole section exists to stop.

### Review Staleness (check before trusting any bot verdict)

A bot's review describes the commit it ran against, not necessarily the PR head. Compare the two before treating a bot verdict, or an absence of findings, as current.

**This resolves five states, not two.** A project with no review bot is a supported configuration (see Notes: *"any combination, SonarQube only, CodeRabbit only, human only, or all three"*). So is a bot that runs on the repo and deliberately declines this PR: a path filter excluding a file type posts no review object at all, so a PR touching only those files has no bot review and never will, on this push or any later one. Treating either permanently-empty result as "behind head" is what makes every run there end at `OUTSTANDING` and never report a clean finish. `none`, `skipped` and `behind` are different answers and only `behind` is a coverage gap. **"The bot has not reviewed yet" and "the bot deliberately skipped this PR" are not the same sentence and must never be reported as one.**

The reviewer login is **configurable**, this skill installs into projects that use CodeRabbit, a different bot, or none:

```bash
# `review.bot_login`: a login to expect, or "" / "none" to declare the project has no
# review bot. Unset (the default) means "probe and find out", handled below.
bot_login=$(jq -r '.review.bot_login // "coderabbitai[bot]"' .claude/config_hints.json 2>/dev/null)
[ "$bot_login" = "null" ] && bot_login=""
bot_configured=$(jq -e 'has("review") and (.review | has("bot_login"))' .claude/config_hints.json >/dev/null 2>&1 && echo explicit || echo probe)

# Every Bash call is a fresh shell, so re-derive the inputs here instead of trusting an earlier
# fence.
pr_number=${pr_number:-$(gh pr view --json number -q .number)}
repo_owner=${repo_owner:-$(gh repo view --json owner -q .owner.login)}
repo_name=${repo_name:-$(gh repo view --json name -q .name)}
me=${me:-$(gh api user -q .login)}
head_oid=$(gh pr view "$pr_number" --json headRefOid -q '.headRefOid')
bot_state=none   # none | current | behind | skipped | paused

if [ -n "$bot_login" ] && [ "$bot_login" != "none" ]; then
  # Pipe to a real jq: `gh api --jq` takes the expression only and does not accept --arg.
  bot_sha=$(gh api "repos/$repo_owner/$repo_name/pulls/$pr_number/reviews" --paginate \
    | jq -s -r --arg b "$bot_login" 'add // [] | [.[] | select(.user.login == $b)] | last | (.commit_id // "")')

  # A bot that skipped this PR by path filter posts no review, so it looks identical to a
  # bot that has not run yet. The distinguishing signal is an ISSUE-level comment from the
  # bot saying so. It is read EVERY time, not only when there is no review: CodeRabbit pauses
  # itself on a busy branch AFTER reviewing once ("Reviews paused"), and a probe consulted only
  # when bot_sha was empty left that PR `behind` forever with nothing coming.
  bot_skipped=$(gh api "repos/$repo_owner/$repo_name/issues/$pr_number/comments" --paginate \
    | jq -s -r --arg b "$bot_login" 'add // []
        | [.[] | select(.user.login == $b) | select((.body // "") | test("review (was )?skipped|reviews? (are |is |were |have been )?paused|review (is )?disabled|will not (be )?review|skipping (the )?review"; "i"))]
        | last | (.body // "")')
  bot_skipped_at=$(gh api "repos/$repo_owner/$repo_name/issues/$pr_number/comments" --paginate \
    | jq -s -r --arg b "$bot_login" 'add // []
        | [.[] | select(.user.login == $b) | select((.body // "") | test("review (was )?skipped|reviews? (are |is |were |have been )?paused|review (is )?disabled|will not (be )?review|skipping (the )?review"; "i"))]
        | last | (.created_at // "")')
  bot_review_at=$(gh api "repos/$repo_owner/$repo_name/pulls/$pr_number/reviews" --paginate \
    | jq -s -r --arg b "$bot_login" 'add // [] | [.[] | select(.user.login == $b)] | last | (.submitted_at // "")')

  # ISO-8601 Z timestamps compare correctly as strings.
  if [ -n "$bot_skipped" ] && { [ -z "$bot_sha" ] || [[ "$bot_skipped_at" > "$bot_review_at" ]]; }; then
    # The bot's newest word on this PR is that it will not review it (or the new head). Waiting
    # cannot change that, so `behind` is the wrong state. `paused` is kept separate because a
    # paused bot CAN be re-triggered, which Phase 6's ending 3 names.
    case "$bot_skipped" in *aused*) bot_state=paused ;; *) bot_state=skipped ;; esac
  elif [ -n "$bot_sha" ]; then
    [ "$bot_sha" = "$head_oid" ] && bot_state=current || bot_state=behind
  elif [ "$bot_configured" = explicit ]; then
    # The project named this bot, so its silence IS a gap: it has not reviewed this PR yet.
    bot_state=behind
  else
    # Default login on a project that never declared one. Before assuming a gap, check
    # whether the bot exists on this repo at all, look at the 5 most recent closed PRs.
    # Costs up to 5 extra API calls, once per run, and only when the bot is absent from
    # THIS PR. Set `review.bot_login` explicitly to skip the probe entirely.
    bot_state=none
    for n in $(gh api "repos/$repo_owner/$repo_name/pulls?state=closed&per_page=5" \
                 --jq '.[].number' 2>/dev/null); do
      if gh api "repos/$repo_owner/$repo_name/pulls/$n/reviews" --jq '.[].user.login' 2>/dev/null \
           | grep -Fxq "$bot_login"; then
        bot_state=behind; break
      fi
    done
    [ "$bot_state" = none ] \
      && echo "No review bot detected on this repo (probed for '$bot_login'). Set review.bot_login in config_hints.json (\"\" if there is none) to make this deterministic and skip the probe."
  fi
fi

case "$bot_state" in
  current) echo "Bot review of ${head_oid:0:9} is current." ;;
  behind)  echo "STALE: bot last reviewed ${bot_sha:0:9}, head is ${head_oid:0:9}" ;;
  skipped) echo "SKIPPED: $bot_login declined this PR on its own path filters, no re-review will arrive." ;;
  paused)  echo "PAUSED: $bot_login reviewed an earlier head and then paused itself; nothing arrives until someone re-triggers it." ;;
  none)    echo "No review bot configured for this project, review coverage is human + SonarQube only." ;;
esac
```

Each state gets its own waiting behaviour and its own words:

| `bot_state` | What it means | Waiting behaviour | How it is reported |
|-------------|---------------|-------------------|--------------------|
| `none` | The project has no review bot | Nothing to wait for | "no review bot configured for this project", coverage is human + SonarQube |
| `current` | The bot reviewed this exact head | Nothing to wait for | Clean finish allowed |
| `behind` | The bot has **not yet** reviewed the current head | Bounded wait, then `OUTSTANDING` | "{bot} has not reviewed {sha}. This run is not clean, it is unreviewed." |
| `skipped` | The bot **deliberately declined** this PR (path filters) | Nothing to wait for, no re-review is coming | Name the bot and what it excluded; never call this "not reviewed yet" |
| `paused` | The bot reviewed an earlier head, then paused itself | Nothing arrives until someone re-triggers it | Name the bot, the sha it reached, and the re-trigger |

When `bot_state` is `behind` the bot has not seen the current code, so its verdict cannot support a claim that the PR is clean, report the gap explicitly. A review several commits behind head produces no warning of its own and can sit unnoticed for days, which is why this is a check and not an observation. When `bot_state` is `none`, `skipped` or `paused` there is no gap to report, only a coverage fact to state: nothing is pending, and a clean finish is available. `skipped` still names the bot and the files it excluded, so the coverage claim stays honest about what did not get reviewed.

**A green bot check is not an absence of findings.** The review bot's entry in `gh pr checks` reports `pass` with a description like `Review completed` even when the review contains unresolved Major findings. `gh pr checks` is evidence that a CI job finished and is never evidence that review feedback is clear, only the `reviewThreads` query (Phase 4) answers that.

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

Skip this source entirely when `bot_state` is `none` or `skipped`, there are no bot findings to fetch. On `skipped` the bot's only comment is the skip notice itself, which is not a finding.

```bash
# Pipe to a real jq: `gh api --jq` takes the expression only and does not accept --arg,
# and $bot_login is configurable (see Review Staleness above).
gh api repos/$repo_owner/$repo_name/pulls/$pr_number/comments --paginate \
  | jq -s --arg b "$bot_login" 'add // [] | [.[] | select(.user.login == $b) | {
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

**If no new issues found:** Skip to Phase 5 (verify) for a final verification, then report clean. Phase 6 still applies: a clean gather is not a clean finish while the bot's review is `behind` the current head.

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

Round {round_number} of {max_agent_rounds}

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

### Approach problems ({n})
{For each finding class with two or more handled findings on this PR, from Phase 1 →
Round Number and Same-Class Detection:}
{warning_emoji} {class}, earlier findings {comment ids}, needs {an approach change | one
source of truth for this value | a scope split}
{If none:} none, no finding class has repeated on this PR

---

Ready to commit fixes? (y/n)
```

**The Approach problems section is printed even when empty.** Phase 6's round cap quotes it, and an omitted section reads as "nothing recurred" when what it means is "nobody looked".

**Wait for user approval before committing.**

## Phase 4, Commit + Reply

On user approval:

### Commit

**ALWAYS create a NEW commit**, never amend the previous one.

```bash
# Record where this round started, BEFORE the first fix commit. Phase 5a classifies the round
# against this sha; taken afterwards it would be a sha inside the round, and every fix landed
# before it would drop out of scope. PRINT it and state the sha in this phase's output as
# `{fix_base}`, Phase 5a runs in a different shell, so a variable assigned here never reaches
# it, and the printed value is what 5a substitutes.
git rev-parse HEAD    # -> {fix_base}; state this sha in the Phase 4 output, 5a substitutes it

git add {fixed_files}
git commit -m "[{namespace}-XXX] Fix PR feedback (iteration {n}): {n} SonarQube, {n} CodeRabbit, {n} reviewer issues"
# Explicit remote + refspec, not a bare `git push`. The Pre-Flight gate has already
# asserted current_branch == pr_head_branch and that its upstream is origin/$pr_head_branch,
# so this is belt-and-braces: it names the destination instead of inheriting whatever
# upstream the local branch happens to carry.
git push origin "HEAD:$pr_head_branch"
```

Stage only the files you actually fixed, never `git add -A` / `git add .`. The Pre-Flight clean-tree gate makes a blanket add *look* safe, but it would also pick up anything the fix run itself produced as a side effect (build output, generated reports).

Follow the Post-Review Fix Commits rule from the ar-taskflow skill: no force push, no amend.

### Reply on PR

**Every reply ends with a marker line**, after the disposition text:

```
<!-- ar-fix round={round_number} commit={sha} -->
```

`{sha}` is the fix commit for `Fixed` / `Fixed forward`, and `none` for every other disposition. Phase 1 counts fix rounds from these markers (a marker with a real commit is a fix round, `none` is not), the reviewer reads them too, and they are invisible in the rendered comment. Without them the round has to be parsed out of prose, which breaks on a backtick. The reviewer side of this exchange posts its own `<!-- ar-review round={n} -->` marker in the review body; the two markers are what let a fresh session compute the same round number.

Replies serve as **iteration markers**, they let the next run know which comments are already handled.

| Source | Reply Strategy |
|--------|---------------|
| SonarQube | No reply needed, SonarQube re-scans automatically on push |
| CodeRabbit (fixed) | Reply: "Fixed in {commit_sha}, {brief description of what changed}" |
| CodeRabbit (disagree) | Substantive reply explaining why (see CodeRabbit Reply Quality table) |
| Human (fixed) | Reply: "Fixed in {commit_sha}, {brief description}" |
| Human (skipped) | No reply, developer handles manually |
| Any source, on a **MERGED / CLOSED** PR | Reply: "Fixed forward in #{followup_pr} ({commit_sha}), {brief description}". **Do not use the plain "Fixed in {sha}" form**: on a merged PR it reads as fixed *in that PR*, which is false, the commit is on a different branch. Name the follow-up PR so the fix is findable. If the follow-up is not open yet, state where it is going ("Fixing forward in a follow-up PR into `{base_branch}`") rather than implying this PR carries the fix |

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

## Phase 5, Verify (MANDATORY)

**After all fixes are committed and pushed, verify nothing is broken.** Mandatory means *the change is verified*, not *this exact command is executed*. Two checks decide what running the suite actually proves here, and both come before you run anything.

### 5a. What scope has this round earned?

**Scope per fix, not per task.** Reviewer comments arrive as independent asks with independent blast radii. "Rename this local" and "this null check is wrong" are not the same change, and charging them the same verification is why a five-comment round used to cost five full suites. Scope each fix, take the **widest** scope any of them earned, and run that **once** for the round, not once per fix, and not the whole suite because one fix touched source.

**How a fix is classified is not decided here.** The **Change Scope** section of `ar-taskflow` owns
the classification, including the comment-only normalisation, the "inert for this project's verify
command" test, and the `verify.comment_only_skip` / `verify.always_full_paths` /
`verify.targeted_command` seams. Read it and apply it to each fix. Restating its table here would
give the same rule two owners, and the copy would be the one that goes stale.

What is specific to this skill is the arithmetic on top of it: classify every fix in the round, take
the widest scope any of them earned, and run that once.

**The base is `{fix_base}`, the sha the branch was at before this round's first fix commit.** Phase 4 captures and records it; substitute the recorded value literally here, the same way `{pr_number}` and `{comment_id}` are substituted. It is **not** a shell variable at this point: every Bash tool call starts a new shell, so `$fix_base` from Phase 4's block expands to empty and `git diff --name-only ""` aborts with `fatal: ambiguous argument ''`. That matters more here than for the other cross-block values in this skill, `pr_number` and `pr_head_branch` can be re-derived from the PR at any time, but a pre-commit sha cannot be recovered once the commit lands, and the obvious recovery from that git failure is `HEAD~1`, the one substitute the reason below rules out.

Not `HEAD~1`: it is the round base only while the round makes exactly one commit, which is what Phase 4 does today. A pinned sha stays correct if a re-fix after a failed verification adds a second commit, the case where `HEAD~1` would silently drop the first fix out of scope, and a migration fixed one commit earlier would be verified as though it had never been touched.

```bash
git diff --name-only {fix_base}          # every path this round touched
git diff --unified=0 {fix_base}          # the hunks, for the comment-only rule
```

A discharged round, where the verification command consumes nothing this round changed, is a **stated scope judgement, not a skipped phase**, and that distinction is what Phase 6 depends on. State it in writing ("verification not run: this round changed only {what}, which {the verify command} does not compile, execute, lint or validate"), then go to Phase 6. Never silently omit it, and never report a suite as green when you did not run one.

### 5b. Does something else already run the suite?

**A pre-push/pre-commit git hook that runs the suite is the gate, do not run it a second time yourself.** Two concurrent runs of the same project share one build-output directory and one dependency cache, so the second run rebuilds artifacts while the first is executing against them. The result is not a clean failure but a plausible one: mass "class/module not found" errors for code that is present in source, assertions failing because the application under test only half-initialised, and mangled result files from two writers, a phantom regression in code you never touched, which then blocks the push and sends you debugging nothing.

```bash
# Does a hook already own this? Check before running the suite yourself.
hook=$(git rev-parse --git-path hooks/pre-push); [ -x "$hook" ] && grep -lE 'test|check|verify' "$hook"
```

When a hook owns it, the push *is* the verification: let it run, and read its verdict. Never run the suite in the background while a push is in flight.

### 5c. Run it, and read the exit status honestly

```bash
# The command follows 5a's scope, not a fixed choice:
#   targeted scope -> `verify.targeted_command` over the touched paths, else `test_command`
#   full scope     -> `verify.full_command`, else `test_command`, else the documented command
# Only the full-scope branch prefers `verify.full_command`: it is the command written to
# include the opt-in and guarded suites a default test task silently skips, and reaching for
# it on a targeted round buys that completeness at full price for a diff that cannot use it.
```

**Never pipe the runner through `tail`, `head` or `grep` and then judge the result by the pipeline's exit code.** In a pipeline the shell reports the *last* command's status, so `<test_command> | tail -5` exits `0` over a failing build: a failing suite arrives as a pass, and truncation throws away the diagnostics needed to tell a real failure from an infrastructure one. Capture the full output to a file and read the runner's own status. With `pipefail` set, `$?` *is* that status, so do not reach for `PIPESTATUS` (undefined in zsh, which spells it `pipestatus` and indexes from 1, and `status` is a read-only special parameter there, so the assignment aborts the line):

```bash
set -o pipefail                      # or: run unpiped and tee
<test_command> 2>&1 | tee /tmp/verify.log; rc=$?
```

Judge a failure before reporting it as a regression: a diff holding nothing the command consumes cannot have caused one, which makes an infrastructure cause (a concurrent build, a stale daemon, an unavailable container runtime) the likelier explanation and worth ruling out first.

**INVOKE AGENT: a_sag_test_runner (background)**, pass it the command 5a's scope selected, and it flags any opt-in/tagged suite that command did not execute. A pass with a skipped-suite warning is **not** a clean green: on a **full**-scope round, run the named suite before declaring the fixes verified; on a **targeted** round the warning is expected and is not a defect, the suites named there are outside the scope this round earned.

1. Invoke `a_sag_test_runner` via the Task tool (subagent_type: `a_sag_test_runner`); its instructions load automatically (from agentic-devkit).
2. Run the command at 5a's scope
3. Review results:
   - **All pass** → proceed to the iteration check
   - **Failures** → STOP. Show the failing tests with file:line. Then:
     - **Unattended** (prompts are suppressed, or this skill was invoked by another routine
       rather than by a person at the keyboard): attempt ONE re-fix commit and re-run. If tests
       still fail, `git revert HEAD`, push the revert, and end this run with
       `VERIFY FAILED: {tests}, fix reverted in {sha}; the finding(s) it answered are back open
       for a human.` Never leave a red head on the PR and never ask a question nobody is there
       to answer.
     - **Interactive**: ask
       ```
       Integration tests failed after fixing PR feedback: {list}
       1. Fix the failing tests now (then re-run)
       2. Revert the last commit and investigate
       ```
       Option 1: fix, commit, re-run. Option 2: `git revert HEAD` and stop. There is no
       "skip tests" option: 5a's stated-scope judgement is the only way to discharge this
       phase, and it is made before the run, not after a red result.

**Do NOT skip this phase.** PR feedback fixes (especially CodeRabbit suggestions) can introduce regressions. Skipping is not the same as 5a's stated-scope judgement: 5a *discharges* the phase by establishing in writing that the suite cannot speak to this diff. Passing over verification in silence, or asserting a green you never observed, is what this rule forbids.

## Phase 6, Iteration Check (BINDING)

Pushing fixes is what makes CI re-run and produce new SonarQube and CodeRabbit comments on the commit just pushed. **The run is therefore not complete after the final push, and this phase is not optional.** Advising the user to re-run later does not discharge it: a sentence like "worth a second pass once CI reports" is an admission that a re-review is pending, not a substitute for handling one.

Re-run the **Review Staleness** check (Phase 1) against the new head and branch on its result. Exactly four endings are allowed:

0. **Round cap, checked before the staleness result is acted on.** Read `round_number` and `max_agent_rounds` from Phase 1. When `round_number` is at or above `max_agent_rounds` and the bot or reviewer is again `behind`, do NOT re-enter Phase 1. Stop with:
   ```
   ROUND CAP: round {round_number} of {max_agent_rounds} on PR #{pr_number}. {k} findings fixed
   across {round_number} rounds, review still posting on the new head.
   Recurring classes: {Phase 3 → Approach problems, or "none recorded"}.
   A human decides whether round {round_number + 1} happens.
   ```
   The order matters: every other ending routes on `bot_state`, so ending 1 matches the same `behind` result and loops before the cap is ever read.

   **This is a stop, not a failure, and not a completion claim.** Reaching the budget says something about the PR's shape, not about whether the fixes were right. See `<standards_location>/code-review.md` → "Round Budget for Agent-to-Agent Exchanges" for what the budget is and why neither green CI nor agreement between the two sides extends it. Run Phase 7 and end the run.

1. **`bot_state=behind`, round cap not reached, wait budget remaining → wait for the bot re-review, BOUNDED, then re-enter Phase 1** and iterate on whatever it raised. The Phase 1 iteration awareness skips comments already handled. The wait is one Bash call with a 600s tool timeout that polls once a minute for up to `review.bot_wait_minutes` (default 10):
   ```bash
   bot_wait=$(jq -r '.review.bot_wait_minutes // 10' .claude/config_hints.json 2>/dev/null)
   case "$bot_wait" in ''|*[!0-9]*) bot_wait=10 ;; esac
   [ "$bot_wait" -gt 10 ] && bot_wait=10   # one tool call; a longer wait belongs to the caller
   for i in $(seq 1 "$bot_wait"); do
     sleep 60
     sha=$(gh api "repos/$repo_owner/$repo_name/pulls/$pr_number/reviews" --paginate \
       | jq -s -r --arg b "$bot_login" 'add // [] | [.[] | select(.user.login == $b)] | last | (.commit_id // "")')
     [ "$sha" = "$head_oid" ] && { echo "bot reviewed $head_oid after ${i}m"; break; }
   done
   ```
   **When a caller that owns its own wakeup loop invoked this skill, skip the wait entirely and take ending 2**: that caller re-checks on its own schedule, and a second wait inside the fixer doubles the idle time and can exceed the tool timeout.
2. **`bot_state=behind` with the wait budget spent (or a scheduling caller owns the pacing) → report an explicit outstanding status** and hand the decision over, in these terms:
   ```
   OUTSTANDING: <bot_login> has not reviewed <sha>. This run is not clean, it is unreviewed.
   ```
3. **`bot_state=none`, `skipped`, `paused` or `current` → a clean finish is allowed.** With `none`, no bot review is pending because the project has none, so nothing is outstanding; state the coverage honestly rather than claiming a review that never happened:
   ```
   Complete. Review coverage: human + SonarQube (no review bot configured for this project).
   ```
   With `skipped`, the bot exists and declined this PR, so no re-review is coming and waiting cannot change that. Name the bot and the reason it gave:
   ```
   Complete. Review coverage: human + SonarQube (<bot_login> skipped this PR: path filters exclude the file types it touches).
   ```
   With `paused`, the bot reviewed an earlier head and then paused itself (CodeRabbit does this on a branch that keeps receiving commits). Nothing arrives until someone re-triggers it, so say so and name the trigger:
   ```
   Complete. Review coverage: human + SonarQube (<bot_login> paused reviews on this PR after <sha>; a re-trigger comment starts one if a bot pass on the current head is wanted).
   ```
   With `current`, the bot has reviewed this exact head and raised nothing further.

**Prohibition:** while a bot re-review of HEAD is *pending*, that is `bot_state=behind`, and only that, the summary must not contain a completion claim: not "all feedback addressed", not "N resolved, 0 unresolved", not "good to go". Endings 0 and 2 are the honest forms of that state. Neither `none` nor `skipped` nor `paused` is a pending review, and blocking a completion claim on them would make a supported configuration, no review bot or a bot whose path filters exclude this PR, unable to ever finish.

Present the choice:

```
All fixes committed and pushed.
Verification: {tests passing | not run, {5a scope reason} | owned by the pre-push hook}
Bot review of {head_sha}: {current | PENDING | none configured | skipped | paused}

Would you like to:
1. Wait for CI and run again → I'll re-gather feedback after CI completes
2. Stop here → I report the outstanding review status, not a clean state
```

Skip the prompt entirely when `bot_state` is `none`, `skipped`, `paused` or `current`, there is nothing to wait for, so asking offers a choice with one real answer. Skip it when the round cap has fired too: option 1 is the thing the cap exists to refuse, so offering it invites the run to spend a round the budget has already spent. The prohibition applies whether or not a user is watching; an unattended run has nobody to catch a false clean state, so it is *more* likely to be believed, not less.

Run Phase 7 (feed durable learnings back to rules) whenever this run finishes instead of looping, that is, at ending 0, at ending 2, and at ending 3.

**Typical iteration flow:**
```
Iteration 1: Fix SonarQube + CodeRabbit comments → commit → push → verified
                                                                      ↓
                                                            CI re-runs on new push
                                                                      ↓
                                        staleness check: bot reviewed < head → NOT clean
                                                                      ↓
Iteration 2: New SonarQube issues? New CodeRabbit comments? → fix → commit → push → verified
                                                                      ↓
Iteration 3: bot review current + nothing outstanding → done
                          OR round cap reached, review still posting → ROUND CAP (human decides)
```

## Phase 7, Feed Durable Learnings Back to Rules

At endings 0, 2 and 3 of Phase 6, close the loop before finishing. Run this **only** over findings you **genuinely fixed in code** this run, never over ones skipped, disagreed-with, deferred, or handled as a one-off domain change. The failure this prevents: the same class of finding keeps reaching review because the rule that would have stopped it is missing or under-documented.

For each genuinely-fixed finding:

1. **Extract the durable lesson:** the generalizable rule behind the fix (a quality-gate rule ID, a bot's recurring pattern, a reviewer convention), distinct from the ticket-specific code change.
2. **Check existing coverage.** Look in `<standards_location>/` for a rule that already teaches it. A rule that names the ID in a heading but never explains the pattern or shows the fix is still a **gap**.
3. **Close a real gap only**, routing per `<standards_location>/learning-routing.md`:
   - **Project convention** → propose a concise rule update under `<standards_location>/`; on approval, commit it on the PR branch.
   - **Framework defect** → invoke `ar-record-improvement` instead (never hand-edit the framework).
   - **One-off / niche** → conversational note only; write no rule.

**Guardrails (the failure mode is over-application, so be conservative):**
- Act only on findings you fixed. Skipped / disagreed / deferred findings teach nothing here.
- **Avoid rule bloat.** Add a rule only when the issue is recurring or the rule is clearly load-bearing; do not record every minor one-off.
- **Never blindly apply.** Verify the rule is genuinely missing or weak first; if a rule already documents the finding, change nothing.
- A rule edit is a **judgement**, not mechanics: it changes a standard every future review reads. Present it for approval before committing it. The conservatism above is what holds the bar, not the prompt.

## Relationship to ar-taskflow

This skill is **standalone**, not embedded in ar-taskflow phases:

```
ar-taskflow (Phase 0-4) → commit → push → create PR
                                               |
                                     CI runs (SonarQube, CodeRabbit, reviews)
                                               |
                                     ar-taskflow-fix-comments  (iteration 1)
                                               |
                                     commit fixes → push → verified
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
- `jq`, for the PR snapshot parsing, the round-marker count, and the review-staleness states
- The project's configured verify command, for Phase 5 verification (discharged, with the reason stated, when it compiles, executes, lints, or validates none of the changed files; owned by a pre-push hook where one runs it)

## Notes

- Each source is independent, skill works with any combination (SonarQube only, CodeRabbit only, human only, or all three)
- Batch similar issues (e.g., multiple "add null check" comments) into logical groups
- Stale CodeRabbit comments (from old commits) are filtered by checking against current file content
- All replies are shown to user for approval before posting, never auto-post
- **Push safety:** Pre-Flight resolves the PR state, the head commit, the branch name, the upstream and every push URL on `origin` before a single file is edited, so fixes cannot land on the wrong branch, the wrong repository, or a merged PR's dead head
- **Post-merge safety:** feedback arriving after a merge is fixed forward on a new branch off the base the PR merged into, with a follow-up PR and a reply on the original threads pointing at it, never pushed to the merged head branch
- **Iteration safety:** Replies on PR serve as the resolution trail, they prevent re-processing the same comments across iterations, and each carries `<!-- ar-fix round={n} commit={sha} -->` so a fresh session recomputes the same round number
- **Test safety:** the verify command runs after every iteration whose diff it consumes (compiles, executes, lints, or validates) to catch regressions from feedback fixes. An iteration it consumes nothing from states that scope judgement instead of running it, and a suite a git hook already runs is not run a second time, two concurrent builds share one output directory and manufacture phantom failures
- **Review safety:** the push that ends a run is what triggers the re-review of it, so Phase 6 is binding and a pending bot review is reported as `OUTSTANDING` rather than as a clean finish. A green `gh pr checks` entry and a zero unresolved count are both compatible with unreviewed code. "Pending" means `bot_state=behind`; a project with no review bot (`none`), a PR the bot declined on its own path filters (`skipped`), and a bot that paused itself (`paused`) have nothing pending and finish cleanly, reporting coverage honestly and naming the bot where there was one
- **The round budget is configurable:** `review.max_agent_rounds` in `config_hints.json` sets how many fix rounds this skill will spend on one PR before Phase 6 stops with `ROUND CAP` (default 3). Raise it for a project whose reviewer genuinely converges; the rule behind the default is `<standards_location>/code-review.md` → "Round Budget for Agent-to-Agent Exchanges". It caps automated exchanges only and never counts a human reviewer's findings
- **Review bot is configurable:** `review.bot_login` in `config_hints.json` names the bot to expect (default `coderabbitai[bot]`), or `""` / `"none"` to declare the project has none. Leaving it unset costs up to 5 extra API calls per run on a repo where the default bot is absent, spent probing recent PRs, set it explicitly to skip that. `review.bot_wait_minutes` (default 10) bounds Phase 6's wait for a pending re-review
