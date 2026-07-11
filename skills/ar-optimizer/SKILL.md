---
name: ar-optimizer
description: Audit and optimize a project's AI rule files. Detects redundancies, conflicts, staleness, example/rationale bloat, and fragmentation. Produces detailed reports and interactive cleanup recommendations. Say "ar-optimizer" or "optimize AI rules" to run.
disable-model-invocation: false
---

**Version:** 2.3.0

## Purpose

Audit and optimize a project's AI rule files. Identifies issues that **directly impact Claude's performance**, context bloat, ignored instructions, conflicts, based on official Claude Code documentation:
- [Best Practices](https://code.claude.com/docs/en/best-practices) | [How Claude Code Works](https://code.claude.com/docs/en/how-claude-code-works) | [Skills](https://code.claude.com/docs/en/skills)

## When to Run

- Post-setup validation or periodic maintenance (full project)
- After `ar-upgrade` to audit only the files that upgrade touched (scoped, see "Scoped Mode" below)
- Developer asks to optimize/audit AI rules
- New AI rules file added, or suspected conflicts/bloat

## Scoped Mode

When invoked by `ar-upgrade` (or any caller) with a fixed scope, the optimizer skips full-project discovery and audits ONLY the provided files. This is the **default behavior post-upgrade** because tuning that lives outside the upgrade's touched files is presumed-good and must not be disturbed.

### How scoped mode is triggered

Either:
1. The invoking skill/agent passes a list of files (one per line) on stdin under a `--scope` flag or via an explicit instruction in the prompt, OR
2. A `.claude/ar-optimizer.scope` file exists in the project root with a newline-separated file list (consumed and deleted by the optimizer).

When in scoped mode:
- **Skip Phase 1 (Discovery).** Use the provided file list as the discovery manifest. Mark its source in the report header (e.g., "Scope: ar-upgrade v6.3.0 → v6.4.0, 7 files").
- Run Phases 2-N (audit, conflict-detection, recommendations) only against the scoped files.
- When reporting findings that would normally suggest cross-project rewrites, **scope those suggestions to the provided files only**, do not recommend changes to files outside the scope.
- When asked about a redundancy that involves a file outside the scope, note it as "external, outside upgrade scope, deferred to next full audit" rather than acting on it.

### What scoped mode preserves

The whole point is to **not disturb tuning in untouched files**. If the optimizer would normally flag a redundancy that requires editing both an in-scope and out-of-scope file, prefer the in-scope edit and leave the out-of-scope file alone with a note.

Tell the user up front:

```
Scoped optimizer pass: {N} files (from {source}).
Files outside this scope will not be audited or changed in this run.
For a full-project audit, re-run `ar-optimizer` with no scope.
```

## Phase 1, Discover All Agent-Readiness rule files

> **Skip this phase in Scoped Mode.** Go straight to Phase 2 with the provided file list as the discovery manifest.

**MUST find ALL AI configuration files** across the entire project.

### Discovery Process

**1a. Search by known patterns:**
```bash
# Find all AI config files
find . -name "CLAUDE.md" -o -name "claude.md" -o -type d -name ".claude" \
       -o -name ".cursorrules" -o -path "*/.cursor/rules/*.mdc" \
       -o -name "AGENTS.md" -o -name "agents.md" -o -name "CODEX.md" \
       -o -name "AI.md" -o -name "RULES.md" -o -name "CODING_STANDARDS.md" \
       -o -name "CONVENTIONS.md" -o -name "GEMINI.md" -o -name ".windsurfrules" \
       -o -path "*/.github/copilot-instructions.md" \
       -o -path "*/.claude/skills/*/SKILL.md" -o -path "*/SKILLS/*.md" \
       -o -name ".aider*"
```

**1b. Search by content (catch custom locations):**
```bash
# Find markdown files with AI instruction phrases
find . -name "*.md" -exec grep -l -i "when working on this project\|AI assistant\|code style\|do not\|always use\|never commit" {} + 2>/dev/null
```

**1c. Check user-level config:**
```bash
ls -la ~/.claude/CLAUDE.md 2>/dev/null
```

**1d. Understand tech stack (for inferable-from-code detection):**
```bash
# Detect frameworks and build tools
grep -E '"(react|vue|angular|express|next)"' package.json 2>/dev/null
for f in build.gradle pom.xml Cargo.toml pyproject.toml; do [ -f "$f" ] && echo "$f"; done
```

**1e. Check for project configuration (if available):**
```bash
# Read project configuration if present
if [ -f .claude/config_hints.json ]; then
    STANDARDS_LOCATION=$(jq -r '.standards_location // ".cursor/rules"' .claude/config_hints.json)
    PLATFORM=$(jq -r '.platform // "unknown"' .claude/config_hints.json)
    echo "Standards location: $STANDARDS_LOCATION"
    echo "Platform: $PLATFORM"
fi
```

### Produce discovery manifest

Output format:
```markdown
## Discovery Results
**Files found:** {n}

### By Tool: Claude Code | Cursor | Generic | Skills | Custom
### Tech Stack: Languages | Frameworks | Build | Testing

| File | Lines | Est. Tokens | Status |
|------|-------|-------------|--------|
| CLAUDE.md | 250 | 1800 | ⚠️ Warning |
| **Total** | **595** | **4170** | ⚠️ High |
```

**If no files found:** Report "❌ No AI rule files found. Recommendation: Run /init to create CLAUDE.md"

## Phase 2, Parse & Categorize Each File

Read each discovered file and extract every instruction/rule. Tag into categories:

**Categories:** CODE_STYLE (formatting, naming, imports) | ARCHITECTURE (structure, patterns, boundaries) | TESTING (strategy, coverage, frameworks) | GIT (commits, branching, PRs) | TOOLING (build, CI/CD, setup) | BEHAVIOR (AI persona, tone, verbosity) | WORKFLOW (steps, checklists, verification) | PROJECT_CONTEXT (domain knowledge, business logic) | SAFETY (destructive action guards) | PERFORMANCE (optimization, limits) | SECURITY (auth, secrets, vulnerabilities) | OTHER

**Parsing checklist:**
1. Extract complete context (full rule, not summary)
2. Note location (file path, line numbers)
3. Detect emphasis (**IMPORTANT**, CRITICAL, ALL CAPS)
4. Count examples per rule
5. Track cross-references to other files/sections
6. Estimate tokens (~4 chars per token)

**Output format:**
```markdown
## Parsed Instructions
### CLAUDE.md (1800 tokens)
1. [CODE_STYLE, line 12] "Use 4-space indentation for TypeScript files"
2. [ARCHITECTURE, line 45-60, 3 examples] "Organize code by feature, not type" (420 tokens)
...
**Total instructions parsed:** 47 | **Unique concepts:** ~35 (12 duplicates detected)
```

## Phase 3, Detect Issues

Run 14 checks across ALL parsed instructions. Each issue type directly impacts Claude's performance.

### 3a. Redundancy (same idea, multiple locations)

**Detect:** Same semantic instruction in 2+ files or 2+ locations in one file.
**Example:** "Use 4-space indentation" appears in AGENTS.md:12, .cursorrules:5, CLAUDE.md:30
**Report:** `REDUNDANT, Indentation rule repeated 3× across 3 files`

### 3b. In-File Repetition (echo problem)

**Detect:** File restates its own point in different sections (AI-generated bloat pattern).
**Heuristics:** Same key phrase 2+ times in different sections | Numbered list defined once then re-listed | Paragraphs with >70% token overlap
**Report:** `ECHO, "{phrase}" appears {n} times in {file} at lines {lines}`

### 3c. Conflicts (contradictory instructions)

**Detect:** Two instructions oppose each other.
**Example:** AGENTS.md says "Always use named exports" but .cursorrules says "Prefer default exports"
**Report:** `CONFLICT, Export style: named (AGENTS.md:14) vs default (.cursorrules:8)`

### 3d. Staleness

**Detect:** References to deprecated packages/APIs, removed files/directories, outdated version numbers
**Report:** `STALE, Reference to {thing} which no longer exists`

### 3e. Example Bloat (multiple samples for one concept)

**Detect:** Rule illustrated with 2+ examples that teach the same thing (AI-generated over-explanation).
**Heuristics:** 2+ code blocks demonstrating same pattern | Multiple "good vs bad" pairs teaching identical lesson | Verbose before/after comparisons
**Example:** "Use early returns" has 4 examples all showing if/return pattern → 3 are redundant
**Report:** `EXAMPLE_BLOAT, "{rule}" has {n} examples in {file}, {n-1} can be removed`

### 3f. Fragmentation

**Detect:** Closely related instructions scattered across many files instead of co-located.
**Report:** `FRAGMENTED, {category} rules spread across {n} files: {list}`

### 3g. Inferable from Code (best practice violation)

**Detect:** Instructions describing things Claude can determine by reading code.
**Examples:** ❌ "Use React 18" (package.json) | ❌ "Express.js for API" (imports) | ❌ "PostgreSQL database" (config files) | ❌ "Tests are in test/" (folder structure)
**Report:** `INFERABLE, "{instruction}" can be determined from code (file: {file})`
**Best practice:** "Only include what Claude can't infer from code alone"

### 3h. Standard Conventions (unnecessary instructions)

**Detect:** Instructions describing standard language/framework conventions Claude already knows.
**Examples:** ❌ "Use camelCase for JS variables" | ❌ "Import React at top" | ❌ "Close database connections" | ❌ "Write clean code" | ❌ "Follow PEP 8"
**Report:** `STANDARD_CONVENTION, "{instruction}" is standard {language/framework} convention Claude already knows`
**Best practice:** Exclude "Standard language conventions" and "Self-evident practices"

### 3i. Embedded Documentation (should be links)

**Detect:** Long API docs, tutorials, or reference material embedded in rules files.
**Heuristics:** Code blocks >30 lines | Detailed API reference sections | Tutorial "how to" sections >50 lines | Content duplicating external docs
**Report:** `EMBEDDED_DOCS, {n} lines of documentation in {file} should be links to external docs`
**Best practice:** "Exclude detailed API documentation (link to docs instead)"

### 3j. Missing Emphasis on Critical Rules

**Detect:** Rules using "must", "never", "always", "critical" but lacking emphasis formatting.
**Examples:** ❌ "Never commit secrets to git" | ❌ "Always run tests before pushing" | ❌ "You must use git hooks"
**Report:** `MISSING_EMPHASIS, Critical rule "{rule}" in {file} lacks emphasis (IMPORTANT/WARNING/etc.)`
**Best practice:** "Add emphasis (e.g., 'IMPORTANT' or 'YOU MUST') to improve adherence"

### 3k. CLAUDE.md Size Warning

**Detect:** CLAUDE.md token count exceeds recommended size.
**Thresholds:** Warning: >2000 tokens | Critical: >4000 tokens
**Report:** `SIZE_WARNING, CLAUDE.md is {n} tokens ({percent}% of recommended max)`
**Why critical:** CLAUDE.md loads every session. Recommended max: 150 lines / 2000 tokens.

### 3l. Skills Without `disable-model-invocation`

**Detect:** Manually-invoked workflow skills lacking the `disable-model-invocation: true` flag.
**Heuristics:** Contains numbered steps | Has side effects (git, file writes, API calls) | Verb-based name (fix-*, deploy-*, run-*)
**Carve-out, do NOT flag mid-flow / conversational action skills.** A skill that the orchestrator (or the model mid-task) is expected to invoke programmatically must set `disable-model-invocation: false` on purpose, so model-invocability is correct, not a defect. Treat `false` as intentional for: skills the orchestrator hands off to during a run (`ar-record-improvement`, `ar-taskflow-review`, `ar-taskflow-fix-comments`) and conversational action skills the model should fire when the user asks (`a_sk_commit`, `a_sk_pr`). Only flag a `true`/missing flag on a skill that is genuinely user-only (setup/destructive/standalone, e.g. `aa-init-*`, `ar-install`, `ar-upgrade`).
**Report:** `MISSING_FLAG, Skill "{name}" appears to be a manually-invoked workflow but lacks 'disable-model-invocation: true'`
**Best practice:** "For skills you invoke manually, set `disable-model-invocation: true` to keep descriptions out of context until you need them; for skills meant to run mid-flow or fire on a conversational ask, set it `false` so the model can invoke them."

### 3m. Context-Heavy CLAUDE.md Imports

**Detect:** CLAUDE.md imports large files that should be skills instead.
**Heuristics:** `@path/to/file.md` syntax | Imported file >500 tokens | Contains domain knowledge or workflows (not project config)
**Report:** `HEAVY_IMPORT, CLAUDE.md imports {file} ({n} tokens). Consider converting to skill (loads on-demand) instead.`
**Why critical:** CLAUDE.md imports load every session. Skills only load when needed.

### 3n. Rationale Bloat (supporting prose in instruction files)

**Detect:** Skills/agents/rules carrying justification, history, or design-narration prose that doesn't change behavior. Instructions must say WHAT to do; WHY belongs in the CHANGELOG and commit history.
**Heuristics:**
- `## Why this exists` / `## Why this matters` / `**Why:**` / `**Why this asymmetry:**` / `**Rationale:**` sections or blocks explaining design choices
- Version-history markers inside the body: `(NEW in vX.Y.Z)`, `(vX.Y.Z change)`, `(vX.Y.Z fix)`, "previously was…", "the vX.Y.Z design…", "pre-vX.Y.Z…", meaningless inside an installed artifact (an install is always exactly one version)
- Framework-bug or design-history narration ("this was added because…", "this actually happened: …")
**Exempt:**
- One-line purpose statement at the top of a file (the description/`## Purpose` opener)
- Cost-flags that inform a user decision (e.g. `⏱ Cost: adds a sub-agent round-trip, opt-in`), these justify an opt-in default the user must choose, which IS behavior
**Report:** `RATIONALE_BLOAT, {file}:{lines} "{marker}", delete; relocate nothing (the CHANGELOG already records the why)`
**Fix:** delete the prose; if the rationale is genuinely undocumented, move it to the framework CHANGELOG entry, never keep it in the artifact body.

## Phase 4, Generate the Report

Output a structured report with:
- **Summary**, files scanned, total instructions, context window impact (CLAUDE.md tokens, heavy imports, missing flags, wasted context/session)
- **Critical Issues** (require decisions), conflicts, inferable-from-code, standard conventions, embedded docs
- **Quality Issues** (auto-fixable), redundancies, echoes, example bloat, rationale bloat, missing emphasis, stale, fragmentation
- **Impact Analysis**, token efficiency (current vs savings), performance risk (LOW/MEDIUM/HIGH)
- **Detailed Findings**, one table per issue type with file, line, description, severity

## Phase 5, Ask Developer Questions (**REQUIRED, Do Not Skip**)

**CRITICAL:** Present ALL findings and get explicit approval before ANY changes. **DO NOT proceed to Phase 6 until developer responds.**

For each issue, present:
- **Critical issues** (conflicts, inferable, conventions), multiple-choice fix options, developer picks
- **Quality issues** (redundancy, bloat, echoes), proposed fix with approve/reject per item

Developer can "apply all approved" or "skip".

## Phase 6, Propose a Fix Plan (only after answers)

After developer answers, produce concrete changeset:

```markdown
## Proposed Changes
**Deletions:** Remove `.cursorrules` line 5 (redundant indentation rule)
**Modifications:** AGENTS.md:14 change "named exports" → "{developer's choice}"
**Consolidations:** Move all CODE_STYLE rules → AGENTS.md § Code Style | Remove CODE_STYLE from CLAUDE.md, .cursorrules
**New Additions:** Add missing SAFETY rule to AGENTS.md: "{rule}"
```

Ask: `Shall I apply these changes? (yes / no / let me adjust)`

## Phase 7, Apply, Optimize & Verify

If confirmed:

**7a. Apply Changes** (in order):
1. Deletions (remove redundant sections)
2. Modifications (fix conflicts, add emphasis)
3. Consolidations (merge scattered rules)
4. New additions (add missing critical rules)

**7b. Optimize Files** - Apply compression rules to every affected file:
- One example per concept (pick clearest)
- Merge duplicate sections
- Remove restated preambles, filler phrases, repeated headings
- Strip rationale/history prose (Why-sections, `(NEW in vX.Y.Z)` markers, design narration), see check 3n; the CHANGELOG already records the why
- Tighten wording (concise imperative sentences over verbose paragraphs)
- Preserve every unique rule; only cut duplication
- Add emphasis (**IMPORTANT**, **CRITICAL**) to safety rules

**7c. Show Before/After**, per-file token table (before | after | reduction %)

**7d. Re-validate**, re-run Phases 2-4 to confirm zero conflicts, redundancies, bloat, and CLAUDE.md under 2000 tokens

**7e. Final Report**, issues resolved, files optimized/deleted, token reduction %, context impact (before → after tokens/session), next steps (test in new session, commit, run quarterly)

## Guiding Principles

### Determine Single Source of Truth

**FIRST:** Ask developer which file should be the single source of truth:
```
Multiple AI config files found. Which should be your single source of truth?
(a) AGENTS.md (conventional) | (b) CLAUDE.md (Claude Code) | (c) .cursorrules (Cursor) | (d) Other: ___
Recommendation: Choose file that's most complete, matches primary AI tool, easily imported by others.
```
Once determined, all consolidation recommendations use this file as target.

### Core Principles

- **Single source of truth**, one file owns core rules; others import or extend
- **Never delete without asking**, developer may have reasons for apparent redundancy
- **Preserve intent**, when merging phrasings, keep the more precise one
- **Tool-specific overrides OK**, must be explicitly marked, not silent contradictions
- **Less is more**, fewer tokens = stronger adherence. One example per concept.

### Consolidation Strategy

When consolidating:
1. **Keep in single source of truth** - Core rules in chosen main file
2. **Tool-specific files import** - Use `@path/to/main.md` syntax
3. **Overrides explicitly marked** - Example: `# .cursorrules` → `See @AGENTS.md for core rules.` → `## Cursor-specific overrides: [Override] Use inline completions (AGENTS.md says plan first)`
4. **Delete truly redundant files** - If only duplicates, delete entirely

### Edge Cases

- **No issues found**, report clean bill of health with token counts
- **CLAUDE.md >4000 tokens**, flag as CRITICAL; recommend moving domain knowledge and workflows to skills, linking external docs, removing inferable bloat
- **Tool-specific contradictions**, may be intentional; ask developer to mark as `[Override]`
- **Files in git**, note that team shares conventions; recommend committing optimization
