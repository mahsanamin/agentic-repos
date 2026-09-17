---
name: ar-sonar-sweep
description: Drive a project's whole SonarQube backlog toward zero open issues, in bounded reviewable batches. Fetches every open issue on a branch (not just the current PR's new code), groups them by file, fixes each batch in severity order following the project's installed rules, verifies with build/tests/lint, and commits per batch onto its own branch/PR so review stays tractable. Explicitly invoked for backlog cleanup; the per-PR flow (ar-taskflow-fix-comments, scope=changed) already handles issues in files a feature PR touches. Say "ar-sonar-sweep" or "sonar sweep".
disable-model-invocation: true
---

# SonarQube Backlog Sweep

Cleans a project's **whole-project SonarQube backlog** down toward 0 open issues. This is the "clean slate" job: it looks at issues across the entire branch, not only the new code on one PR. Because a backlog can be large, it works in **bounded, reviewable batches** (one file, or a small group, per commit, prioritized by severity), so a human reviewer is never handed a thousand-line diff.

**When NOT to use this:** for issues on a PR you are actively working, the per-PR flow already covers them. `ar-taskflow-fix-comments` fetches `SONAR_SCOPE=changed`, which fixes every issue in the files that PR touched. Use this sweep only for the standing backlog in files no current PR touches.

**MANDATORY:** every code change here must follow the project's installed rules at `{standards_location}` (from `config_hints.json`): the stack's coding-conventions rule, its SonarQube/lint-compliance rule (assertion idioms, dead code, matcher rules), its unit-testing rule (when a fix needs a test), and its module-boundary rule. A "fix" that violates an installed rule is a bug.

## Prerequisites

- `~/.claude/scripts/ar-sonarqube/fetch-issues.sh` installed (via `ar-install-tools` / `ar-upgrade`), and `SONARQUBE_URL` + `SONARQUBE_TOKEN` exported in this shell. If either is missing, stop and guide setup; do not silently report a clean backlog.
- A clean working tree. The sweep produces its own branches/worktrees; it never commits to `main`/`master`.

## Scope

Ask for the scope if it is not clear:

1. **Whole project** (default): every open issue on the branch.
2. **A module or path prefix**: restrict the sweep to one area (large repos are best swept area by area).
3. **A branch** other than the default: set `SONAR_BRANCH`.

## Pipeline

### Phase 1: Fetch the backlog

```bash
SONAR_SCOPE=all ~/.claude/scripts/ar-sonarqube/fetch-issues.sh 2>&1
# Optional: SONAR_BRANCH=<branch> to sweep a non-default branch.
```

This returns every open (`OPEN`/`CONFIRMED`/`REOPENED`) issue on the branch, paginated. Report the total and the breakdown by severity and by type (bug / vulnerability / code smell / security hotspot).

### Phase 2: Triage and order

- **Never auto-fix security findings** (vulnerabilities, security hotspots) or concurrency issues. List them for manual review with their locations; they are out of scope for an automated sweep.
- **Group the remaining issues by file.** A per-file batch keeps each commit coherent and its tests runnable.
- **Order files by highest severity first** (BLOCKER, then CRITICAL, MAJOR, MINOR, INFO), then by issue count. If a path/module scope was given, keep only files in it.
- Announce a **per-run batch cap** (default: work until the branch backlog in scope is clear, but open at most a handful of PRs per run so review does not pile up; state the number). Anything left over is reported as remaining and picked up on the next run.

### Phase 3: Fix one batch

For each file batch, on its own branch (use `a_g_worktree_*` for isolation):

1. Read the file in full to understand control flow. The goal is a correct fix, not a silenced rule.
2. For each issue, apply the fix that follows the installed rules. Common code-smell categories and the safe action:

   | Category | Action |
   |----------|--------|
   | Unused imports / variables / fields / parameters | Remove |
   | Empty blocks (catch, if, …) | Remove or add a documented no-op |
   | Missing / weak test assertions | Add a meaningful assertion (follow the unit-testing rule) |
   | Naming / formatting / style | Fix to convention |
   | Redundant / dead code | Remove |
   | Cognitive complexity | Refactor **only** if behavior-preserving and covered by tests; otherwise flag for manual review |
   | Behavior-changing rules | Flag for manual review; do not guess |

3. Do not change observable behavior. If a "fix" would, flag it instead of applying it.

### Phase 4: Verify each batch

Run the project's build, the affected tests, and the lint/format check (commands from `config_hints.json` / installed rules). A batch does not ship until all three are green. If a fix breaks something, revert that fix and flag the issue for manual review rather than leaving the batch red.

### Phase 5: Commit and PR per batch

- Commit the batch with the commit skill (which requires user approval). Never force-push.
- Open (or append to) a PR for the sweep. Keep batches small enough to review. Let the standing PR feedback loop (SonarQube re-scan, CodeRabbit) run; the re-scan confirms the fixed issues drop off.
- **Merging stays a human decision.** The sweep never merges.

### Phase 6: Report

Per run, output: starting backlog count (by severity), issues fixed, issues flagged for manual review (with reasons and locations), batches committed / PRs opened, and the **remaining** backlog count so progress toward 0 is visible across runs. If nothing remains in scope, say so plainly.

## Rules

- **Security and behavior-changing findings are never auto-fixed.** They are flagged, with locations, for a human.
- **Bounded and resumable.** A large backlog is cleared over multiple runs; each run reports what is left.
- **This skill does not merge.** It commits and opens PRs; a human merges.
- **Installed rules win.** A fix that trips a project rule is not a fix.
