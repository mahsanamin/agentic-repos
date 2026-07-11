> **STOP. Do not execute this file directly.**
>
> This file is a **procedures reference**, not a runnable script.
>
> - **Adopt in a repo (fresh):** the `ar-install` skill, say `ar-install at /path/to/project`
> - **Refresh an adopted repo:** the `ar-upgrade` skill, say `ar-upgrade at /path/to/project`
> - **Install the global layer on a machine:** `./install.sh` from the framework root (or the `ar-install-tools` skill)
> - **Framework development:** the `ar-add-improvement` skill
>
> The procedures below are referenced by these skills by SECTION NAME and are not run independently.

# Agentic Repos Setup Procedures Reference

Reusable procedures referenced by the `ar-install` and `ar-upgrade` skills.

## Scope: config + rules only

Agentic Repos splits into two layers (see `docs/ARCHITECTURE.md`):

- **Procedure (global):** the `ar-*` driver skills, the devkit agents/skills, the worktree helpers, the SessionStart hook, and the default-branch guard. Installed ONCE per machine by `install.sh` as symlinks into the source repos. Reads the config layer at runtime.
- **Config + Rules (local):** `config_hints.json`, `AGENTS.md`, `.claude/skill.config`, an autonomous `.claude/settings.json` (permissions only), the stack-adapted coding rules extracted into `standards_location`, and PR/commit templates. Written per repo by `ar-install`.

`ar-install` and `ar-upgrade` write ONLY the local layer. They **never** copy `ar-*` skills or devkit agents into a target repo, and they **never** write hooks (the SessionStart workflow hook and the default-branch / force-push guard are wired GLOBALLY by `install.sh` into `~/.claude/settings.json`, so they already cover every repo and must not be duplicated per project). They **never** install framework scripts either: `install.sh` symlinks `scripts/ar-freshness`, `scripts/ar-sonarqube`, and `scripts/ar-session` into `~/.claude/scripts/`, so a skill referencing `~/.claude/scripts/ar-sonarqube/fetch-issues.sh` resolves from the global layer. Agents are invoked by name at runtime (`a_sag_*`), skills likewise (`a_sk_*`, `a_g_worktree_*`); because the global layer is on the machine, those names resolve in every project.

**Formatting rules for ALL generated files (AGENTS.md, CLAUDE.md, config, rule files):**
- One blank line max between sections
- No horizontal rules (`---`) unless a template shows them
- No trailing whitespace, no decorative separators
- Compact and scannable, no fluff

## Precheck: Global Layer Present

Before writing anything into a target repo, confirm the machine has the global layer. `ar-install` and `ar-upgrade` depend on it and must not re-implement it.

```bash
# 1. ar-* skills linked into ~/.claude/skills (install.sh symlinks them)
ls -d "$HOME/.claude/skills/ar-taskflow" >/dev/null 2>&1 && echo "AR_SKILLS_OK" || echo "AR_SKILLS_MISSING"
# 2. agentic-devkit present (agents a_sag_*, skills a_sk_*, worktree a_g_worktree_*)
ls "$HOME/.claude/agents/a_sag_code_reviewer.md" "$HOME/.claude/agents/a_sag_codebase_explorer.md" >/dev/null 2>&1 && echo "DEVKIT_OK" || echo "DEVKIT_MISSING"
# 3. framework dir known
echo "AR_FRAMEWORK_DIR=${AR_FRAMEWORK_DIR:-unset}"
```

If either check is missing, STOP and tell the user:

```
The global Agentic Repos layer is not installed on this machine yet.
Run it once from the framework root, then re-run this command:

  cd <agentic-repos>   # the framework repo
  ./install.sh

This links the ar-* skills, bootstraps agentic-devkit (agents + atomic skills + worktree),
installs the framework scripts, and wires the session hook + default-branch guard. It does
not touch this project.
```

Do NOT attempt to install the global layer from here.

## Content Adaptation Pipeline

The agents and passes that turn a repo's real code into an agent-ready config + rules layer. Used by both `ar-install` and `ar-upgrade`.

**Design for context efficiency:** shared state passes through files on disk in the target root (`_install_config.json`, `_codemap.md`, `_install_manifest.json`), never through conversation context. The main session orchestrates; agents hold small, focused contexts.

### File-Based Handoffs

`_install_config.json` is written by the main session in the gather phase. All gathered configuration:
```json
{
  "target_project": "/path/to/project",
  "framework_path": "/path/to/agentic-repos",
  "project_name": "User Service",
  "tracker": { "type": "github", "url": "" },
  "namespace": "SVC",
  "namespaces": null,
  "standards_location": "docs/ai-rules",
  "existing_state": { "claude_md": true, "agents_md": false, "settings": false, "rules_dirs": [] },
  "saved_claude_md_content": "...",
  "saved_ai_files_content": {},
  "mode": "fresh",
  "framework_version": "1.0.0",
  "stack": "java-spring-boot",
  "applicable_rule_dirs": ["universal", "java-spring-boot"]
}
```

`_codemap.md` is written by `a_sag_codebase_explorer`: the real structure, stack, conventions, and invariants of the repo. The authoritative input to rule extraction.

`_install_manifest.json` lists every file written by a writer pass, merged by the orchestrator:
```json
{ "files_written": [
  { "path": "docs/ai-rules/project-conventions.md", "action": "extracted", "source": "codebase" },
  { "path": "docs/ai-rules/critical-thinking.md", "action": "adapted", "source": "rules/universal/critical-thinking.md" }
] }
```

### Stack Detection (Positive Evidence)

Detect the stack by **positive evidence**, most-specific first. **Language never selects a stack rule set on its own** (Android uses Gradle + Java/Kotlin but is NOT Spring). When no curated stack matches, use `universal` + the language-neutral `_generic` fallback. Never borrow a different language's rule set.

```bash
cd {target_project}
STACK="generic"
if [ -f "AndroidManifest.xml" ] || grep -rqsE 'com\.android\.(application|library)' build.gradle build.gradle.kts settings.gradle settings.gradle.kts 2>/dev/null; then
  STACK="android"
elif ls *.xcodeproj >/dev/null 2>&1 || [ -f "Podfile" ] || [ -f "Package.swift" ]; then
  STACK="ios"
elif grep -rqs "spring-boot" pom.xml build.gradle build.gradle.kts 2>/dev/null \
     || grep -rqsE 'import org\.springframework|@SpringBootApplication' . --include='*.java' --include='*.kt' 2>/dev/null; then
  STACK="java-spring-boot"
elif [ -f "go.mod" ]; then STACK="go"
elif [ -f "Gemfile" ]; then STACK="ruby"
elif [ -f "Cargo.toml" ]; then STACK="rust"
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then STACK="python"
elif [ -f "package.json" ] && grep -qs '"react"' package.json; then STACK="react"
elif [ -f "package.json" ]; then STACK="node"
elif [ -f "pom.xml" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then STACK="jvm-generic"
fi
echo "DETECTED_STACK=$STACK"
```

Map `STACK` to `applicable_rule_dirs` (only map to a stack dir that actually exists under `rules/`, otherwise universal-only):
- `java-spring-boot` gives `["universal", "java-spring-boot"]`
- `react` gives `["universal", "react"]`
- everything else gives `["universal", "_generic"]` (no curated per-stack set yet; extract the project's own conventions from the code, do NOT pull in another stack's set)

This is a hint. The exploration pass may narrow or genericize it, never substitute a different language's stack rules.

### Rule Extraction (the heart of agent-ready)

An agent is only as good as the rules it is handed. A repo with no written conventions produces ad-hoc, inconsistent output. So the core job of adoption is to **read the real code and extract its conventions into rule files** under `standards_location`. Do not merely copy generic templates.

**1. Explore.** Delegate to `a_sag_codebase_explorer`: launch it as a Task to map the repo and write `_codemap.md` (structure, stack, conventions, invariants). Give it only the target path and `_install_config.json`.

**2. Extract into `standards_location`.** From `_codemap.md` and representative source files, write rule files that reflect what the repo actually does (cite real files, use the project's own idioms in Do/Don't examples). Extract only what is genuinely present.

Always extract:
- `project-conventions.md`: the repo's real naming, layout, import ordering, comment/style conventions.

Extract when evidence exists:
- `api-patterns.md`: request/response shape, error format, auth, versioning.
- `database-patterns.md`: query/transaction/migration conventions, entity relationships.
- `testing-patterns.md`: test naming, setup/teardown, mocking, assertion style, data management.
- `error-handling.md`: exception hierarchy, error codes, logging, retry.
- `project-structure.md`: real modules and package layout (detect actual packages; never ship generic placeholders).

**3. Adapt the framework's rules on top.** Install the universal rules from `{framework_path}/rules/universal/` into `standards_location`, and the applicable stack rules from `{framework_path}/rules/{stack}/` (only if `rules/{stack}/` exists), adapting every stack-specific element (package names, paths, commands, entity names, grep patterns) to the target's real values. Keep both the extracted rule and the framework rule when they overlap: the extracted one carries project-specific examples, the framework one carries universal patterns.

**Infrastructure-dependent rules (`requires:` frontmatter).** A rule that documents a concrete in-house facade declares `requires: <symbol>`. Install it ONLY if the target repo already contains that symbol (probe the whole repo, not just top-level `src/`, since backends are often multi-module). Otherwise record it in the install report as "available but not installed: <rule> (requires '<symbol>', not found)" and skip it. On upgrade, if a `requires:` rule is already present but its symbol is now absent, flag it (do not auto-remove).

The extracted rules are the repo's editable surface: a strong starting point, then owned by the team.

### Config Writer

Writes the config seam that every `ar-*` skill reads at runtime. Runs after rule extraction (so it can list the rules).

1. `config_hints.json`: see "config_hints.json Schema" below. Identity (name, namespace/tracker), platform, `standards_location`, and the detected commands.
2. `AGENTS.md`: the single source of truth (see "Create AGENTS.md"). Build commands + project structure from `_codemap.md`, the rule list from `_install_manifest.json`, merged prior AI-file content.
3. `.claude/skill.config`: per-repo paths/state (see "Create .claude/skill.config").
4. `.claude/settings.json`: the autonomous permissions template (see "Write Autonomous Settings").
5. `CLAUDE.md`: the standard `@AGENTS.md` pointer (see "Handle CLAUDE.md and Existing AI Files").

Do NOT read framework skills/agents here; they are not installed per repo.

### Verification (Contamination + Reference Check)

After the rules and config are written, verify no foreign-stack noise or dangling reference shipped. Run in a fresh context: re-detect the stack independently, then scan the WRITTEN files (rules in `standards_location`, `AGENTS.md`, `config_hints.json`). This scans the local layer only; there are no per-repo skills/agents to check.

```bash
cd {target_project}
std="$(jq -r '.standards_location // "docs/ai-rules"' .claude/config_hints.json)"
stack="$(jq -r '.stack // .platform // "generic"' .claude/config_hints.json)"
violations=0

# (1) UNRESOLVED PLACEHOLDERS in written rules/config/AGENTS.md.
if grep -rnE '\{project\}|\{namespace\}|\{standards_location\}|com\.example\.\{' "$std" AGENTS.md 2>/dev/null; then
  echo "unresolved placeholders above"; violations=$((violations+1))
fi

# (2) DANGLING RULE REFERENCES: every rule .md referenced by a written rule must exist in $std.
refs=$(grep -rhoE '[a-z0-9-]+\.md' "$std" AGENTS.md 2>/dev/null | grep -vE '^(README|CLAUDE|AGENTS)\.md$' | sort -u)
for r in $refs; do
  case "$r" in
    *-conventions.md|*-patterns.md|*-standards.md|*-policy.md|project-structure.md|error-handling.md|critical-thinking.md|code-review.md|task.md)
      [ -f "$std/$r" ] || { echo "dangling rule reference: $r (not in $std/)"; violations=$((violations+1)); } ;;
  esac
done

# (3) FOREIGN-LANGUAGE IDIOMS: for non-JVM stacks, no hardcoded Java/Gradle instructions in the rules.
case "$stack" in
  java-spring-boot|jvm-generic|android|kotlin) ;;
  *)
    foreign=$(grep -rnoE 'gradlew|\*Test\.java|src/test/java|@RestController|@GetMapping|@Transactional|JpaRepository|@SpringBootTest|application\.yml' "$std" 2>/dev/null \
              | grep -vE 'e\.g\.|example|Example|for Gradle|for Java|detect|whichever|or the project')
    if [ -n "$foreign" ]; then echo "foreign-language idioms for stack '$stack':"; echo "$foreign" | head -20; violations=$((violations + $(echo "$foreign" | grep -c .))); fi ;;
esac

if [ "$violations" -gt 0 ]; then
  echo "VERIFY FAILED ($violations). Fix the flagged files, then re-run this check."
else
  echo "VERIFY PASSED: no placeholders, dangling refs, or foreign idioms."
fi
```

On FAIL: fix the flagged rule/config files and re-run until PASS. On PASS: continue to summary.

### Cleanup

After the skill completes (success or failure), delete temp handoffs:
```bash
rm -f {target_project}/_install_config.json {target_project}/_codemap.md {target_project}/_install_manifest.json
```

## Step: Validate Prerequisites

1. Run the **Precheck: Global Layer Present** above. STOP if the global layer is missing.
2. Check GitHub CLI (for the `github` tracker default and `a_sk_pr`):

```bash
command -v gh >/dev/null 2>&1 && echo "GH_EXISTS" || echo "GH_MISSING"
gh auth status 2>&1 | grep -q "Logged in" && echo "GH_AUTHED" || echo "GH_NOT_AUTHED"
```

If `gh` is missing or unauthenticated, tell the user how to install/authenticate (`brew install gh`, then `gh auth login`) and continue (skills that need it warn at runtime).

3. Read the canonical framework version:

```bash
FRAMEWORK_VERSION=$(jq -r '.framework_version' "{framework_path}/config_hints.json")
echo "Framework version: $FRAMEWORK_VERSION"
```

## Step: Gather Project Configuration

Ask the user:

```
1. Project name?  (e.g., User Service, Products API)

2. Issue tracker?
   a) GitHub Issues (default, uses the gh CLI; the repo is the scope, no "spaces")
   b) Jira (Atlassian)
   c) Linear
   d) None (identifiers managed manually in prompts)
```

Store the tracker as `{ "type": "...", "url": "..." }`: `github` gives `{ "type": "github", "url": "" }` (default), `jira` gives `{ "type": "jira", "url": "your-org.atlassian.net" }`, `linear` gives `{ "type": "linear", "url": "" }`, `none` gives `{ "type": "none", "url": "" }`.

**Namespace.** For GitHub/Linear/None (no "spaces"), ask for a single namespace used as a ticket/branch prefix (e.g., SVC, API). For Jira, ask whether the team works across one or multiple Jira spaces. If multiple, collect each prefix + name; the first listed becomes `default_namespace`, and skills resolve the namespace from the ticket ID in the prompt at runtime.

**Standards location.** Ask where to place coding rules:

```
Where should I place coding rules?
  1. docs/ai-rules   (Recommended: AI/agent-specific, tool-agnostic)
  2. docs/coding-standards
  3. .cursor/rules   (keep Cursor location)
  4. .claude/rules   (keep Claude Code location)
  5. .aiRules        (hidden, tool-agnostic)
```

Store as `standards_location`.

Write everything gathered, plus `stack` and `applicable_rule_dirs` from **Stack Detection**, into `_install_config.json`.

## Step: Create Install Branch

Never commit the adoption on the repo's default branch (the global default-branch guard blocks it, and hidden install commits are a footgun).

```bash
default_branch=$(git -C {target_project} symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$default_branch" ] && default_branch="main"
current_branch=$(git -C {target_project} branch --show-current)
```

If `current_branch` is already a non-default branch, use it silently. If on the default branch, offer to create `feature/agentic-repos-setup` from latest default (recommended), a custom name, or continue on default at the user's explicit choice. Store `BRANCH_NAME` and `DEFAULT_BRANCH` for the summary.

A dedicated docs/tasks repo that commits directly to its default branch is out of scope for `ar-install`: use `ar-install-context` for the context/docs layer instead.

## Step: Handle CLAUDE.md and Existing AI Files

`CLAUDE.md` should contain ONLY `@AGENTS.md` and a notice. `AGENTS.md` is the single source of truth.

Scan for existing AI-instruction files that may carry useful context:

```bash
for f in CLAUDE.md .cursorrules .cursor/rules/README.md COPILOT.md \
         .github/copilot-instructions.md AI.md CONVENTIONS.md .windsurfrules; do
  [ -f "$f" ] && echo "FOUND: $f"
done
```

If any are found, offer to merge their content into `AGENTS.md`. Save the content for the Config Writer. If no `CLAUDE.md` exists and this is a greenfield adoption, optionally run `claude init` and save the generated content for merging.

Final `CLAUDE.md` content (all paths lead here):

```markdown
<!-- NOTE: Do NOT add content here. All project documentation, skills, agents,
     and guidelines belong in AGENTS.md. This file only tells Claude Code to load it. -->
@AGENTS.md
```

## Step: Greenfield Bootstrap (Optional)

Only for a true greenfield repo (no existing rules dir, no prior AI files, no `.claude/`). Otherwise skip.

Run `a_sag_codebase_explorer` even on greenfield to capture whatever structure exists, then let **Rule Extraction** author the initial `project-conventions.md` (and any evidenced rule files) from the real code. There is nothing project-specific to preserve, so extraction is the whole job.

## Step: Extract and Adapt Coding Rules

Follow **Rule Extraction (the heart of agent-ready)**:
1. Explore via `a_sag_codebase_explorer` to write `_codemap.md`.
2. Extract the repo's real conventions into `standards_location`.
3. Adapt the framework's universal + applicable stack rules on top, resolving every stack-specific element to the target's real values.
4. Gate `requires:` infrastructure-dependent rules by probing for the symbol.

Preserve any rules the project already had (custom rules, tuned thresholds): merge framework additions underneath, never overwrite project content. Append every written file to `_install_manifest.json`.

## Step: Create config_hints.json

Ask the platform (free-form; the exploration pass is authoritative when available):

```
What platform is this project? (e.g., Backend - Java Spring Boot, React web app, iOS, Android,
Python/FastAPI, Go/Gin, Ruby/Rails, or describe it)
```

### config_hints.json Schema

Single-namespace:

```json
{
  "_comment": "Project configuration for Agentic Repos. Safe to commit to git.",
  "project": {
    "namespace": "{namespace}",
    "name": "{project_name}",
    "tracker": { "type": "github", "url": "" }
  },
  "framework_version": "{FRAMEWORK_VERSION}",
  "platform": "{platform}",
  "standards_location": "{standards_location}",
  "stack": "{DETECTED_STACK}",
  "test_command": "",
  "lint_command": "",
  "build_command": "",
  "verify": { "full_command": "" }
}
```

Multi-namespace (Jira spaces): replace `project.namespace` with `default_namespace` + a `namespaces` array of `{ "prefix": "...", "name": "..." }`, and set `tracker.url`.

**Field notes.** `standards_location` is the runtime seam: `ar-*` skills read it from here to find the rules (there is no install-time rewrite of skill bodies). `stack` drives the language-safety check. `test_command`, `lint_command`, `build_command`, and `verify.full_command` make skills language-neutral; leave empty when detection is ambiguous (skills then detect from the repo at runtime), never hardcode a single project's command.

**Detect and persist a concrete `test_command` (best-effort, install AND upgrade).** Detection-driven only. Prefer a `Makefile test` target, else the language-native command for the detected tooling. Only write when the field is empty (never clobber a tuned value):

```bash
CONFIG=.claude/config_hints.json
detect_test_command() {
  if [ -f Makefile ] && grep -qE '^test:' Makefile; then echo "make test"; return; fi
  if [ -f build.gradle ] || [ -f build.gradle.kts ]; then [ -f gradlew ] && echo "./gradlew test" || echo "gradle test"; return; fi
  if [ -f pom.xml ]; then [ -f mvnw ] && echo "./mvnw test" || echo "mvn test"; return; fi
  if [ -f go.mod ]; then echo "go test ./..."; return; fi
  if [ -f Cargo.toml ]; then echo "cargo test"; return; fi
  if [ -f Gemfile ] && grep -qiE 'rspec' Gemfile; then echo "bundle exec rspec"; return; fi
  if [ -f Gemfile ]; then echo "bundle exec rake test"; return; fi
  if [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ]; then echo "pytest"; return; fi
  if [ -f package.json ] && jq -e '.scripts.test // empty' package.json >/dev/null 2>&1; then echo "npm test"; return; fi
  echo ""
}
TEST_CMD=$(detect_test_command)
if [ -n "$TEST_CMD" ] && [ -z "$(jq -r '.test_command // ""' "$CONFIG" 2>/dev/null)" ]; then
  tmp=$(mktemp); jq --arg c "$TEST_CMD" '.test_command = $c' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
  echo "Persisted test_command: $TEST_CMD"
fi
```

This file contains no absolute paths and is safe to commit; the whole team shares it.

## Step: Create AGENTS.md

`AGENTS.md` (repository documentation, single source of truth) is different from any `.claude/agents/` idea (there is none per repo; agents are global `a_sag_*`). Generate it from `_codemap.md` (build commands + structure) and `_install_manifest.json` (the rule list), merging any saved AI-file content.

**Scanner-compatibility rules (a rubric scanner treats any backtick-quoted text as a path/URL claim):**
1. Only backtick-quote real file/dir paths that exist in the repo.
2. Never put template variables inside backticks; resolve them first or use plain text.
3. Never backtick-quote naming patterns (write "PascalCase components", not the backticked form).
4. Never backtick-quote localhost/runtime URLs.
5. Package names (e.g. com.example.server) are plain text, not backticked.

Structure: project name + description, Quick Start (Setup/Build/Test/Run from the detected commands), Project Structure (modules, key directories, package layout), Documentation links, and an Agentic Repos section pointing at `standards_location` for the rules and naming the global workflow (`ar-taskflow` for real work, `ar-record-improvement` to capture friction). End with a footer line showing the installed `framework_version`.

## Step: Create .claude/skill.config

Per-repo paths and state that skills read (e.g. links to a paired tasks/docs workspace if any). Keep it minimal; only include paths that actually exist. Add `.claude/skill.config` and `.claude/settings.local.json` to `.gitignore` (see the .gitignore step).

## Step: Write Autonomous Settings

Write the target's `.claude/settings.json` from `{framework_path}/templates/settings.template.json`. This is an **autonomous permission posture**: `defaultMode: acceptEdits` plus an allow-list covering the git/build/PR/skill operations the flow performs, and NO "ask" list, so `ar-taskflow` and friends run end to end without stopping for permission prompts. Only genuinely destructive commands are denied.

**Permissions only, no hooks.** The SessionStart workflow hook and the default-branch / force-push guard are wired GLOBALLY by `install.sh` into `~/.claude/settings.json`. They already apply to this repo and must NOT be duplicated here. If the template ever carried a `hooks` block, strip it before writing.

**Merge, do not clobber.** If the target already has `.claude/settings.json`, union its permissions with the template rather than overwriting the team's existing entries:

```bash
TPL="{framework_path}/templates/settings.template.json"
DEST=".claude/settings.json"
mkdir -p .claude
if [ -f "$DEST" ]; then
  tmp=$(mktemp)
  jq -s '
    .[0] as $tpl | .[1] as $cur |
    $cur
    | .permissions.defaultMode = ($cur.permissions.defaultMode // $tpl.permissions.defaultMode)
    | .permissions.allow = (((($cur.permissions.allow // []) + ($tpl.permissions.allow // [])) | unique))
    | .permissions.deny  = (((($cur.permissions.deny  // []) + ($tpl.permissions.deny  // [])) | unique))
    | del(.hooks)
  ' "$TPL" "$DEST" > "$tmp" && mv "$tmp" "$DEST"
else
  jq 'del(.hooks)' "$TPL" > "$DEST"
fi
echo "Wrote autonomous permissions to $DEST (no hooks; global layer owns those)."
```

A project that wants non-autonomous behavior can add an `"ask"` array to this file afterward.

## Step: Setup Templates

**Core rule:** the framework NEVER installs PR or commit templates into `.claude/templates/`. Projects hold these at standard locations; a `.claude/` copy creates a duplicate source of truth that `a_sk_pr` and `a_sag_commit_writer` would have to disambiguate at runtime. The full scan-then-install flow runs only during `ar-install`; `ar-upgrade` never installs templates (it only deletes legacy `.claude/templates/` duplicates).

**PR template.** Scan standard locations; if found, keep it in place (`a_sk_pr` auto-detects it) and skip. If not found, offer the framework default at the repo root (`PULL_REQUEST_TEMPLATE.md`) or user-pasted content.

```bash
PR_TEMPLATE=""
for f in PULL_REQUEST_TEMPLATE.md .github/PULL_REQUEST_TEMPLATE.md .github/pull_request_template.md \
         .github/PULL_REQUEST_TEMPLATE/default.md docs/templates/pr-template.md; do
  [ -f "$f" ] && PR_TEMPLATE="$f" && break
done
# not found + user chooses default:
cp {framework_path}/templates/pr-template.md PULL_REQUEST_TEMPLATE.md
```

**Commit template.** Scan `docs/templates/commit-template.md`, `.gitmessage`, `.github/commit-template.md`, and `git config commit.template`. If found, keep it. If not and the user opts in, `cp {framework_path}/templates/commit-template.md docs/templates/`.

**Cleanup of legacy `.claude/templates/` duplicates (runs on both install and upgrade):**

```bash
for f in .claude/templates/pr-template.md .claude/templates/commit-template.md; do
  [ -f "$f" ] && rm "$f" && echo "Removed redundant duplicate: $f"
done
[ -d .claude/templates ] && rmdir .claude/templates 2>/dev/null
```

## Step: Generate ERD Documentation (Optional)

Only when a database layer is detected (migrations or entity definitions). Generate `docs/erd.md` with a Mermaid diagram, table definitions, relationships, and migration history from the actual migration/entity files. Skip entirely when no database is present. Append to `_install_manifest.json`.

## Step: Update .gitignore / .dockerignore

Add to `.gitignore`: `.claude/skill.config`, `.claude/settings.local.json`, and the temp handoff files (`_install_config.json`, `_codemap.md`, `_install_manifest.json`). If a `Dockerfile` exists, add the Agentic Repos config/rules files to `.dockerignore` so they do not bloat build context.

## Step: Verification

Run **Verification (Contamination + Reference Check)** above against the written rules, `AGENTS.md`, and `config_hints.json`. Fix and re-run until PASS before finalizing. This is the hard backstop against foreign-language noise and dangling rule references shipping into the repo.

## Step: Summary

Report what was written (config_hints.json, AGENTS.md, skill.config, settings.json, CLAUDE.md, the extracted + adapted rules with counts, any templates, ERD), the verification verdict, and the next steps:

```
Agentic Repos adopted for {project_name} (config + rules layer, v{FRAMEWORK_VERSION}).

- config_hints.json: identity, tracker, platform, standards_location, detected commands
- AGENTS.md: single source of truth
- .claude/skill.config: per-repo paths/state
- .claude/settings.json: autonomous permissions (no hooks; the global layer owns those)
- CLAUDE.md: points to @AGENTS.md
- {standards_location}/: {N} rules ({K} extracted from your code, {M} adapted framework rules)
- Verification: PASS

Next steps:
  1. ar-init-skills   (configure local paths, optional)
  2. ar-init-mcps     (issue-tracker integration: github verifies gh auth; jira/linear configure the MCP)
  3. ar-taskflow      (start your first task)
  4. Push the branch and open a PR:
       git -C {target_project} push -u origin {BRANCH_NAME}
       gh pr create --base {DEFAULT_BRANCH} --title "Adopt Agentic Repos v{FRAMEWORK_VERSION}"

The global procedure (ar-* skills, devkit agents, scripts, session hook, default-branch guard) is already on
this machine via install.sh. To refresh it later: (cd "$AR_FRAMEWORK_DIR" && git pull && ./install.sh).
```

Then run **Cleanup** to delete the temp handoff files.

## Project Configuration Reference

After adoption, skills read these from `.claude/config_hints.json` at runtime:
- **Ticket format:** `{namespace}-XXX`
- **Branch format:** `feature/{lowercase_namespace}-XXX-description`
- **Tracker:** `tracker.type` (`tracker.url` set for jira/linear)
- **Rules:** `standards_location`
- **Commands:** `test_command`, `lint_command`, `build_command`, `verify.full_command` (empty means detect at runtime)

## Versioning

See `VERSIONING.md`. The canonical version is `framework_version` in the framework root `config_hints.json`. It is mirrored to each target's `.claude/config_hints.json` at adoption and to the `AGENTS.md` footer.

## Refreshing an Adopted Project

`ar-upgrade` refreshes the local config + rules layer to the current framework version: re-run the applicable-rule adaptation, preserve project customizations (extracted rules, tuned thresholds, deliberate overrides), merge any new autonomous permissions into `.claude/settings.json`, bump `framework_version` in `config_hints.json` and the `AGENTS.md` footer, and run **Verification**. It never copies skills/agents, never installs scripts, and never writes hooks. To refresh the GLOBAL layer, it nudges the user to run `(cd "$AR_FRAMEWORK_DIR" && git pull && ./install.sh)`.
