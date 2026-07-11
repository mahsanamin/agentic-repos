---
name: ar-install
description: Adopt Agentic Repos in a project, writing its per-repo config + rules layer by extracting the codebase's real conventions. Say "ar-install" or "make this repo agent-ready".
disable-model-invocation: true
---

# Adopt Agentic Repos in a Project

Make a repo agent-ready by writing ONLY its per-project **config + rules** layer: `config_hints.json`, `AGENTS.md`, `.claude/skill.config`, an autonomous `.claude/settings.json` (permissions only), coding rules **extracted from the actual codebase** into `standards_location`, and PR/commit templates.

This command does NOT install the global procedure. The `ar-*` skills, the devkit agents (`a_sag_*`) and atomic skills (`a_sk_*`), the worktree helpers (`a_g_worktree_*`), the framework scripts, the SessionStart hook, and the default-branch guard are all installed once per machine by `install.sh`. This command reads that global layer. It never copies skills/agents into the target, never installs scripts, and never writes hooks (the global session hook and default-branch guard already cover every repo).

Follow `setup.md`, referenced below by section name.

## When to Use

- A repo has never been adopted (no `.claude/config_hints.json`).
- If `config_hints.json` already exists, use `ar-upgrade` instead.

## What This Does

1. Precheck: confirm the global layer is installed.
2. Validate & gather: prerequisites, target path, identity/tracker/standards config, written to `_install_config.json`.
3. Branch: create a dedicated install branch.
4. Explore & extract: map the codebase, extract its real conventions into `standards_location`, adapt framework rules on top.
5. Config: write `config_hints.json`, `AGENTS.md`, `.claude/skill.config`, `.claude/settings.json`, `CLAUDE.md`, templates, optional ERD.
6. Verify: contamination + reference check in a fresh context.
7. Summary: report, then clean up temp files.

All agents communicate through files on disk (`_install_config.json`, `_codemap.md`, `_install_manifest.json`), not conversation context.

**Bash rule:** run each command individually (no `&&`/`;` chaining), use absolute paths, no `cd` + relative.

## Phase 1: Precheck, Validate, Gather

### 1a. Precheck the global layer

Run `setup.md` -> **Precheck: Global Layer Present**. If the `ar-*` skills or agentic-devkit are missing, STOP and tell the user to run `./install.sh` from the framework root first. Do not install the global layer from here.

### 1b. Ask for the target project

**Ask ONLY this single free-text question. No menu, no numbered list, no suggested paths:**

```
What is the full path to your target project?
```

Validate the directory exists. Store as `TARGET_PROJECT`. Then check whether it is already adopted:

```bash
ls {TARGET_PROJECT}/.claude/config_hints.json 2>/dev/null
```

If it exists, tell the user this project is already adopted and to use `ar-upgrade` instead. Stop here.

### 1c. Create the install branch

Follow `setup.md` -> **Step: Create Install Branch**. Store `BRANCH_NAME` and `DEFAULT_BRANCH` for the summary.

### 1d. Validate prerequisites

Follow `setup.md` -> **Step: Validate Prerequisites** (gh check, read the canonical `FRAMEWORK_VERSION`).

### 1e. Gather configuration

Follow `setup.md` -> **Step: Gather Project Configuration** (project name, tracker, namespace(s), `standards_location`) and -> **Stack Detection (Positive Evidence)** for `stack` + `applicable_rule_dirs`.

### 1f. Handle existing AI files

Follow `setup.md` -> **Step: Handle CLAUDE.md and Existing AI Files**. Save any merge-worthy content for the Config Writer.

### 1g. Write the handoff config

Write `_install_config.json` to the target root with everything gathered (target/framework paths, project name, tracker, namespace(s), `standards_location`, `stack`, `applicable_rule_dirs`, saved AI content, `mode: "fresh"`, `framework_version`). Schema in `setup.md` -> **File-Based Handoffs**. Present the detected stack + applicable rules and continue.

## Phase 2: Greenfield Bootstrap (Optional)

Only for a true greenfield repo (no existing rules dir, no prior AI files, no `.claude/`). Follow `setup.md` -> **Step: Greenfield Bootstrap**. Skip otherwise.

## Phase 3: Explore and Extract Rules (the core)

This is what makes the repo agent-ready. Follow `setup.md` -> **Rule Extraction (the heart of agent-ready)** and **Step: Extract and Adapt Coding Rules**:

1. Launch `a_sag_codebase_explorer` (Task) with the target path + `_install_config.json`, which writes `_codemap.md`.
2. Extract the repo's real conventions into `standards_location` (cite real files, use the project's own idioms). Do not merely copy generic templates.
3. Adapt the framework's universal + applicable stack rules on top, resolving every stack-specific element to the target's real values. Gate `requires:` rules by probing for the symbol.

Append every written rule file to `_install_manifest.json`.

## Phase 4: Write Config, Settings, Templates, ERD

Run the **Config Writer** (`setup.md` -> **Config Writer**), then settings, templates, and optional ERD:

1. `config_hints.json`: `setup.md` -> **Step: Create config_hints.json** (schema + `test_command` detection).
2. `AGENTS.md`: `setup.md` -> **Step: Create AGENTS.md** (scanner-compat rules; build commands + structure from `_codemap.md`, rule list from `_install_manifest.json`).
3. `.claude/skill.config`: `setup.md` -> **Step: Create .claude/skill.config**.
4. `.claude/settings.json`: `setup.md` -> **Step: Write Autonomous Settings** (autonomous permissions from the template, merged not clobbered; no hooks, the global layer owns those).
5. `CLAUDE.md`: the standard `@AGENTS.md` pointer.
6. Templates: `setup.md` -> **Step: Setup Templates**.
7. ERD (only if a database is detected): `setup.md` -> **Step: Generate ERD Documentation**.
8. `.gitignore` / `.dockerignore`: `setup.md` -> **Step: Update .gitignore / .dockerignore**.

## Phase 5: Verify

### 5a. Contamination + reference check
Follow `setup.md` -> **Step: Verification** (contamination + reference check, fresh context, re-detect stack independently). Fix flagged files and re-run until PASS.

### 5b. Redundancy sweep
Extraction plus merging framework rules under any pre-existing project rules can leave overlap. Invoke `ar-optimizer` over `standards_location` to catch redundant or duplicated rules, `alwaysApply` overuse, and stale cross-references, then reconcile its findings. This is the same sweep `ar-agent-ready` runs, so adoption leaves no duplicated rules behind.

## Phase 6: Summary and Cleanup

Follow `setup.md` -> **Step: Summary** to report what was written, the verification verdict, and next steps (`ar-init-skills`, `ar-init-mcps`, `ar-taskflow`, push + PR). Then run `setup.md` -> **Cleanup** to delete the temp handoff files.
