---
name: ar-optimize-inline-comments
description: Audit a codebase's implementation comments, the ones inside a body. Finds commented-out code, stale TODOs, line-restating noise, and obsolete workaround notes, and proposes every removal for a human. Never deletes unattended. Say "ar-optimize-inline-comments" or "audit the code comments" to run.
disable-model-invocation: true
---

**Version:** 1.0.0

## Purpose

An implementation comment has **no signature to be checked against**, so nothing can prove it wrong. It is the least verifiable documentation in a repository and the most likely to outlive what it describes.

That cuts both ways, and the second way governs this skill: **deleting one can destroy the only record of a why, permanently.** There is no declaration to reconstruct it from. So this skill removes nothing on its own.

**The sub-case that catches people: a comment above a test explaining what regression it exists to catch reads exactly like history, and is not.** "Before this, a request the provider took over ten seconds on was stranded forever" is a why the assertion cannot express, and it is usually the most valuable comment in the file. A literal reading of "present tense, no narration" destroys it. Strip any ticket number, keep the sentence.

## Scope Boundary

**This skill owns comments inside a body.** The boundary against the other four `ar-optimize*` skills is stated once, in `~/.claude/ar-framework-hints.md` → **Scope boundary**.

A declaration-attached block is the sibling skill's, even when it sits two lines away. Record it as `external, deferred`.

## When to Run

- Commented-out code or stale `TODO`s are suspected
- Before a refactor, so the notes that matter are identified while there is still context
- Scoped to the files a PR touched

**⏱ Cost:** proposal-only, so the cost is review attention rather than wall clock. Do not run it repository-wide on a large codebase and hand over a thousand-line list, nobody reads that, and an unread proposal is the same as no audit. Agree a scope in Phase 0.

## Phase 0, Scope and Ground Rules (**EDIT NOTHING**)

**0a. Find the rule.** `lean-inline-comments.md` states the contract and **wins on specifics**.

**0b. Sizing.** Report comment lines as a share of the files in scope, so the proposal is judged against real weight rather than an impression.

**0c. Agree a scope.** A module, a package, or the diff. This skill's output is read by a person; scope it to what a person will act on.

**0d. Branching convention.**

Then ask the user for the scope if it is not obvious, and for anything the repo cannot answer.

## Phase 1, Collect, With Enough Context to Judge

For each comment in scope, record the file, the line, the comment, **and the code it sits above or beside**. A comment cannot be classified without the line it is commenting on, that is the whole difference between noise and a warning.

Skip: licence headers, generated files, vendored code, and declaration-attached blocks (the sibling skill's).

## Phase 2, Classify

| Class | Definition | Action |
|-------|------------|--------|
| **COMMENTED-OUT CODE** | disabled statements, an old implementation left in place | propose deletion, `git` has it |
| **STALE MARKER** | a `TODO`/`FIXME`/`XXX` naming closed work, a shipped release, or a departed owner | propose deletion or re-owning |
| **LINE-RESTATING** | says what the line does: `// increment the counter` | propose deletion |
| **OBSOLETE WORKAROUND** | "workaround for upstream bug X" where X is fixed | propose removing **note and workaround together** |
| **NARRATION** | "used to do X", dated notes, "as discussed" | propose deletion |
| **TICKET REFERENCE** | a ticket ID, commit hash or author name inside an otherwise fine comment. **Not** an ID inside a `TODO`/`FIXME`/`XXX` marker, and **not** an ID naming a tracker this team does not own | propose in bulk: **strip the reference, keep the sentence** |
| **DIRECTIVE** | read by a compiler, linter, or type checker, a suppression, a lint-disable, a pragma, a type hint, a build marker | **keep, this is code** |
| **LOAD-BEARING** | why this line is not the obvious one; a non-obvious consequence; the authority that forced the choice | **keep** |

**A directive is code whatever it looks like.** It is a comment in form only; something in the toolchain acts on it. Never propose one, and never argue it away as redundant with a neighbouring annotation, removing it is a behaviour change disguised as tidying.

**A stale marker is a claim, so verify it before calling it stale.** A `TODO` naming a ticket needs the ticket's state, not a guess from its age; an old comment describing a live problem is load-bearing. Never classify on date alone.

**An obsolete workaround is the one class where the comment is not the defect.** The workaround is. Removing the note alone leaves the workaround permanent and now unexplained, strictly worse than either doing nothing or removing both. If you cannot confirm the upstream fix, leave both and say so.

**TICKET REFERENCE is the one safe mechanical subset in this family, and it is the reason a proposal-only skill can still be worth running at scale.** A ticket ID is not a why: `git blame` carries it better and the reader cannot open the tracker from the call site. Removing it cannot lose information, which gives it the "exactly one correct answer" property the rest of this family lacks.

**Two references are out of scope, and skipping them is not optional.** An ID inside a `TODO`/`FIXME`/`XXX` marker is that marker's owner, and `lean-inline-comments.md` requires a marker to name live work; stripping it produces an unowned marker that this same skill then flags as a STALE MARKER, and destroys the input the staleness check needs. An ID naming an upstream project's bug, a spec clause or a vendor ticket is an *earner* under the same rule, because no `git blame` of this repo can supply it. Both tests are structural, so a run can apply them without judgement.

It is still not a regex. **The reference almost always sits inside a sentence that is load-bearing:**

```java
// PROJ-1267: the restricted-countries gate, and this is its authoritative point on this path.
```

Delete the line and a real constraint goes with it; strip the number and nothing is lost. Propose the class in one batch with a per-instance rewrite, and state the rule the way it has to be stated to work: **strip the number, keep the sentence.** Across parallel workers the failure mode is never keeping too much. It is dropping the line because it names a ticket.

**NARRATION has a sharp test: re-tense to the present and see what survives.** "This used to be transactional; that held a pooled connection across storage calls" becomes "Not transactional: that would hold a pooled connection across storage calls." Same trap, no history. Where re-tensing leaves nothing, the comment was pure archaeology and can go. Where it leaves a sentence, that sentence is the comment, so propose the rewrite rather than the deletion.

## Phase 3, Propose (**this skill's terminal state**)

Report, and **change nothing**:

```markdown
| File:line | Comment | Code it sits on | Class | Why it can go |
|-----------|---------|-----------------|-------|---------------|
| Svc.java:88 | `// retry 3x, API flakes` | the retry loop | LOAD-BEARING | keep, names the authority |
| Svc.java:140 | `// old impl` + 12 disabled lines | none | COMMENTED-OUT | git has it |
```

Then, per class: the count, the lines it would remove, and **every case you were unsure about, listed rather than resolved**. Uncertainty is the finding here, not a failure to reach one.

**Never present this as applied.** If the user asks for the edits, apply them in a separate, reviewable pass, and re-state the "only record of a why" check for each deletion before making it.

## Phase 4, Verify (only if edits were approved)

- The build and test suite still pass. A deletion inside a string, a heredoc, or a language where a pragma comment is semantic (a directive, a suppression, a type hint) changes behaviour.
- No DIRECTIVE left with the batch. A build that still passes does not prove it, a dropped suppression surfaces as a new warning, or as nothing at all until the next strict run.
- Diff what was removed and confirm no clause carrying a reason left with it.

## Phase 5, Stop the Regrowth

**5a. Probe before you write.** The framework ships `lean-inline-comments.md` and `ar-install`/`ar-upgrade` install it, so on an installed project it is already present. Do not author a second copy.

```bash
standards_dir=$(jq -r '.standards_location // "docs/ai-rules"' .claude/config_hints.json 2>/dev/null || echo docs/ai-rules)
ls "$standards_dir"/lean-inline-comments.md >/dev/null 2>&1 && echo PRESENT || echo ABSENT
jq -r '[.bootstrap_rules[]? | sub("^.*/";"")] | if index("lean-inline-comments.md") then "project-owned" else "framework-owned" end' \
  .claude/config_hints.json 2>/dev/null
```

PRESENT → confirm the contract, report the owner, go to 5b. ABSENT → write it. Framework-owned and diverging → `external, deferred`, fix upstream.

**5b. Wire it in:**

| Wire | Where |
|------|-------|
| Commented-out code is a review finding | the project's code-review rule |
| The linter catches what it can | most ecosystems can fail a build on commented-out code and on a marker without an owner |
| Contributors and agents are pointed at it | `AGENTS.md`, `CLAUDE.md`, or `CONTRIBUTING` |

**Commented-out code is the one class a gate can own outright.** Propose enabling that check rather than relying on review attention; it is the only class here with no judgment in it.

## Final Report

Per class: found, proposed, and the cases you could not decide. State the comment share before, and what it would be if every proposal were accepted, as an estimate, clearly labelled, since nothing was applied.

## Edge Cases

- **Generated, vendored, or minified files**, skip entirely.
- **A directive masquerading as a comment**, a suppression, a pragma, a type hint, a build marker. Code. Never propose it.
- **A comment inside a string or heredoc**, not a comment.
- **A codebase with few comments**, report it and stop. This skill does not add comments.
- **A large stale-marker backlog**, do not propose deleting them en masse. An owner and a date on the ten that matter beats deleting a hundred.
