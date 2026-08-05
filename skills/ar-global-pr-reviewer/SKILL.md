---
name: ar-global-pr-reviewer
description: Review any GitHub PR from anywhere on the machine, no project checkout needed. Clones the repo, sets up a review worktree, does a best-effort test run, reviews changed code for logical bugs and missing-test gaps against the project's rules, dedups against existing comments, and posts an inline review with fixes. Say "ar-global-pr-reviewer", "review pr globally", or "global review <PR-URL>".
disable-model-invocation: true
---

# Global PR Reviewer

Review any GitHub pull request from anywhere on the machine. You don't need to be in the target project's checkout, the skill clones (or reuses) it under `~/ar-global-pr-reviewer/repos/` and creates a review worktree.

## 🧭 Learning routing

Follow the rule at `<standards_location>/learning-routing.md` (resolve `standards_location` from `.claude/config_hints.json`): route any learning to a project rule (`docs/ai-rules/`), a framework improvement (`ar-record-improvement`), or conversational-only, never personal auto-memory.

---

## Phase 0: Accept the PR URL

The user invokes the skill in one of these ways:

```
> ar-global-pr-reviewer
> ar-global-pr-reviewer 356
> ar-global-pr-reviewer https://github.com/your-org/example-service/pull/356
> global review https://github.com/your-org/example-service/pull/356
```

If no argument is provided, ask:

```
Which PR should I review?

Provide a full URL or just the number + repo:
  https://github.com/your-org/example-service/pull/356
  your-org/example-service#356

Your input:
```

Parse the input. A bare number alone is ambiguous (no repo), ask for the URL or `owner/repo#N` form.

Store as: `PR_URL`, `OWNER`, `REPO`, `PR_NUMBER`.

```bash
# Validate gh is installed and authenticated
if ! command -v gh >/dev/null 2>&1; then
    echo "❌ gh CLI not installed. brew install gh, then gh auth login."
    return 1
fi
gh auth status >/dev/null 2>&1 || { echo "❌ gh not authenticated. Run: gh auth login"; return 1; }

# Fetch PR metadata. Capture stderr so a wrong field name or missing scope
# surfaces the actual `gh` error message, not a misleading "Check URL/auth".
PR_META_ERR=$(mktemp)
PR_META=$(gh pr view "$PR_URL" --json number,title,state,author,headRefName,baseRefName,headRefOid,headRepository,url,additions,deletions,changedFiles,body 2>"$PR_META_ERR")
if [ -z "$PR_META" ]; then
    echo "❌ Could not fetch PR."
    if [ -s "$PR_META_ERR" ]; then
        echo "    gh said: $(cat "$PR_META_ERR")"
    else
        echo "    Check the URL, run 'gh auth status', and confirm org access."
    fi
    rm -f "$PR_META_ERR"
    return 1
fi
rm -f "$PR_META_ERR"

PR_NUMBER=$(echo "$PR_META" | jq -r '.number')
PR_TITLE=$(echo "$PR_META" | jq -r '.title')
PR_STATE=$(echo "$PR_META" | jq -r '.state')
HEAD_BRANCH=$(echo "$PR_META" | jq -r '.headRefName')
BASE_BRANCH=$(echo "$PR_META" | jq -r '.baseRefName')
PR_AUTHOR=$(echo "$PR_META" | jq -r '.author.login')
CHANGED_FILES=$(echo "$PR_META" | jq -r '.changedFiles')
ADDITIONS=$(echo "$PR_META" | jq -r '.additions')
DELETIONS=$(echo "$PR_META" | jq -r '.deletions')
```

**Sanity-check before continuing:**

```
PR #{PR_NUMBER}: {PR_TITLE}
  State: {PR_STATE}
  Author: @{PR_AUTHOR}
  Base ← Head: {BASE_BRANCH} ← {HEAD_BRANCH}
  Changes: +{ADDITIONS} −{DELETIONS} across {CHANGED_FILES} files

Proceed with review? (y/N)
```

If the PR is large (>50 files or >5000 changed lines), warn and ask the user to confirm scope. Suggest splitting by directory if they accept.

If the PR is CLOSED or MERGED, also warn, reviewing closed PRs is valid (post-merge audit) but the user should know they're commenting on a non-active PR.

**Self-review detection.** Compare the authenticated `gh` user to the PR author. If they match, the review is a self-review, set a flag that adjusts framing in Phase 7.

```bash
GH_LOGIN=$(gh api user --jq .login 2>/dev/null)
if [ "$GH_LOGIN" = "$PR_AUTHOR" ]; then
    SELF_REVIEW=true
    echo ""
    echo "⚠️  You're reviewing your own PR ($GH_LOGIN == @$PR_AUTHOR)."
    echo "    Self-reviews have systematically lower yield than cross-team reviews."
    echo "    This run will adjust:"
    echo "      - Phase 7 prompt asks 'what would a skeptical teammate who doesn't"
    echo "        know your intent ask?' instead of 'find bugs'"
    echo "      - threshold for raising small things is lower (no second pair of eyes)"
    echo "      - the verdict block's expected-yield line warns you up front that"
    echo "        most self-review findings will be things you already considered"
    echo ""
else
    SELF_REVIEW=false
fi
```

Store `SELF_REVIEW` for Phase 7's prompt + Phase 8's draft-yield line.

---

## Phase 1: Clone or locate the repo

```bash
GLOBAL_ROOT="$HOME/ar-global-pr-reviewer"
# Key by $OWNER/$REPO, not bare $REPO. Same repo name can exist under
# different orgs (org-a/foo vs org-b/foo); without the owner segment the
# second clone would collide with the first.
REPO_DIR="$GLOBAL_ROOT/repos/$OWNER/$REPO"
mkdir -p "$GLOBAL_ROOT/repos/$OWNER"

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "→ Cloning $OWNER/$REPO into $REPO_DIR..."
    gh repo clone "$OWNER/$REPO" "$REPO_DIR" -- --depth=200 --no-tags
    # depth=200 keeps clone fast for typical PRs; if the base branch's tip
    # is older, deepen on demand below.
else
    echo "→ Reusing existing clone at $REPO_DIR"
    git -C "$REPO_DIR" fetch origin --quiet
fi

# Ensure we have both base and head reachable (for the diff)
if ! git -C "$REPO_DIR" rev-parse "origin/$BASE_BRANCH" >/dev/null 2>&1; then
    git -C "$REPO_DIR" fetch origin "$BASE_BRANCH" --quiet
fi
if ! git -C "$REPO_DIR" rev-parse "origin/$HEAD_BRANCH" >/dev/null 2>&1; then
    git -C "$REPO_DIR" fetch origin "$HEAD_BRANCH" --quiet
fi

# If merge-base resolution fails (likely shallow clone problem), deepen
if ! git -C "$REPO_DIR" merge-base "origin/$BASE_BRANCH" "origin/$HEAD_BRANCH" >/dev/null 2>&1; then
    echo "→ Deepening clone to find merge-base..."
    git -C "$REPO_DIR" fetch --deepen=500 origin "$BASE_BRANCH" "$HEAD_BRANCH" --quiet
fi
```

---

## Phase 2: Create the review worktree

Use the `a_g_worktree_review` helper from agentic-devkit. It already handles PR-number resolution, `review-pr-{N}` naming, dotfile copying, and auto-cd.

```bash
cd "$REPO_DIR"

# a_g_worktree_review comes from agentic-devkit. In an interactive shell it is
# sourced by name. Claude Code's Bash tool runs non-interactive (helpers not
# sourced), so resolve it directly from the devkit scripts dir.
WT_DIR="${AGENTIC_DEVKIT_DIR:-$HOME/agentic-devkit}/scripts"
if [ ! -f "$WT_DIR/a_g_worktree_review" ]; then
    echo "❌ a_g_worktree_review not found. Install agentic-devkit (run its install.sh)."
    return 1
fi

# Source it (the script uses `return` not `exit`, designed to be sourced)
INPUT="$PR_NUMBER" source "$WT_DIR/a_g_worktree_review" "$PR_NUMBER"
# That cd's us into the new review worktree at:
#   /(dirname REPO_DIR)/WorkTrees/$REPO/review-pr-$PR_NUMBER/
# Capture it:
WORKTREE_DIR="$(pwd)"
```

If you prefer to avoid sourcing in this context (e.g., the skill is being invoked headlessly), do the worktree creation inline:

```bash
WORKTREE_DIR="$GLOBAL_ROOT/repos/$OWNER/WorkTrees/$REPO/review-pr-$PR_NUMBER"
mkdir -p "$(dirname "$WORKTREE_DIR")"
LOCAL_REVIEW_BRANCH="review-pr-$PR_NUMBER"
# If already exists from prior session, reuse
if [ ! -d "$WORKTREE_DIR" ]; then
    git -C "$REPO_DIR" worktree add -b "$LOCAL_REVIEW_BRANCH" "$WORKTREE_DIR" "origin/$HEAD_BRANCH"
fi
cd "$WORKTREE_DIR"
```

---

## Phase 3: Detect project rules + existing reviewers

This is the "intelligently follow the project's existing process" part of the skill. Scan multiple known config locations; combine findings into a single context summary.

```bash
REVIEW_DIR="$GLOBAL_ROOT/reviews/PR-$PR_NUMBER-$(echo "$PR_TITLE" | tr -cd '[:alnum:]-_' | head -c 40)"
mkdir -p "$REVIEW_DIR"

# Save PR metadata for audit
echo "$PR_META" > "$REVIEW_DIR/pr-meta.json"
```

**Detect rule files**, try each location, collect whatever exists. Rules can live in any of these:

| Location | What it usually contains |
|---|---|
| `CLAUDE.md` (root) | AI assistant primary instructions |
| `AGENTS.md` (root) | Agent-level project instructions |
| `docs/ai-rules/*.md` | framework convention |
| `.claude/ai-rules/*.md` | Alternative location some projects use |
| `.cursorrules` | Cursor IDE rules |
| `.windsurfrules` | Windsurf IDE rules |
| `docs/CONTRIBUTING.md` / `CONTRIBUTING.md` | Human contributor guide |
| `docs/conventions/`, `docs/standards/` | Free-form |
| `README.md` (last section, usually "Contributing") | Sometimes the only rules doc |

Build a unified rules context:

```bash
# globstar enables ** to match nested directories; nullglob makes non-matching
# patterns expand to nothing instead of the literal pattern string. Without
# both, the docs/ai-rules/**/*.md and .claude/ai-rules/**/*.md patterns silently
# skip nested rule directories on default bash.
shopt -s globstar nullglob 2>/dev/null
RULES_CONTEXT=""
for candidate in \
    CLAUDE.md AGENTS.md \
    docs/ai-rules/*.md docs/ai-rules/**/*.md \
    .claude/ai-rules/*.md .claude/ai-rules/**/*.md \
    .cursorrules .windsurfrules \
    docs/CONTRIBUTING.md CONTRIBUTING.md \
    docs/conventions/*.md docs/standards/*.md
do
    [ -f "$candidate" ] || continue
    RULES_CONTEXT="$RULES_CONTEXT

--- $candidate ---
$(cat "$candidate")"
done
```

**Detect existing reviewers** (automation already running on the PR):

| Signal | Tool | Categories it covers |
|---|---|---|
| `.coderabbit.yaml` / `.coderabbit.yml` | CodeRabbit | Style, simple bugs, unused imports, naming |
| `.github/workflows/*.yml` with `sonarqube` / `sonar-scanner` | SonarQube | Code smells, security hotspots, duplication |
| `.github/workflows/*.yml` with `lint`/`format`/`prettier`/`eslint`/`checkstyle`/`spotbugs` | Linters | Style, format, common smells |
| `.github/workflows/*.yml` with `codeql` | CodeQL | Security |
| `.github/CODEOWNERS` | Human reviewers assigned | (informational only, don't dedup against humans) |

```bash
EXISTING_REVIEWERS=""
# Explicit if/then for the CodeRabbit check. `[ A ] || [ B ] && action`
# is a classic precedence footgun, POSIX `&&`/`||` are left-associative
# with equal precedence, so the intent ("either file exists → action") is
# only accidentally preserved here, and shellcheck (SC2015) flags it. The
# grep-based detections below are `cmd && action` (single test) and don't
# share the same ambiguity.
if [ -f ".coderabbit.yaml" ] || [ -f ".coderabbit.yml" ]; then
    EXISTING_REVIEWERS="$EXISTING_REVIEWERS coderabbit"
fi
grep -l -iE 'sonarqube|sonar-scanner' .github/workflows/*.y*ml 2>/dev/null >/dev/null && EXISTING_REVIEWERS="$EXISTING_REVIEWERS sonarqube"
grep -l -iE '\b(lint|format|prettier|eslint|checkstyle|spotbugs)\b' .github/workflows/*.y*ml 2>/dev/null >/dev/null && EXISTING_REVIEWERS="$EXISTING_REVIEWERS linters"
grep -l -i 'codeql' .github/workflows/*.y*ml 2>/dev/null >/dev/null && EXISTING_REVIEWERS="$EXISTING_REVIEWERS codeql"
EXISTING_REVIEWERS="$(echo "$EXISTING_REVIEWERS" | xargs)"  # trim
```

**Categories to SKIP based on detected tools** (so we don't post stuff a bot already caught):

| If detected | Skip these categories |
|---|---|
| `coderabbit` | unused imports, simple naming, missing docstrings, format-only suggestions |
| `linters` | code formatting, missing semicolons, indent issues, simple style |
| `sonarqube` | code smells (cognitive complexity, magic numbers, duplicated blocks), most security-hotspot patterns |
| `codeql` | known-pattern security issues (SQL injection, XSS, hardcoded creds) |

**Categories we should ALWAYS cover** (these tools rarely catch):

- Logical bugs introduced by the diff (the change does X when it should do Y)
- Edge cases not handled (null/empty/concurrent/error paths)
- API misuse (wrong arg order, deprecated method, contract violation)
- Missing tests for new behaviour
- Behavioural regressions implied by the diff but not addressed
- Cross-file consistency (changed name in file A, callers in file B not updated)
- Documentation drift (changed behaviour, docstring still describes old behaviour)

Save the rules + reviewers summary to `$REVIEW_DIR/project-rules-summary.md` for audit:

```markdown
# Project rules + reviewer context, PR #{N}

## Rule sources detected

{list of each file found, with a one-line summary}

## Existing automated reviewers

- CodeRabbit: {yes/no, config at .coderabbit.yaml}
- SonarQube: {yes/no, referenced in .github/workflows/X.yml}
- Linters: {yes/no, eslint/prettier/checkstyle in workflows}
- CodeQL: {yes/no}

## Categories this review will SKIP

{list, based on detected reviewers}

## Categories this review will COVER

{list, always-covered categories}
```

---

## Phase 4: Environment setup (best-effort to SUCCEED, not to TRY)

"Best-effort" here means **best-effort to make setup succeed**, not best-effort to attempt and bail at the first hiccup. The review needs a real local signal, without it, the only signal is what the PR description claims, and the PR description is not a source of truth.

### What NOT to skip

Common rationalisations to refuse:

| Rationalisation | Right move |
|---|---|
| "The PR description says tests pass" | Not your job to trust, verify. Launch the build/test yourself. |
| "First build is slow" | Launch in the background (see below); proceed with Phases 6-7 in parallel; fold results in at Phase 8. |
| "Java not on PATH" / "no Maven wrapper" | Detect `.tool-versions`, `.java-version`, `pom.xml`, `build.gradle`. Tell the user what to install in the log. PROCEED without blocking the review, but log specifically what stopped you, vague "skipped" entries are worthless to a follow-up run. |
| "Setup looked complicated, skipping" | Log what you tried, what failed, why you stopped. The log entry must be actionable enough that a follow-up run can resolve it manually. |

The review is non-blocking on setup outcome, that's by design. But you MUST attempt it, and the attempt log must be specific.

### Launching in the background

Setup AND test commands MUST be launched via the **Bash tool with `run_in_background: true`** so the review-reading work in Phases 6-7 proceeds in parallel. Don't block the review on `./gradlew dependencies` or `npm install` finishing.

Pattern:

1. Launch setup command in background, capture the shell-id. Tee output to `$REVIEW_DIR/env-setup.log`.
2. Continue immediately into Phase 5's test-launch (also background), then Phase 6 diff generation, then Phase 7 review-reading.
3. Before Phase 8 drafts the verdict, check the background tasks' output (`BashOutput` / `TaskOutput` as available). If still running, wait briefly; if hung beyond reasonable timeout, kill and record the timeout in the log.

The setup and test logs become **part of the review evidence** that Phase 7 reads. A skipped/failed setup is fine; a setup that wasn't even attempted is a defect.

> 💡 **LLM directive:** The bash block below is the COMMAND CONTENT. Launch it via the Bash tool with `run_in_background: true`, do NOT run it inline. Running inline blocks Phases 6-7 for up to 5 minutes (the `timeout 300` ceiling on each setup branch), which defeats the whole point of the background-launch pattern documented above.

```bash
SETUP_LOG="$REVIEW_DIR/env-setup.log"
exec 3>&1 4>&2  # save stdout/stderr for status echo
{
    echo "=== Setup attempt: $(date) ==="
    SETUP_SUCCESS=false

    # Prefer Docker if a docker-compose exists, most consistent across machines
    if [ -f "docker-compose.yml" ] || [ -f "compose.yml" ]; then
        echo "→ Detected docker-compose. Skipping auto-up (risky); user can start manually."
        SETUP_TYPE="docker-compose (not started)"
        SETUP_SUCCESS=true
    # Java/Gradle
    elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
        echo "→ Detected Gradle project."
        SETUP_TYPE="gradle"
        if [ -x "./gradlew" ]; then
            echo "→ Running ./gradlew dependencies (download only, no build)..."
            timeout 300 ./gradlew dependencies --no-daemon 2>&1 && SETUP_SUCCESS=true
        else
            echo "  warn: no gradle wrapper; skipping setup."
        fi
    # Java/Maven
    elif [ -f "pom.xml" ]; then
        echo "→ Detected Maven project."
        SETUP_TYPE="maven"
        if [ -x "./mvnw" ]; then
            echo "→ Running ./mvnw dependency:resolve..."
            timeout 300 ./mvnw dependency:resolve --quiet 2>&1 && SETUP_SUCCESS=true
        else
            echo "  warn: no maven wrapper; skipping setup."
        fi
    # Node
    elif [ -f "package.json" ]; then
        echo "→ Detected Node project."
        SETUP_TYPE="node"
        if [ -f "pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
            timeout 300 pnpm install --frozen-lockfile 2>&1 && SETUP_SUCCESS=true
        elif [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
            timeout 300 yarn install --frozen-lockfile 2>&1 && SETUP_SUCCESS=true
        elif [ -f "package-lock.json" ]; then
            timeout 300 npm ci 2>&1 && SETUP_SUCCESS=true
        else
            timeout 300 npm install 2>&1 && SETUP_SUCCESS=true
        fi
    # Python
    elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
        echo "→ Detected Python project."
        SETUP_TYPE="python"
        # Don't auto-create venv, too easy to pollute. Just check imports possible.
        echo "  note: Python setup not automated; user should activate venv manually."
        SETUP_SUCCESS=false
    else
        echo "→ No recognised project type. Skipping setup."
        SETUP_TYPE="unknown"
        SETUP_SUCCESS=false
    fi
    echo "Setup: $SETUP_TYPE, $([ "$SETUP_SUCCESS" = true ] && echo "OK" || echo "skipped/failed")"
} >"$SETUP_LOG" 2>&1
exec 1>&3 2>&4

echo "→ Setup: $SETUP_TYPE, $([ "$SETUP_SUCCESS" = true ] && echo "OK" || echo "skipped (see $SETUP_LOG)")"
```

**Port management:** when running anything that needs a port (DB, app server, mock server), find a free port and pass it via env var. Pattern:

```bash
# Pick a free port (uses Python or netcat as available)
find_free_port() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()"
    else
        # Fallback: scan from 49152 (ephemeral range) upward
        for p in $(seq 49152 65535); do
            (echo >/dev/tcp/localhost/$p) >/dev/null 2>&1 || { echo "$p"; return; }
        done
    fi
}
# Example use: SERVER_PORT=$(find_free_port) ./gradlew bootRun
```

Only spin up services if tests need them. Log the chosen port in `$REVIEW_DIR/env-setup.log` so the user knows what was used.

---

## Phase 5: Run tests (best-effort to SUCCEED, not to TRY)

Same rule as Phase 4: best-effort means best-effort to actually get a test signal, not to attempt and skip. The model MUST launch tests if setup succeeded, and ALSO launch them in the background so Phases 6-7 proceed in parallel.

The same "what NOT to skip" rationalisations from Phase 4 apply here. In particular:

- "Tests are too slow", launch in background; the review-reading work covers the wait. Timeout is per-language (1200s Java, 600s Node).
- "Test depends on a service I don't have", pick the smallest subset that doesn't need that service (unit-only / `--exclude-tags integration`), launch THAT, log what was excluded.
- "Tests failed but it's flake", fold the failure into the review draft; don't suppress it. Flake is noted; non-flake is a finding.

Strategy: only run tests TOUCHED by the diff if possible (faster, more focused). Fall back to full suite if scoping isn't feasible.

> 💡 **LLM directive:** The bash block below is the COMMAND CONTENT. Launch it via the Bash tool with `run_in_background: true`, do NOT run it inline. The block carries `timeout 1200` (Java) / `timeout 600` (Node) ceilings; running it inline would freeze Phases 6-7 for up to 20 minutes and the parallelism documented above would be lost.

```bash
TEST_LOG="$REVIEW_DIR/test-run.log"
TEST_VERDICT="not-run"
TESTS_RAN=false

if [ "$SETUP_SUCCESS" = true ]; then
    {
        echo "=== Test run: $(date) ==="
        # Identify changed test files
        CHANGED_TEST_FILES=$(git diff --name-only "origin/$BASE_BRANCH...origin/$HEAD_BRANCH" \
            | grep -iE '(test|spec)\.(java|kt|js|ts|py)$|/(test|tests|__tests__)/' | head -50)

        case "$SETUP_TYPE" in
            gradle*)
                if [ -n "$CHANGED_TEST_FILES" ]; then
                    # Run only changed test classes. Gradle's --tests flag treats its
                    # value as ONE literal pattern, so a comma-joined "A,B,C" string
                    # matches no real class → 0 tests run → exit 0 → false "pass"
                    # verdict. Emit one --tests flag per class instead.
                    test_classes=$(echo "$CHANGED_TEST_FILES" | sed -E 's|.*/([^/]+)\.(java|kt)$|\1|' | sort -u)
                    tests_args=()
                    while IFS= read -r tc; do
                        [ -n "$tc" ] && tests_args+=(--tests "$tc")
                    done <<< "$test_classes"
                    if [ "${#tests_args[@]}" -gt 0 ]; then
                        timeout 1200 ./gradlew test "${tests_args[@]}" --no-daemon 2>&1
                    else
                        timeout 1200 ./gradlew test --no-daemon 2>&1
                    fi
                else
                    timeout 1200 ./gradlew test --no-daemon 2>&1
                fi
                TEST_EXIT=$?
                TESTS_RAN=true
                ;;
            maven*)
                timeout 1200 ./mvnw test --quiet 2>&1
                TEST_EXIT=$?
                TESTS_RAN=true
                ;;
            node*)
                # Most projects expose `test` script
                if [ -n "$CHANGED_TEST_FILES" ] && jq -re '.scripts["test:changed"]' package.json >/dev/null 2>&1; then
                    timeout 600 npm run test:changed 2>&1
                else
                    timeout 600 npm test 2>&1
                fi
                TEST_EXIT=$?
                TESTS_RAN=true
                ;;
            *)
                echo "→ Test command unknown for $SETUP_TYPE; skipping."
                # TESTS_RAN stays false; TEST_VERDICT stays "not-run". Do NOT
                # let a fall-through here ($? = 0 from the echo) get mapped to
                # "pass", that would silently fabricate a green test signal
                # for setup types we don't actually exercise (docker-compose,
                # python, unknown).
                ;;
        esac

        if [ "$TESTS_RAN" = true ]; then
            case "$TEST_EXIT" in
                0) TEST_VERDICT="pass" ;;
                124) TEST_VERDICT="timeout" ;;
                *) TEST_VERDICT="fail" ;;
            esac
        fi
        echo "=== Verdict: $TEST_VERDICT ==="
    } >"$TEST_LOG" 2>&1
fi

echo "→ Tests: $TEST_VERDICT"
```

The verdict feeds into the review as **one signal among several**, a passing test suite doesn't mean the diff is correct, and a failing one doesn't mean it's wrong (may be unrelated flake). Always report exact test names that failed when relevant.

---

## Phase 6: Generate review context

Build the data the reviewer model will see.

```bash
# Diff
git diff "origin/$BASE_BRANCH...HEAD" > "$REVIEW_DIR/review.diff"

# Existing PR comments, for dedup.
# `--jq '.[] | {…}'` would emit one object per line (NDJSON); wrap the
# projection in `[ … ]` so the file is a real JSON array and Phase 7's
# reader can `jq '.[]'` it normally.
gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments" \
    --jq '[.[] | {id: .id, path: .path, line: .line, position: .position, body: .body, user: .user.login, in_reply_to_id: .in_reply_to_id}]' \
    > "$REVIEW_DIR/existing-comments.json"

# Also fetch issue-level (non-inline) comments for context. Same array wrap.
gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" \
    --jq '[.[] | {id: .id, body: .body, user: .user.login, created_at: .created_at}]' \
    > "$REVIEW_DIR/existing-comments-issue.json"
```

---

## Phase 6.5: Classify each potential finding

Before any finding is added to the draft, classify it as one of:

- **PR-INTRODUCED**, this PR's diff added/modified the offending code
- **PR-EXPOSED**, the PR makes a latent bug reachable (new caller / new code path that now exercises pre-existing buggy code)
- **PRE-EXISTING**, same issue exists in unchanged sibling code; the PR didn't cause it

**Procedure: see [`checks/classifier.md`](checks/classifier.md).**

Quick summary:

1. `git log -p -S<symbol>` over the change range → were the offending lines touched by THIS PR?
2. `git grep <pattern>` in unchanged sibling files → does the same issue exist there too?
3. PRE-EXISTING findings move to the draft's "Notes" section, NOT inline comments. Reframe as "this PR is a good moment to fix N other locations", never phrase as if the PR caused it.

Findings without a classification are rejected from the draft. This is the #1 source of low-confidence noise in v1, silently flagging pre-existing issues as if the PR introduced them.

---

## Phase 6.6: Author-intent check

For each surviving finding, check whether the author already considered the topic. Grep the PR body, commit messages, and any referenced tickets for evidence.

**Procedure: see [`checks/author-intent.md`](checks/author-intent.md).**

Quick summary: if the author left a trace (PR body, commit msg, ticket comment, code comment) showing they considered the topic, reframe the comment as a **question**, not a finding. "You noted X in the PR body, does that hold under condition Y?" beats "Y is wrong." Findings that ignore author intent burn reviewer credibility.

Skip this check for high-confidence + high-impact findings (NPE, security, data corruption) and for bot-authored PRs.

---

## Phase 7: Review

This is where the model does the actual reading and reasoning. Invoke the `a_sag_code_reviewer` agent if available; otherwise reason inline.

**Prompt for the reviewer (you, the model, OR a subagent):**

```
You are reviewing PR #{PR_NUMBER} on {OWNER}/{REPO}: "{PR_TITLE}".

INPUTS:
  - Diff:                   $REVIEW_DIR/review.diff
  - PR metadata:            $REVIEW_DIR/pr-meta.json
  - Project rules summary:  $REVIEW_DIR/project-rules-summary.md
  - Existing comments:      $REVIEW_DIR/existing-comments.json + existing-comments-issue.json
  - Setup log:              $REVIEW_DIR/env-setup.log
  - Test results log:       $REVIEW_DIR/test-run.log (verdict: $TEST_VERDICT)
  - Working tree:           $(pwd)  (you may open and read any file)

REVIEW SCOPE, focus on:
  - Logical bugs introduced by the diff
  - Edge cases not handled (null/empty/concurrent/error paths)
  - API misuse (wrong arg order, deprecated method, contract violation)
  - Missing tests for new behaviour
  - Behavioural regressions implied by the diff but not addressed
  - Cross-file consistency (renamed something in file A, callers in file B unchanged?)
  - Documentation drift (changed behaviour, docs still describe old)

REVIEW SCOPE, explicitly SKIP (covered by existing automated reviewers):
$(cat $REVIEW_DIR/project-rules-summary.md | sed -n '/Categories this review will SKIP/,/^##/p')

CLASSIFICATION (mandatory per Phase 6.5, see checks/classifier.md):
  - Tag each potential finding as PR-INTRODUCED, PR-EXPOSED, or PRE-EXISTING.
  - PRE-EXISTING findings move to "Notes" (not inline). Reframe, never as
    if the PR caused them.

AUTHOR INTENT (mandatory per Phase 6.6, see checks/author-intent.md):
  - Grep PR body, commit messages, referenced tickets for evidence the author
    considered the topic.
  - If yes → reframe as a question, not a finding.
  - Skip this softener for high-confidence + high-impact findings (NPE,
    security, data corruption).

SELF-REVIEW MODE (set in Phase 0):
  - SELF_REVIEW=$SELF_REVIEW
  - If true: ask "what would a skeptical teammate who DOESN'T know your intent ask?"
    rather than "find bugs". Lower the threshold for small things, no second pair of eyes.

DEDUP + CROSS-REFERENCE, for each potential comment, before drafting it:
  1. Read existing-comments.json + existing-comments-issue.json.
  2. If a substantively similar comment is already posted (same file, same area,
     same root cause), DO NOT add a duplicate. Note in your private log
     "skipped: dup of #COMMENT_ID".
  3. If the existing comment partially addresses the issue but missed something,
     post a follow-up, but reference the existing comment.
  4. CROSS-REFERENCE automated reviewers' OUTPUT (not just presence):
     - Filter existing comments by bot users (coderabbit-ai, github-actions[bot],
       sonarqubecloud, etc.).
     - IF a bot reviewer posted "no actionable comments" / "looks good" / approved:
       BAR GOES UP. The bot's threshold is lower than yours; if it found nothing,
       your findings should be ones it CAN'T see (logical bugs, edge cases not
       caught by patterns). Be more confident before posting.
     - IF a bot posted multiple findings: READ them. For each, mark in the draft
       whether you AGREE / DISAGREE / UNRELATED. Don't ignore them, that wastes
       the author's time when your comments unknowingly overlap.

COMMENT FORMAT, each comment is a markdown body with this shape:

  **{One-sentence summary}**

  **Classification:** PR-INTRODUCED | PR-EXPOSED | PRE-EXISTING
  **Confidence:** high | medium | low, {one-line justification}
  **What I checked:**
  - {evidence bullet, be specific, e.g. "traced exception through 3 call sites"}
  - {evidence bullet, e.g. "ran failing test FooTest.testBar locally"}
  - {evidence bullet, e.g. "grep'd for callers in module-server"}

  {What's wrong, in 1-3 sentences.}

  ```suggestion
  {OPTIONAL: if you can confidently write the exact replacement code, put it
   here. GitHub renders ```suggestion blocks as one-click apply buttons.
   ONLY use if the fix is unambiguous. Don't paste speculation here.}
  ```

  {OPTIONAL: a brief AI-prompt the human can copy if they want Claude to fix
   it for them. Keep it small, 1-2 sentences max.}

OUTPUT, write your review as a markdown file at $REVIEW_DIR/review-draft.md
in this shape:

  # Review: PR #{N}, {title}

  ## Verdict

  **Outcome:** NEEDS_CHANGES | APPROVED | COMMENTS_ONLY
  **Review confidence:** {1-10}/10, {one-line justification of what you did/didn't do}
  **Expected yield:** {one-line calibration, see examples below}
  **Self-review:** {YES, adjusted framing | no}
  **Test signal:** pass/fail/skipped, {what failed if known}
  **Scope skipped:** {brief, e.g., "style/format (eslint covers)"}

  Honest defaults, do NOT default to high confidence:

  - "Review confidence: 7/10, ran tests locally, traced one finding end-to-end.
     Didn't dig into the upstream client retry path."
  - "Review confidence: 3/10, didn't run tests, didn't have time to read the
     called services. Treat findings as hypotheses, not verdicts."

  Yield calibration examples:

  - "Self-review of a 100-line PR: low yield. Most findings will be things
     you already considered. Don't over-engineer comments."
  - "Cross-team review of a 2000-line refactor: medium-high yield. Pedantic
     verification is your value-add."

  If phases were skipped (setup didn't complete, tests didn't run, didn't
  read called services), the confidence score MUST reflect that.

  ## Inline comments

  ### {file}:{line}
  - [ ] {summary}

    {body, same shape as COMMENT FORMAT above}

  ### {file}:{line}
  ...

  ## Notes (not posted as comments)

  - {observations that are decision-relevant but don't warrant a PR comment}

DO NOT POST anything yet, only write the draft. The user reviews the
checkboxes and decides which comments to publish.
```

---

## Phase 8: Draft for user approval

Show the user the draft:

```
✓ Review draft ready at: $REVIEW_DIR/review-draft.md

{cat the file}

Edit the file to:
  - Uncheck [ ] any comment you don't want to post
  - Reorder/merge comments if some belong together
  - Tweak wording on anything you'd phrase differently
  - Mark low-confidence comments with `[Q]` prefix to post as a question
    instead of an inline finding (top-level PR comment asking the author
    for reasoning, rather than annotating their code as wrong)

When ready, type "post" to publish the checked comments AND auto-remove the
  review worktree.
Type "post + keep worktree" to publish AND skip the worktree cleanup
  (you want to follow up locally based on what landed).
Type "cancel" to abandon (the draft file is kept for your reference).

Low-confidence findings (Confidence < medium) are good candidates for the
`[Q]` prefix, many low-confidence findings are actually requests for
clarification dressed up as critique.
```

Wait for the user's response. If they edit and re-show, show the diff of what changed.

---

## Phase 9: Post inline comments

For each checked comment in `review-draft.md`, post via `gh api`. GitHub's inline-comment API needs:

- `body`, the comment text (markdown)
- `commit_id`, head SHA of the PR
- `path`, file path relative to repo root
- `line` (or `position`), the line in the file

```bash
HEAD_SHA=$(echo "$PR_META" | jq -r '.headRefOid // empty')
[ -z "$HEAD_SHA" ] && HEAD_SHA=$(git -C "$REPO_DIR" rev-parse "origin/$HEAD_BRANCH")

# For each checked comment in review-draft.md:
# Reject empty $LINE upstream, gh would happily POST `line=` and the API
# would return 422 with no usable error. Skip the comment and log loudly
# instead so the draft can be corrected.
if [ -z "$LINE" ]; then
    echo "⚠️  Empty line number for $FILE_PATH, skipping comment. Fix the draft and re-run." >&2
    continue
fi
gh api \
    --method POST \
    "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments" \
    -f body="$COMMENT_BODY" \
    -f commit_id="$HEAD_SHA" \
    -f path="$FILE_PATH" \
    -F line="$LINE" \
    -f side='RIGHT'
```

Side is `RIGHT` (the head version) for almost all comments; `LEFT` only when commenting on a removed line.

After all comments posted, report:

```
✓ Posted {N} comments to {PR_URL}.
  - Skipped {M} as duplicates of existing comments.
  - {K} comments included one-click fix suggestions.

Review draft saved at: $REVIEW_DIR/review-draft.md
```

---

## Phase 9.5: Cleanup (default: REMOVE worktree)

After posting, automatically remove the review worktree AND the local `review-pr-{N}` branch. Worktrees accumulated in v1 because cleanup defaulted to "keep"; that bloated disk and made the layout messy.

```bash
# Invoke the script directly. The `a_g_worktree_remove` shell function defined
# in worktree.sh is only available in interactive shells that sourced the rc
# block. Claude Code's Bash tool calls run non-interactive, the function
# would be "command not found" and the fallback would run every single time.
# Calling the script binary works in both interactive and non-interactive
# contexts and keeps a single source of truth for the cleanup logic.
#
# --force is REQUIRED. Without it, a_g_worktree_remove drops into an
# interactive `read -r REPLY` confirmation prompt; in Claude Code's
# non-interactive Bash the read returns empty + non-zero, the script prints
# "Cancelled." and exits 0. The `|| echo` warning never fires and the
# worktree silently accumulates on disk. --force bypasses the prompt and
# the unpushed-commits check, both of which are irrelevant for a throwaway
# `review-pr-N` branch we just created from a remote tip.
bash "${AGENTIC_DEVKIT_DIR:-$HOME/agentic-devkit}/scripts/a_g_worktree_remove" --force "review-pr-$PR_NUMBER" 2>&1 || \
    echo "⚠️  Worktree cleanup failed; inspect '$WORKTREE_DIR' manually if it's still present."
```

### Skip cleanup if any of

- Zero comments were posted (approve-only / all-questions; no follow-up expected anyway)
- User typed "post + keep worktree" or "keep worktree" in Phase 8
- A `gh api` comment-post failed mid-product, preserve the debugging surface so the user can re-try without re-cloning

The clone at `~/ar-global-pr-reviewer/repos/$OWNER/$REPO/` is **always kept**, it's cheap (just refs) and speeds up future reviews of any PR in the same repo.

---

## Failure modes + recovery

| Symptom | Cause | Fix |
|---|---|---|
| "gh CLI not authenticated" | First-time use | `gh auth login` |
| "Could not fetch PR" | Wrong URL or no access | Check URL, check `gh auth status`, verify org membership |
| Worktree creation fails | A worktree at the path already exists | `a_g_worktree_remove review-pr-{N}` then re-run |
| Setup hangs / times out | Project needs interactive input or unusual setup | Look at `$REVIEW_DIR/env-setup.log`; you can manually `cd $WORKTREE_DIR` and set up yourself, then re-invoke the skill, it'll skip the setup phase if `$REVIEW_DIR/env-setup.log` exists from this session |
| Tests fail with unrelated flake | The diff didn't cause it | Mention in review notes; don't gate the review on it |
| `gh api` post returns 422 | Likely line out of diff range (commented on a line the PR didn't touch) | Re-check that the file+line are in `git diff --name-only origin/$BASE...HEAD` |
| Duplicate comments posted | Dedup missed a substantively-similar existing comment | Tighten the dedup criteria in Phase 7 prompt; consider asking user before posting if a near-match exists |

---

## Notes

- **Clones in `~/ar-global-pr-reviewer/repos/` are full clones** (depth=200 initially, deepened on demand). They're NOT cleaned up automatically, you can `du -sh ~/ar-global-pr-reviewer/repos/*` to check size and `rm -rf` directories you don't need.
- **Worktrees live alongside the clones** under `repos/$OWNER/WorkTrees/$REPO/`. The `a_g_worktree_*` helpers manage them.
- **This skill never modifies the project's `main` or `master` branch**, only the `review-pr-{N}` local branch in a worktree.
- **Comments are posted as YOU** (your authenticated `gh` user). The PR's other watchers will see them as your reviews. There's no "AI bot" identity for these.
- **For multi-PR review** (a feature split across PRs): invoke the skill once per PR. Cross-PR analysis is out of scope for v1, use `a_sk_review_pr` from inside a checkout if you need that.
