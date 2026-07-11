---
name: ar-install-context
description: Install or update context-processing skills (discussion, email, meeting, specs, state) into a Docs Project. Separate from ar-taskflow - does not touch ar-taskflow skills or config.
disable-model-invocation: true
---

# Install Context Skills

Install or update the context-processing command templates into a target Docs Project. This is the context/docs layer: separate from the code-repo config+rules layer that `ar-install` writes, and separate from the global procedure that `install.sh` links. This repo is the single source of truth for these templates: update them here, then push to all projects.

## What Gets Installed

| File | Target | On Update |
|------|--------|-----------|
| `context-collect-discussions.md` | `.claude/commands/` | **Always overwrite** |
| `context-collect-emails.md` | `.claude/commands/` | **Always overwrite** |
| `context-meeting-minutes.md` | `.claude/commands/` | **Always overwrite** |
| `context-update-specs.md` | `.claude/commands/` | **Skip if exists** (project-specific Document Registry) |
| `state-update.md` | `.claude/commands/` | **Skip if exists** (project-specific sections) |
| `document-formatting.md` | `.claude/rules/` | **Skip if exists** (may have project-specific rules) |

Templates are in `context-skills/templates/` with `{{BASE_PATH}}` and `{{ARCHIVE_PATH}}` placeholders.

## Process

### Step 1: Ask for target path

```
Which Docs Project should I install/update context skills in?
Provide the absolute path to the Docs Project directory.
Example: ~/repos/example/Example_Docs_Project
```

### Step 2: Derive paths

From the given docs project path, automatically determine:

1. **Repo root**, walk up from the docs project path until you find a `.git` directory:
   ```bash
   repo_root=$(cd "<docs_project_path>" && git rev-parse --show-toplevel)
   ```

2. **BASE_PATH**, relative path from repo root to docs project:
   ```bash
   base_path=$(python3 -c "import os; print(os.path.relpath('<docs_project_path>', '<repo_root>'))")
   ```

3. **Commands dir**, check both locations, use whichever has `.claude/commands/`:
   - `<docs_project_path>/.claude/commands/` (project-level)
   - `<repo_root>/.claude/commands/` (repo-level)
   - If neither exists, create at project level: `<docs_project_path>/.claude/commands/`

4. **Rules dir**, same logic as commands dir but for `.claude/rules/`.

5. **ARCHIVE_PATH**, scan repo root for a directory matching `*Archive*`:
   ```bash
   ls -d "$repo_root"/*Archive* 2>/dev/null
   ```
   - If found, use relative path from repo root.
   - If not found, derive from base_path: replace `DocsProject` or `Docs_Project` with `Archive` in the parent directory name. Create it.

6. **Show derived paths and ask for confirmation:**
   ```
   Derived configuration:
   - Repo root: <repo_root>
   - Base path: <base_path>
   - Commands dir: <commands_dir>
   - Rules dir: <rules_dir>
   - Archive path: <archive_path>

   Proceed? (y/n)
   ```

### Step 3: Install/update skills

Read each template from `context-skills/templates/`, replace `{{BASE_PATH}}` and `{{ARCHIVE_PATH}}` with derived values, and write to target.

```bash
framework_root="${AR_FRAMEWORK_DIR:-<path to agentic-repos>}"
templates="$framework_root/context-skills/templates"
```

**For each generic skill** (context-collect-discussions, context-collect-emails, context-meeting-minutes):
1. Read template from `$templates/<filename>`
2. Replace `{{BASE_PATH}}` with `$base_path` and `{{ARCHIVE_PATH}}` with `$archive_path`
3. Write to `$commands_dir/<filename>` (overwrite always)

**For each project-specific skill** (context-update-specs, state-update):
1. Check if `$commands_dir/<filename>` already exists
2. If exists: **skip** and note "preserved existing (project-specific content)"
3. If not exists: read template, replace placeholders, write to target

**For document-formatting.md rule:**
1. Check if `$rules_dir/document-formatting.md` exists
2. If exists: **skip** and note "preserved existing"
3. If not exists: copy template as-is (no placeholders to replace)

### Step 4: Ensure directory structure

Create the standard directories if they don't exist:
```bash
mkdir -p "$repo_root/$base_path/RawInformation/meetings"
mkdir -p "$repo_root/$base_path/RawInformation/emails"
mkdir -p "$repo_root/$base_path/Context/OnGoingKnowledeDiscussionSummary/OnGoingEmailsSummary"
mkdir -p "$repo_root/$base_path/ProjectStatus"
mkdir -p "$repo_root/$archive_path/OnGoingDiscussions/meetings"
mkdir -p "$repo_root/$archive_path/OnGoingDiscussions/emails"
```

### Step 5: Confirm

```
Context skills installed to <commands_dir>:
- context-collect-discussions.md, [installed / updated]
- context-collect-emails.md, [installed / updated]
- context-meeting-minutes.md, [installed / updated]
- context-update-specs.md, [installed / skipped (existing preserved)]
- state-update.md, [installed / skipped (existing preserved)]
- document-formatting.md, [installed / skipped (existing preserved)]

Directories created: [list any new dirs]
```

## Important

- This skill is **completely independent** of `ar-taskflow`. It does not read, modify, or depend on any `ar-taskflow` files, `skill.config`, or `config_hints.json`. It installs context command templates only. It never copies `ar-*` skills or devkit agents and never writes hooks (those belong to `install.sh`).
- The `context-update-specs.md` template has a placeholder Document Registry. After first install, the user must customize it with their project's actual document paths.
- To force-update a project-specific skill, delete the existing file first, then re-run this installer.
