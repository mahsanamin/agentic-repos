---
name: ar-optimize-docs
description: Audit and lean out a project's documentation. Verifies every doc claim against the code, classifies each doc, removes what git or the code already carries, and installs a rule that stops re-bloat. Say "ar-optimize-docs", "audit the docs", or "the docs are stale" to run.
disable-model-invocation: true
---

**Version:** 1.0.0

## Purpose

Make a project's doc set smaller, correct, and hard to re-bloat. Docs accumulate by accretion: each session that debugs something writes down the whole investigation. The result drifts into being **wrong**, and a wrong doc is worse than a missing one because it gets trusted.

Reduce the doc set. Do not rewrite it in a tighter voice.

## Scope Boundary

**This skill owns doc files**: `README`, `docs/`, runbooks, ADRs, in-repo wiki pages, `CONTRIBUTING`. The boundary against the other four `ar-optimize*` skills is stated once, in `~/.claude/ar-framework-hints.md` → **Scope boundary**.

A finding about an instruction file belongs to `ar-optimizer`; record it as `external, deferred` and leave it alone. A finding about documentation belongs here even when an instruction file links to it.

**If the complaint is about comments in code, this is the wrong skill.** Someone whose actual problem is bloated blocks above their functions will reach for "optimize docs" and this skill will correctly find nothing. Say so and hand off: declaration-attached blocks are `ar-optimize-doc-comments`, comments inside a body are `ar-optimize-inline-comments`.

## When to Run

- Documentation is suspected stale, contradictory, or oversized
- Onboarding revealed a doc that misled someone
- Periodic maintenance, or after a release that moved structure
- Scoped to the docs a PR touched (see Scoped Mode)

**⏱ Cost:** Phase 1b reads code to confirm each claim and is the slowest part. On a large doc set, agree a scope in Phase 0 rather than skipping verification, an unverified pass produces a tighter voice and the same wrong facts.

## Scoped Mode

When a caller supplies a file list (on stdin under `--scope`, in the prompt, or via `.claude/ar-optimize-docs.scope`, consumed and deleted on read), skip Phase 1a discovery and treat that list as the inventory. Run every other phase unchanged.

State up front:

```
Scoped docs audit: {N} file(s) (from {source}).
Docs outside this scope are not audited or changed in this run.
```

A finding that needs an out-of-scope edit stays out of scope: record it as `external, deferred to next full audit` and leave the file alone.

## Phase 0, Understand the Target (**EDIT NOTHING**)

Determine from the repo, not by asking:

**0a. Who reads these docs.** Check `git log` authorship on doc paths, whether docs address a developer or an agent, and whether any doc reads as written for another team or a customer.

**0b. Existing intent.** Find a docs rule, standards directory, or contributor guide. Read it before overriding anything, **it wins on specifics.**

```bash
standards_dir=$(jq -r '.standards_location // "docs/ai-rules"' .claude/config_hints.json 2>/dev/null)
ls "$standards_dir" CONTRIBUTING.md docs/README.md 2>/dev/null
```

**0c. Generated vs hand-written.** Locate generators (schema files, API specs, doc generators, CLI help output). Hand-written prose that restates a generated source is a prime target.

**0d. Branching and review convention, and whether merging the default branch publishes anything.** Follow the project's flow; never invent one.

Then ask the user **only** what the repo cannot answer. Expect two:

1. Are any of these docs consumed outside this repo (linked from a wiki, an onboarding deck, another team's runbook)? Those must not be deleted without telling them.
2. Autonomy: propose-then-wait, or execute-and-report?

## Phase 1, Gather Evidence

### 1a. Inventory

List every doc with size, and read all of them. Note overlaps.

```bash
find . -name '*.md' -o -name '*.adoc' -o -name '*.rst' \
  | grep -vE '/(node_modules|vendor|build|target|dist|\.git)/' \
  | xargs wc -l | sort -rn
```

**Scan for secrets before anything else.** Docs are where credentials survive review: a reviewer checks whether an example command's flags are right, not whether its third positional argument is a real password. This is the highest-severity thing a documentation audit can find.

```bash
grep -rniE "(password|passwd|secret|token|api[_-]?key)[=: ]+['\"]?[A-Za-z0-9/+_-]{16,}" --include='*.md' .
grep -rniE '[a-z0-9-]+\.(amazonaws|azure|googleapis)\.com' --include='*.md' .
```

**`-i` is load-bearing.** The uppercase env-var form is what doc examples actually use, so a
case-sensitive scan misses `PASSWORD=`, `API_KEY=`, `TOKEN=` and `SECRET=` and finds only the
lowercase spellings. That is most of the real hits.

On a hit, **redacting the file is the smaller half**: the value is in git history and must be **rotated**. Never rewrite shared history to hide it. Report it as a finding that needs a named owner, replace the example with `$VAR` placeholders, and say plainly that the redaction alone does not fix it.

**Then grep for docs that admit their own staleness.** Someone knew, wrote it down, and moved on; the admission then reads as context rather than as a defect. Every hit is either a defect to fix or a line to delete.

```bash
grep -rniE "behind the code|out of date|not yet updated|may be stale|TODO|FIXME|needs updating" \
  --include='*.md' .
```

### 1b. Verify Every Claim Against the Code (**the centrepiece**)

This separates *verbose* from *defective*, and it is mechanical. For each doc:

- **Enumerations** (endpoints, env vars, tables, columns, modules, scripts, resources, templates), count the real ones and compare.
- **Named things** (paths, files, services, ports, versions, commands), confirm each still exists and still has that value.
- **Described behaviour**, find the code and confirm it.
- **Absence claims** ("not implemented", "planned", "disabled", "removed"), verify. These age worst and mislead hardest.

Produce the evidence table. **It is the mandate for every later phase**; a doc is not classified until it appears here.

```markdown
| Doc | Claim | What the code says | Verdict |
|-----|-------|--------------------|---------|
| README.md:22 | "exposes 3 endpoints" | 5 route handlers | WRONG |
| docs/setup.md:8 | "requires PORT env var" | read at config.ts:14 | OK |
| docs/api.md:40 | "batch import not built" | implemented at import.ts:9 | WRONG |
```

Report counts: claims checked, wrong, unverifiable. **Never carry a claim into a rewrite unchecked.**

### 1c. Find Load-Bearing References

Before restructuring anything, grep the **whole repo**, source, config, CI, scripts, not just docs, for references *into* the docs: file paths, numbered entries, anchors, section names.

```bash
grep -rnoE '(docs/[A-Za-z0-9_./-]+\.(md|adoc|rst))(#[A-Za-z0-9_-]+)?' \
  --exclude-dir={.git,node_modules,vendor,build,target,dist} . | sort -u
```

An identifier referenced from code or config **is an API**: keep it stable and compress around it. **Renumbering is never worth it.** Record every such identifier; Phase 4 verification re-checks each one.

### Then find the facts with more than one home

`lean-docs.md` says one fact, one owner. Nothing in this skill looked for violations of it, and that is the pattern that produces the most confidently wrong documentation, because when several copies agree, the agreement reads as corroboration and nobody re-checks any of them. They went stale together, in one change that updated none of them.

For each **specific value** a doc asserts (a TTL, a count, a limit, a port, a version, a "not supported yet"), grep the rest of the doc set for the same value or the same subject:

```bash
grep -rn "{the value or subject}" --include='*.md' . | grep -v "{the doc you found it in}"
```

**Two homes is a finding on its own, before you check which one is right.** Record the owner you will keep and make the others link to it. Real shapes this catches: one cache TTL documented in four places across three docs, every copy wrong the same way; one "feature not supported" claim in five places, wrong in all five because the feature shipped.

Absence claims duplicate the worst, because each copy makes the next reader more confident.

## Phase 2, Classify Every Doc

Every doc gets exactly one class, justified by a Phase 1b row.

| Class | Definition | Action |
|-------|------------|--------|
| **WRONG** | Contradicts the code | Fix or delete. Highest priority either way |
| **DUPLICATE** | A fact with two homes | Keep the more specific owner; the other links to it |
| **INVENTORY** | Transcribes what the code already names | Replace with a pointer to the source plus the command that lists the current answer |
| **HISTORY** | Change logs, migration narratives, "as of {date}", "previously X", resolved-incident writeups, tombstones | Delete. Git carries this better |
| **SPECULATIVE** | Documents what does not exist, planned features, payloads for unbuilt routes | Delete. It reads as shipped |
| **NAVIGATION** | Only points at other docs | Keep exactly one index; delete the rest |
| **LOAD-BEARING** | Carries what the code cannot | Keep |

A doc is LOAD-BEARING only if it carries at least one of:

- **WHY** a non-obvious decision was made, and what breaks if it is undone
- A **TRAP**, with how to detect it and what to do
- A **CROSS-CUTTING FLOW** no single file shows
- A **PROCEDURE** spanning tools (deploy, rotate, restore)
- **WHAT IS LIVE RIGHT NOW**, where the repo does not derive it

**DUPLICATE and useful are not mutually exclusive.** Flag any duplicative doc that may still be someone's daily reference rather than deleting it silently.

## Phase 3, Propose (**REQUIRED GATE**)

Report, and **change nothing until the user answers** unless Phase 0 agreed execute-and-report:

- The Phase 1b evidence table
- The classification, one row per doc
- Delete / merge / rewrite per doc
- Before/after size (files, lines)
- Anything you are **not confident about**
- Every doc flagged duplicative-but-possibly-load-bearing

## Phase 4, Execute

- **CUT, DON'T APPEND.** Prefer editing a paragraph to be correct *and* shorter over adding a correct one beside it.
- **Delete, don't tombstone.** No struck-through "resolved", no "kept for reference".
- **Present tense.** A date or ticket number survives only if it changes what the reader does.
- **Re-verify every number you KEEP**, not only the ones you change. Carrying a stale figure into a fresh rewrite launders it as newly checked.
- **Never delete the only record of a decision's rationale.** If it is buried in a doc being cut, move it, do not drop it.
- Follow the project's branching and PR convention exactly.

### Verify, and report the commands

```bash
# every relative link resolves
grep -rnoE '\]\(([^)#:]+\.md)(#[^)]*)?\)' --include='*.md' . \
  | sed -E 's/^([^:]+):[0-9]+:\]\(([^)#]+).*/\1 \2/' \
  | while read -r src tgt; do
      [ -e "$(dirname "$src")/$tgt" ] || echo "DANGLING: $src -> $tgt"
    done

# no dangling reference to anything deleted or renamed (source and config too)
grep -rn '{deleted-path}' --exclude-dir={.git,node_modules,build,target,dist} .
```

Confirm each explicitly:

- Every relative link resolves
- No dangling reference to a deleted or renamed doc, **in source and config as well as docs**
- Every load-bearing identifier from Phase 1c is still present
- The project's own build/test/lint gate passes, **say plainly if it could not run, and why**

## Phase 5, Stop the Regrowth (**do not skip**)

Without this the doc set grows back.

**5a. Get the rule in place, probe before you write.** Since v8.9.0 the framework ships this rule as `lean-docs.md` and `ar-install`/`ar-upgrade` install it into every target, so **on an installed project it is already there before this skill ever runs**. Authoring it again duplicates a file the framework owns, and the hand-written copy is overwritten on the next upgrade, the work is lost, and in the meantime the doc set is wrong about who owns its own standard.

```bash
standards_dir=$(jq -r '.standards_location // "docs/ai-rules"' .claude/config_hints.json 2>/dev/null || echo docs/ai-rules)
ls "$standards_dir"/lean-docs.md >/dev/null 2>&1 && echo PRESENT || echo ABSENT
# Who owns it: a rule listed in bootstrap_rules has diverged deliberately and ar-upgrade leaves it alone.
# Match on basename, bootstrap_rules holds bare filenames on some targets and full paths on others.
jq -r '[.bootstrap_rules[]? | sub("^.*/";"")] | if index("lean-docs.md") then "project-owned" else "framework-owned" end' \
  .claude/config_hints.json 2>/dev/null
```

| Probe says | What to do |
|------------|------------|
| **PRESENT** | **Do not rewrite it.** Confirm it still states the points below, report whether it is framework- or project-owned, then go straight to **5b**. 5b is the half that is genuinely per-project, and the half that is usually missing. |
| **PRESENT but contradicts the points below** | Report the divergence and who owns it. Edit it only if it is project-owned; if it is framework-owned the fix belongs upstream in `rules/universal/lean-docs.md`, so record it as `external, deferred` and leave the file alone. |
| **ABSENT**, a pre-v8.9.0 install, or a repo with no framework | **Write the rule** there. |

The rule must state:

- What earns a doc, the LOAD-BEARING list from Phase 2
- One fact, one owner
- Name the source, do not transcribe it
- Present tense, no change logs
- Delete, do not tombstone
- Cut, do not append

**5b. Wire it in**, or it is decoration:

| Wire | Where |
|------|-------|
| Each violation is a review finding | the project's code-review rule or checklist |
| The docs-update step enforces it | whatever skill or step syncs docs after a change |
| Contributors and agents are pointed at it | `AGENTS.md`, `CLAUDE.md`, or `CONTRIBUTING` |

**A wiring point that covers less than the doc set is not wired.** The docs-update step is the one that fails quietly: it typically names the handful of docs it was written against, so every doc added since drifts with nothing watching it. Check its coverage against the Phase 1a inventory, name the gap, and close it, and prefer pointing that step at the inventory over listing the files inside it a second time, or the list is a second home that goes stale on its own.

**Compute the gap, do not eyeball it.** This warning is easy to read past and agree with while the gap survives the run. Diff the two lists:

```bash
LC_ALL=C comm -23 \
  <(git ls-files '*.md' | grep -vE '/(node_modules|vendor|build)/' | LC_ALL=C sort) \
  <(grep -oE '[A-Za-z0-9_./-]+\.md' "{the docs-update mapping file}" | LC_ALL=C sort -u)
```

**`LC_ALL=C` must cover `comm` as well as both `sort`s.** The two have to agree on collation. BSD
`comm` honours the locale while GNU `comm` compares byte-wise, so locale-sorted input makes GNU
`comm` print `file 1 is not in sorted order` and emit garbage, and byte-sorted input fed to BSD
`comm` silently reports watched files as unwatched. Setting it once for the whole pipeline is the
only form that is right on both.

**Expand the mapping to concrete paths before diffing.** The `grep` above extracts literal `.md`
filenames, so a mapping that scopes by directory ("everything under `docs/`") yields nothing and the
diff then reports the entire inventory as unwatched. Resolve directory scopes to files first, or read
the output as candidates rather than findings.

Every line of output is a doc nothing watches. Expect the worst-drifted docs to be in that set: a mapping written for `docs/` typically leaves the root `README`, per-directory READMEs and any investigations folder uncovered, which is exactly where nobody looks.

## Final Report

State, per removal, **what was deleted and where that information lives now**, so the next reader can tell *removed as duplication* from *lost*.

```markdown
| Removed | Class | Information now lives |
|---------|-------|-----------------------|
| docs/migration-2024.md | HISTORY | git log |
| docs/endpoints.md | INVENTORY | route definitions; `{list-command}` |
| docs/index.md | NAVIGATION | README table |
```

Close with: docs before → after (files, lines), claims corrected, and the rule's location plus its wiring points.

## Edge Cases

- **No docs found**, report it; recommend a README only if the project has none.
- **A doc is wrong and nobody owns the correct answer**, do not guess. Delete the claim, or mark it unverified with the command that would settle it.
- **Generated output committed to the repo**, do not hand-edit. Fix the generator or the template.
- **A doc consumed outside the repo**, never delete on your own judgement; list it and ask.
- **The whole doc set is load-bearing**, report a clean bill of health with sizes. Finding little to cut is a valid outcome.
