---
name: ar-upgrade
description: Refresh an adopted project's per-repo config + rules layer to the current framework version. Say "ar-upgrade" or "refresh the project rules".
disable-model-invocation: true
---

# Refresh a Project's Config + Rules Layer

Bring an adopted repo's per-project **config + rules** layer up to the current framework version: re-adapt the applicable rules, refresh the framework-managed sections of `AGENTS.md`, merge any new autonomous permissions, bump `framework_version`, and re-verify. Preserve everything the team owns (extracted rules, tuned thresholds, deliberate overrides).

Like `ar-install`, this touches ONLY the local layer. It does NOT copy `ar-*` skills or devkit agents, does NOT install scripts, and does NOT write hooks. The GLOBAL procedure is refreshed separately (see Phase 4). There is no migration: this is a clean v1, with nothing to migrate from.

Follow `setup.md`, referenced below by section name.

## When to Use

- The project is adopted (`.claude/config_hints.json` exists with `framework_version`).
- The framework version is newer than the project's, or a drift check at the same version.
- If there is no `config_hints.json`, use `ar-install` instead.

**Bash rule:** run each command individually (no `&&`/`;`), absolute paths, no `cd` + relative.

## Phase 1: Detect Changes

### 1a. Precheck the global layer

Run `setup.md` -> **Precheck: Global Layer Present**. If missing, STOP and tell the user to run `./install.sh` from the framework root first.

### 1b. Ask for the target project

**Ask ONLY this single free-text question. No menu, no list, no suggested paths:**

```
What is the full path to your target project?
```

Validate the directory exists. Store as `TARGET_PROJECT`. If `{TARGET_PROJECT}/.claude/config_hints.json` is absent, tell the user to use `ar-install` instead and stop.

### 1c. Create the update branch

Follow `setup.md` -> **Step: Create Install Branch** (same logic; name it `feature/agentic-repos-update`). Store `BRANCH_NAME`, `DEFAULT_BRANCH`.

### 1d. Read versions and preserved config

```bash
FRAMEWORK_VERSION=$(jq -r '.framework_version' {FRAMEWORK_PATH}/config_hints.json)
PROJECT_VERSION=$(jq -r '.framework_version' {TARGET_PROJECT}/.claude/config_hints.json)
```

Read `standards_location`, `platform`, `stack`, and `namespace`/`namespaces` from the project's `config_hints.json`. These drive rule adaptation and are the values to preserve verbatim.

### 1e. Build the changed set

- **If `PROJECT_VERSION == FRAMEWORK_VERSION`:** run a drift check on the installed rules + `AGENTS.md` against the framework's current rule sources. If nothing is actionable, report "config + rules are up to date" and skip to Phase 4 (offer the global refresh). If drift is found, treat those rules as the changed set.
- **If `PROJECT_VERSION < FRAMEWORK_VERSION`:** read `CHANGELOG.md`, extract entries after `v{PROJECT_VERSION}`, and collect changed paths under `rules/`, the only per-repo installable layer.

**Ignore everything else in the changelog.** `skills/`, `agents/`, `scripts/`, `settings.json`, and `.claude/commands/` are the GLOBAL layer (refreshed by `install.sh`, not installed per repo). `templates/pr-template.md` / `templates/commit-template.md` are install-time only.

Map each changed rule path to the target, keeping only rule dirs applicable to the project's `stack`:
- `rules/universal/{name}` maps to `{standards_location}/{name}` (always)
- `rules/{stack}/{name}` maps to `{standards_location}/{name}` (only if `rules/{stack}/` exists and matches the project's `stack`)

### 1f. Present the plan

Show the user, file by file, what will be re-adapted and what will be preserved:

```
Project is at Agentic Repos v{PROJECT_VERSION}; framework is at v{FRAMEWORK_VERSION}.

Rules to refresh:
  - {standards_location}/{rule}: {what changed} -> ADD / UPDATE / DELETE

Preserved:
  - Rules extracted from your code, tuned thresholds, and override sections: kept; framework additions merged underneath
  - AGENTS.md: team-written sections untouched; only framework-managed sections refreshed
  - config_hints.json: only framework_version updated; all other fields verbatim
```

Ask a precise question only where the framework genuinely cannot decide (a tuned rule that also changed upstream: keep-and-merge vs replace vs review side by side; extra config fields to confirm keeping). Otherwise ask a single "Proceed?". If the user declines, stop.

## Phase 2: Apply Rule Changes

For each changed rule file, apply Smart-Merge. The defensive default is preserve:

- **PRESERVE:** project-specific values (packages, paths, namespaces), tuned thresholds, custom sections, override blocks, project examples, and any rule extracted from the repo's own code.
- **ADD:** new framework sections, guardrails, and examples the project lacks.
- **UPDATE:** framework bug fixes the target still has; the `framework_version` field.
- **NEVER:** replace project values with generic placeholders, touch rules the project extracted from its own code, or silently delete a project's custom section (escalate via the precise question in 1f).

Adapt every stack-specific element to the target's real values (read them from `config_hints.json`; for `project-structure.md`, detect the actual packages). Apply the `requires:` gate from `setup.md` -> **Rule Extraction** (do not introduce an infra-dependent rule whose symbol is absent; flag one already present whose symbol is now missing, without auto-removing it). Delete any rule listed under `**Removed:**` in the changelog if present in `{standards_location}`. Run the legacy-`.claude/templates/` cleanup from `setup.md` -> **Step: Setup Templates**.

## Phase 3: Finalize the Local Layer

1. `config_hints.json`: set `framework_version` to `FRAMEWORK_VERSION`; run the `test_command` best-effort detection (only-if-empty) from `setup.md` -> **Step: Create config_hints.json**. Leave every other field verbatim.
2. `.claude/settings.json`: run `setup.md` -> **Step: Write Autonomous Settings** in merge mode, so any new allow/deny entries from the current template land without clobbering the team's existing permissions. Still no hooks.
3. `AGENTS.md`: refresh only the framework-managed sections and the footer version.
4. Verify: run `setup.md` -> **Step: Verification** against the rules, `AGENTS.md`, and `config_hints.json`. Fix and re-run until PASS.
5. Redundancy sweep: if rule files changed in Phase 2, invoke `ar-optimizer` over `standards_location` to catch overlap introduced by the merge, then reconcile. Skip if no rules changed.
6. Commit: commit the changes on `BRANCH_NAME`. Do not push automatically; leave the push + PR to the user.

## Phase 4: Nudge the Global Refresh

The local layer is now current, but the machine's global procedure (the `ar-*` skills, devkit agents, scripts, session hook, guard) is refreshed independently. Tell the user:

```
Local config + rules refreshed to v{FRAMEWORK_VERSION}.

To refresh the GLOBAL layer on this machine (ar-* skills, devkit agents, scripts, session hook, default-branch guard):
  (cd "$AR_FRAMEWORK_DIR" && git pull && ./install.sh)

Then push and open a PR for this project:
  git -C {TARGET_PROJECT} push -u origin {BRANCH_NAME}
  gh pr create --base {DEFAULT_BRANCH} --title "Refresh Agentic Repos to v{FRAMEWORK_VERSION}"
```

## Phase 5: Summary and Cleanup

Report the rules changed/added/removed, any `requires:` flags, the verification verdict, and the version bump. Then run `setup.md` -> **Cleanup** to remove any temp handoff files.
