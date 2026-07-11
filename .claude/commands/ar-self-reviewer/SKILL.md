---
name: ar-self-reviewer
description: Reviews a PULL REQUEST of the Agentic Repos framework SOURCE repo itself for project-based noise. Its input is a framework PR, on trigger it FIRST asks which agentic-repos PR to review (framework PRs only; it refuses PRs from any other repo). Proves the PR introduces ZERO project-based noise into the project-agnostic framework, installed artifacts (rules/, skills/, agents/, templates/, setup.md) AND docs/. Catches a source project's identity (real names, packages, developer paths, tickets, people, dated incident notes), whole files bound to one project (a <project>-feedback.md mining doc, anything named after or dominated by a single product line, these belong in the source project, not the framework), stack idioms leaking into stack-agnostic skill/agent bodies, ungenericized business-domain examples, rationale/version-history bloat, mis-tiered rules, and version-file drift. Use whenever you want to review/self-review an agentic-repos PR for "does this leak or bind a project into the generic framework," before merging a framework PR, or to vet a framework change before the version bump.
---

# Framework Self-Review (project-noise gate)

This framework ships to **every consuming team**. A change that smuggles one project's identity, its name, package, a developer's path, a ticket id, a teammate's email, a dated incident note, or a business-domain example, into an installed artifact pollutes every install. This gate runs over a framework-source change and proves it didn't.

It is the missing third guard. The framework already has two:

- `scripts/ar-lint/generic-skill-lint.sh`, hard-fails on **stack idioms** in skill/agent bodies (`@Transactional`, `gradlew`, …). Unambiguous, mechanical.
- `ar-optimizer` check 3n, flags **rationale bloat** (Why-sections, version-history markers) during a full audit.

Neither scans `rules/` for **business/project noise**, and `ar-add-improvement`'s noise filtering (Step 0e) runs **only on the import path**, a leak added directly or via the "describe" flow sails straight through. This gate closes that hole by combining the mechanical lints with a judgment pass for the noise regex can't see.

## Input

**This gate takes a framework PR as its input.** Its first action is always to ask which `mahsanamin/agentic-repos` PR to review (unless the user already named one). It reviews **agentic-repos PRs only**, for target-project PRs use `a_sk_l_review_pr` or `ar-global-pr-reviewer`.

**Scope, it complements, does not duplicate.** This gate covers exactly one axis: *does this PR leak or bind a project into the project-agnostic framework.* It does **not** re-review correctness, security, tests, or style, CodeRabbit / SonarQube / human review own those (and on a framework PR, project-noise is precisely the axis they *don't* check). Don't restate their findings; report only the noise axis.

## When to run

- To review (or self-review) an agentic-repos PR for project noise, before merge.
- As the review step after `ar-add-improvement` opens a framework PR.
- A **pre-PR / pre-commit fallback** exists: if no PR is open yet (e.g. invoked mid-`ar-add-improvement` before the PR exists), it can scan the local branch diff instead, see Step 1.

It is a **framework-development** gate. It is meaningless inside a target install (a target project is *supposed* to be full of its own names), which is why it lives in `.claude/commands/` and is never installed.

## Finding-type enum

Every finding is exactly one of these. The judgment pass and the report use these names verbatim.

| Type | What it means | Typical source |
|---|---|---|
| `STACK_IDIOM_IN_SKILL` | A language/stack idiom in a skill/agent body that must stay stack-agnostic. | `generic-skill-lint.sh` |
| `PROJECT_NOISE` | A real project's identity in an installed artifact: name, package (`com.example.<realname>` vs `{project}`), absolute dev path, literal ticket id, person/team email, commit SHA, or a dated incident note. | `project-noise-lint.sh` + judgment |
| `PROJECT_SCOPED_ARTIFACT` | A whole file whose **name or dominant content binds the generic framework to ONE specific project**, a `<project>-feedback.md` mining doc, a doc declaring a `Source project:`, a file named after a product line. The framework is project-agnostic: it keeps the distilled **generic** output (rules); the project-specific analysis belongs in the source project or scratch space, not committed here. Most often hides in `docs/`. | `project-noise-lint.sh` (filename / source-project line / slug density) + judgment |
| `UNGENERICIZED_EXAMPLE` | An example whose **names reveal a source project's business domain** even though no literal project string appears (e.g. a DTO named for one team's feature). Regex can't see this, judgment only. | judgment pass |
| `RATIONALE_BLOAT` | Why-sections, design-history narration, or `(NEW in vX.Y.Z)` / "previously was" markers inside an artifact body. The CHANGELOG records the why; the artifact states the what. | `project-noise-lint.sh` + `ar-optimizer` 3n |
| `MISTIERED_RULE` | Stack-specific content placed in `rules/universal/` (or `rules/_generic/`), which leaks it to every stack. | judgment pass |
| `VERSION_INCONSISTENCY` | `framework_version` in `config_hints.json`, the `Version:` line in `CLAUDE.md`, and the top `## v…` entry in `CHANGELOG.md` disagree. | version check |

## Severity enum

- `BLOCKING`, fails the gate. Must be fixed before commit. (Any `STACK_IDIOM_IN_SKILL`; any confirmed `PROJECT_NOISE` / `UNGENERICIZED_EXAMPLE` / `MISTIERED_RULE`; any `VERSION_INCONSISTENCY`.)
- `WARN`, almost certainly should change, but a human may have a reason (e.g. an illustrative date that genuinely aids understanding). Surface loudly; don't hard-fail.
- `INFO`, a candidate the judgment pass adjudicated as legitimate (an established shared-library reference, a labelled placeholder). Recorded so the human sees it was considered, not silently dropped.

## Procedure

Steps run in order. The first action, always, is to resolve which framework PR you're reviewing.

### 1. Resolve the PR (ask FIRST)

The input to this gate is a framework PR. If the user did not already name one, **ask before doing anything else**:

```
Which agentic-repos PR should I self-review? (PR number or URL)
```

Accept a number (`6`) or a GitHub URL. Then **validate the repo** (capture stderr so a real `gh` auth/scope error surfaces instead of a misleading "check the URL"):

```bash
command -v gh >/dev/null && gh auth status >/dev/null 2>&1 || { echo "gh not installed / not authenticated"; exit 2; }
# From a URL, extract owner/repo + number; from a bare number, assume mahsanamin/agentic-repos.
gh pr view "$PR" --repo mahsanamin/agentic-repos \
  --json number,title,headRefName,headRefOid,url,additions,changedFiles 2>/tmp/gh.err || { cat /tmp/gh.err; exit 2; }
```

If the PR belongs to **any repo other than `mahsanamin/agentic-repos`, STOP and refuse**: "ar-self-reviewer reviews agentic-repos PRs only, for a target-project PR use `a_sk_l_review_pr` or `ar-global-pr-reviewer`." This gate's entire premise (the framework must stay project-agnostic) is meaningless for a project repo, which is *supposed* to be full of its own names.

**Pre-PR fallback:** if invoked before a PR exists (e.g. mid-`ar-add-improvement`), the user can say "local" / "this branch", then skip the fetch and scope from the working tree (`git diff --name-only main...HEAD`), and at step 6 print the findings instead of posting them. Everything else is identical.

### 2. Fetch the PR and resolve scope

Read the PR's files at its head **without disturbing the user's working tree**, use a review worktree. Prefer the framework's helper (same one `ar-global-pr-reviewer` uses), fall back to raw git:

```bash
# Preferred: bash "${AGENTIC_DEVKIT_DIR:-$HOME/agentic-devkit}"/scripts/a_g_worktree_review <PR>   (creates WorkTrees/<repo>/review-pr-<PR>/)
# Fallback (helper absent):
git fetch origin "pull/$PR/head" 2>/dev/null
wt=$(mktemp -d); git worktree add --detach "$wt" FETCH_HEAD >/dev/null
# (cd "$wt" for the lint steps; `git worktree remove "$wt"` when done)
```

Scope is what the PR **changed**, restricted to installed artifacts (the `PROJECT_NOISE` / stack-idiom surface) **and `docs/`** (the `PROJECT_SCOPED_ARTIFACT` surface, where a project-bound file hides, since it isn't "installed"):

```bash
gh pr diff "$PR" --repo mahsanamin/agentic-repos --name-only \
  | grep -E '^(rules|skills|agents|templates|docs)/|^setup\.md$'
gh pr diff "$PR" --repo mahsanamin/agentic-repos --name-only --diff-filter=A   # added files, name alone can flag PROJECT_SCOPED_ARTIFACT
```

If nothing matches, report `no scanned artifacts changed` and pass. `CHANGELOG.md` is intentionally out of scope, it is the designated history and may name the project that motivated a change.

Also fetch the PR's **existing comments** (for dedup + cross-reference in step 4) and its **added-line ranges** (so a posted comment lands on a line the PR actually touched, GitHub rejects an inline comment on an unchanged line with a 422):

```bash
gh api "repos/mahsanamin/agentic-repos/pulls/$PR/comments"  --jq '[.[]|{path,line,user:.user.login,body}]' > /tmp/pr-comments-$PR.json
gh api "repos/mahsanamin/agentic-repos/issues/$PR/comments" --jq '[.[]|{user:.user.login,body}]'       > /tmp/pr-issue-$PR.json
gh pr diff "$PR" --repo mahsanamin/agentic-repos --patch > /tmp/pr-$PR.patch   # added lines = the only valid inline-comment anchors
```

### 3. Mechanical lints (the wide net), run in the worktree

```bash
( cd "$wt" && bash scripts/ar-lint/generic-skill-lint.sh )           # STACK_IDIOM_IN_SKILL, hard fail on its own
( cd "$wt" && bash scripts/ar-lint/project-noise-lint.sh --changed )  # PROJECT_NOISE / PROJECT_SCOPED_ARTIFACT / RATIONALE_BLOAT candidates
```

`generic-skill-lint.sh` exit 1 is **immediately BLOCKING**, a stack idiom in a skill/agent body is never acceptable. Record each hit as `STACK_IDIOM_IN_SKILL`.

`project-noise-lint.sh` exit 1 means it surfaced **candidates**, not confirmed findings, noise-vs-legitimate is contextual. Carry every candidate into the judgment pass for adjudication. Do not block on the raw exit code alone.

### 4. Judgment pass (the safety net)

The lints miss two things by design: noise that has no fixed shape (`UNGENERICIZED_EXAMPLE`), and mis-tiering (`MISTIERED_RULE`). They also over-fire (an established shared-library reference looks like `PROJECT_NOISE`). Spawn the `a_sag_code_reviewer` agent to adjudicate the candidates and to read the changed artifacts cold for domain-shaped leakage.

Give the agent:

- the list of changed files from step 1 (it reads them in full),
- the raw `project-noise-lint.sh` candidate list from step 2,
- this instruction:

> Review these Agentic Repos **source** changes for project-based noise that would ship to (or pollute) the project-agnostic framework. For each changed file under `rules/`, `skills/`, `agents/`, `templates/`, `setup.md`, **and `docs/`**:
> 1. **Adjudicate each lint candidate**, confirm it as real noise, or mark it `INFO` with a one-line reason it's legitimate (a labelled placeholder, an established shared-library/base-class reference the framework already uses elsewhere on `main`, a deliberately illustrative value).
> 2. **Find what regex can't** (`UNGENERICIZED_EXAMPLE`): example class/field/variable/entity names that reveal a *specific source project's business domain* rather than a neutral illustration. Neutral examples (`User`, `Order`, `Item`, `Feature`, `unitPrice`) are fine; names that read like one team's feature set are not. State the neutral replacement you'd use.
> 3. **Judge whole-file project-binding** (`PROJECT_SCOPED_ARTIFACT`): is this file's *reason to exist* tied to ONE specific project? A doc named after a project, declaring a `Source project:`, or whose body is dominated by one project's business specifics / test names / repo paths is project-bound, it does **not** belong in the framework even though it isn't "installed" anywhere. The framework keeps the distilled **generic** output (the rules a change produced); the project-specific feedback/analysis stays in the source project or a scratch space. Recommend removing it from the framework (or relocating it), and confirm the generic rules it produced are what remains. A *generic* design/decision doc (no single-project binding) is fine, `INFO`.
> 4. **Check tiering** (`MISTIERED_RULE`): any file under `rules/universal/` or `rules/_generic/` that contains language/framework idioms belongs in a per-stack tier instead.
> 5. **Classify each finding as `PR-INTRODUCED`, `PR-EXPOSED`, or `PRE-EXISTING`** (this is mandatory, it is the difference between a clean review and noise). The lints scan whole changed files, so they surface noise on lines the PR did **not** touch. Cross-check every candidate against the PR's added lines (`/tmp/pr-$PR.patch`): only `PR-INTRODUCED` (the diff added/changed the offending line) and `PR-EXPOSED` (the diff made a pre-existing problem reachable) become posted comments. A `PRE-EXISTING` hit, the same noise already sits in unchanged code (e.g. a `com.example.<lib>` import the PR didn't add), goes to an internal **Notes** line, never an inline comment, and is **never** phrased as if the PR caused it ("this PR is a good moment to also clean up N pre-existing spots" is the only acceptable framing).
> 6. **Dedup + cross-reference existing comments** (`/tmp/pr-comments-$PR.json`, `/tmp/pr-issue-$PR.json`): skip any finding a prior comment already covers (note `dup of …` internally). If an automated reviewer (CodeRabbit, SonarQube) already posted on the noise axis, reconcile, agree/extend, don't repeat. If a bot said "no actionable comments," that does **not** clear the noise axis (bots don't check it), proceed.
> 7. **Author-intent softener:** if the PR body / commit message shows the author already considered a finding (e.g. "temporary doc, will delete before merge"), reframe that one as a **question**, not a hard finding, except for an unambiguous BLOCKING leak, which stands regardless.
> Classify every finding with the finding-type and severity enums above. A clean change with zero findings is the expected, good outcome, do not manufacture findings. Cite `file:line` (or the filename, for a whole-file `PROJECT_SCOPED_ARTIFACT`) for each, and tag its PR-INTRODUCED / PR-EXPOSED / PRE-EXISTING class.

Established shared references already present on `main` (a shared library package, a common base class) are `INFO`, not `BLOCKING`, verify by grepping `main` before flagging a name as new noise.

### 5. Rationale-bloat sweep

Fold `project-noise-lint.sh`'s `RATIONALE_BLOAT` candidates together with anything the judgment pass flagged, applying `ar-optimizer` check 3n: delete Why-sections, design-history narration, and `(NEW in vX.Y.Z)` / "previously was" / "pre-vX.Y.Z" markers from artifact bodies. An installed artifact is always exactly one version, version-history prose inside it is meaningless. Exempt one-line purpose openers and cost-flags that inform an opt-in decision.

### 6. Version consistency

Only when the change includes a version bump (or you're about to make one):

```bash
cfg=$(grep '"framework_version"' config_hints.json | sed 's/.*: *"\(.*\)".*/\1/' | tr -d '[:space:]')
cla=$(grep "^Version: v" CLAUDE.md | sed 's/Version: v//')
chg=$(grep "^## v" CHANGELOG.md | head -1 | sed 's/.*v\([0-9.]*\).*/\1/')
echo "config_hints=$cfg  CLAUDE.md=$cla  CHANGELOG=$chg"   # all three must match
```

All three must agree. A mismatch is `VERSION_INCONSISTENCY` / `BLOCKING`.

### 7. Draft and post comments, `a_sk_l_review_pr` style

Findings are delivered as **PR review comments in exactly the `a_sk_l_review_pr` format**, not a freeform prose summary. The bar is the same: every comment is a real problem the author needs to act on; a clean PR with zero comments is a good outcome; never manufacture findings to look thorough.

**Two interaction points only:** Step 1 (which PR) and here (which comments to post). Everything between runs without asking.

**Comment body format, every comment, in the draft AND when posted, starts with location:**

```
📍 `rules/java-spring-boot/api-conventions.md:7`

**Problem:** Example DTO `ReserveRequest` (`tierId`, `usdToUserCurrencyFactor`, `RatePlanType`) names one project's business domain, not a neutral illustration.
**Fix:** Rename to a neutral example, `CreateOrderRequest` / `itemId` / `unitPrice` / `OrderType`.
```

Language rules (identical to `a_sk_l_review_pr`): first line is `📍 \`path:line\``; Problem in one concrete sentence (no "there might be…"); Fix in one concrete sentence; no filler openers ("I noticed", "it appears"); backtick every code/file/identifier reference; **one comment = one fix**. For a whole-file `PROJECT_SCOPED_ARTIFACT`, anchor at the file's first added line (`:1`) and make the Fix "remove from the framework / relocate to the source project; keep only the generic rules it produced."

**Build the draft**, then show a lean table, only real findings, no padding:

```
Self-review of PR #{n}, {title}
Verdict: {APPROVED / NEEDS WORK / BLOCKED}   ({B} blocking, {W} warn)

| # | Type | Severity | Class | File:line | Problem | Action |
|---|------|----------|-------|-----------|---------|--------|
| 1 | UNGENERICIZED_EXAMPLE | BLOCKING | PR-INTRODUCED | api-conventions.md:7 | DTO names one project's domain | Post |
| 2 | PROJECT_SCOPED_ARTIFACT | BLOCKING | PR-INTRODUCED | acme-spring-boot-feedback.md:1 | whole doc bound to one project | Post |
| 3 | PROJECT_NOISE | INFO | PRE-EXISTING | commands.md:51 | `com.example.<lib>`, pre-existing, not added here | Internal (Notes) |

{P} to post, {I} internal. Post all? Or tell me which to adjust.
```

Map to action: a `PR-INTRODUCED` or `PR-EXPOSED` finding at `BLOCKING`/`WARN` is **Post**; everything else is **Internal**, `INFO` (adjudicated-legitimate), `PRE-EXISTING` (real noise but the PR didn't add it → a Notes line, framed as "also worth cleaning up," never as this PR's fault), and dups of existing comments. If there are zero postable findings, show only the verdict (`APPROVED`), do not pad with "all good" rows.

**Post only after the user picks** (`yes` / `post 1,2` / `skip 3` / `none`). Post as a **single batch review** so GitHub sends one notification, mirroring `a_sk_l_review_pr` Step 12:

```bash
head_sha=$(gh pr view "$PR" --repo mahsanamin/agentic-repos --json headRefOid -q .headRefOid)
gh api repos/mahsanamin/agentic-repos/pulls/"$PR"/reviews --method POST --input /tmp/ar-self-review-"$PR".json
```

The review JSON uses `event: COMMENT`, the head `commit_id`, and one `comments[]` entry per posted finding (`path`, `line`, `side:"RIGHT"`, `body` = the location-first block above). The review summary `body` is a single plain line, `"Framework self-review, {B} blocking, {W} warn"`, **no marketing preamble, no "I ran our lens over this PR" narration.** Findings carry the message; the body just labels the batch. Fall back to per-comment `POST .../pulls/{n}/comments` if the batch call fails. Clean up the temp file.

Each comment's `line` MUST be one the PR actually added (in `/tmp/pr-$PR.patch`), GitHub returns 422 for an inline comment on an unchanged line. A new file (e.g. a `PROJECT_SCOPED_ARTIFACT` doc) has `:1` in its added range, so anchoring there is safe.

Then remove the review worktree (non-interactive `--force`, mirroring `ar-global-pr-reviewer`'s cleanup): `bash "${AGENTIC_DEVKIT_DIR:-$HOME/agentic-devkit}"/scripts/a_g_worktree_remove --force "review-pr-$PR"` (or `git worktree remove --force "$wt"` for the raw fallback).

## What this gate does NOT do

- It does not post without showing the draft and getting your pick first, same contract as `a_sk_l_review_pr`.
- It does not modify tracked files; it reviews and comments. (If you ask, it can apply the BLOCKING fixes to a branch separately.)
- It does not replace `ar-optimizer` (full-project token/redundancy audit) or `a_sk_l_review_pr` (target-project code review). It is narrowly the *no-project-noise* review for framework PRs.
- It does not run in target projects, project-specific content is expected there.
