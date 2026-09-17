---
name: ar-optimize-doc-comments
description: Audit and repair a codebase's doc comments, the documentation blocks attached to a declaration. Verifies every documented name against the real signature, fixes provable signature drift, and proposes the rest. Say "ar-optimize-doc-comments", "audit the javadoc", or "the doc comments are stale" to run.
disable-model-invocation: true
---

**Version:** 1.0.0

## Purpose

A doc comment is a **claim about a signature that sits next to that signature**. Nothing compiles it, so it drifts silently, and because it drifts next to code that still works, it is trusted longer than prose ever would be.

That adjacency is also the leverage: unlike a prose doc, most of these claims are **mechanically falsifiable**. Verify them; do not read them for tone.

Two defects live here, not one. **Correctness**, where the claim is wrong, and **volume**, where the claim is true and still costs a read every time the declaration is read. A codebase whose doc comments are all true can still be 15% documentation nobody can afford to read, and a pass that only checks correctness will report it clean. Classify for both.

A useful side effect: compressing forces a read of every block in scope, which makes this the most reliable correctness audit a doc-comment set will ever get. Expect the sweep to surface wrong claims that no reviewer caught, because it is the only process that guarantees every block is actually read.

## Scope Boundary

**This skill owns the documentation block attached to a declaration**, whatever this project's language calls it and whatever its syntax is. Resolve that from the installed rules and the code you are reading, never from a list carried here. The boundary against the other four `ar-optimize*` skills is stated once, in `~/.claude/ar-framework-hints.md` → **Scope boundary**.

A finding outside this scope is recorded as `external, deferred` and left alone.

## When to Run

- Doc comments are suspected stale, cloned, or padding the file
- Before publishing API reference (javadoc, typedoc, sphinx, DocC)
- Scoped to the declarations a PR touched
- Periodic maintenance on a large codebase

**⏱ Cost:** Phase 2 parses every declaration in scope. On a large repository agree a scope in Phase 0, a module, a package, or the diff, rather than skipping verification. Phase 3's auto-fix is bounded to one defect class; everything else waits for a human.

## Phase 0, Scope and Ground Rules (**EDIT NOTHING**)

**0a. Find the rule.** `lean-doc-comments.md` states the contract and **wins on specifics**.

```bash
standards_dir=$(jq -r '.standards_location // "docs/ai-rules"' .claude/config_hints.json 2>/dev/null || echo docs/ai-rules)
ls "$standards_dir"/lean-doc-comments.md >/dev/null 2>&1 && echo PRESENT || echo ABSENT
```

**0b. Is the API reference published?** A generator config (`javadoc`, `typedoc.json`, `sphinx`, `.docc`) means these comments are consumed outside the repo. Correct freely; flag rather than delete.

**0c. Sizing, and what the number means.** Report the surface before proposing anything: declarations in scope, how many carry a doc comment, and doc-comment lines as a share of the whole.

Then act on that share rather than just printing it. **Above roughly 10% on a typical backend, volume is the finding** and the run is a bloat sweep: expect most blocks to be true and still worth cutting. Below it, drift is the finding and the classes in Phase 2's top half are where the value is. Also report the share of doc-comment lines sitting in a block that names a ticket or narrates history. That single number usually predicts how much of the set is transcription rather than documentation.

**0d. Branching convention**, and whether merging the default branch publishes the reference.

Then ask only what the repo cannot answer: the **scope** if it is large, and whether the published reference has consumers who must be told before a symbol's documentation changes shape.

## Phase 1, Parse, Don't Read

Build a table of `declaration → signature → doc comment` for the scope. Parse the language's real syntax; do not regex the first quoted string out of an annotation.

Two traps that produce confidently wrong findings:

- **An attribute is not a parameter.** An annotation or decorator carrying a content type, a route, an options object, or a default argument value will hand you a string literal that is not the thing you are extracting. Read the attribute you want **by name**, never "the first quoted string".
- **Nested delimiters break naive matching.** An annotation or decorator whose argument contains a closing bracket inside a string will truncate a `[^)]*` scan and silently shift every subsequent result. Match balanced.

**Verify your parser before you trust it.** Take a sample of declarations, check them by hand against the source, and only then report counts. A parser that is wrong produces findings that look mechanical and are fiction.

### Prioritise, or the report is unactionable

A large codebase has thousands of blocks and "agree a scope in Phase 0" is not enough guidance to pick one. Score and rank instead:

1. **Score every block.** `size >= 12 lines AND (names a ticket OR narrates history OR restates the body)` isolates the set where reading cost actually lands. On a 6,700-block codebase this selected under 600 blocks holding a quarter of all doc-comment lines.
2. **Rank files by targetable lines, not by block count.** Bloat concentrates: the top five files can hold a fifth of the targetable lines and the top forty about half, so a bounded pass captures most of the win and you can say exactly what you left.
3. **Fan out by file, never by block.** Two workers editing one file conflict, and the file is the unit where "does this still compile" is checkable.
4. **Say what the scoring dropped.** A bounded pass that does not name its own tail reads as complete coverage.

## Phase 2, Classify Each Doc Comment

| Class | Definition | Falsifiable? | Action |
|-------|------------|--------------|--------|
| **SIGNATURE DRIFT** | documents a name the declaration does not have, a `@param` for a vanished argument, a `@return` on a void, a documented `@throws` never thrown | **Yes, provably** | Phase 3 auto-fix |
| **CLONE DRIFT** | copied from a sibling declaration and never adapted; documents that sibling's parameters | Yes | propose |
| **CONTRADICTION** | asserts behaviour the code or annotations deny | Yes, by reading the code | propose |
| **TAUTOLOGY** | restates the signature: `@param id the id`, "Gets the name" on `getName()` | Yes, structurally | propose |
| **HISTORY** | "previously returned", "changed in v2", design archaeology: "it used to be X, then we found Y" | Yes | propose |
| **TICKET REFERENCE** | a ticket ID, commit hash or author name | Yes, structurally | propose in bulk (see Phase 3) |
| **BODY RESTATEMENT** | walks through what the method does step by step, typically a numbered list, directly above the body it restates | Yes, structurally | propose |
| **OVERSIZED** | longer than the code it documents, and carrying no why, trap, contract, side effect or lifecycle | Yes, by measuring | propose |
| **ORPHANED** | a second block stacked above another, bound to nothing, because most languages bind only the block nearest the declaration | **Yes, provably** | propose, with the re-attachment target named |
| **TOMBSTONE** | commented-out signature, "kept for reference" | Yes | propose |
| **LOAD-BEARING** | a why, a contract the signature cannot express, a trap, a side effect, non-obvious lifecycle | No | **keep** |

**Count clone drift separately from signature drift.** They look identical to a checker and differ completely in cause: one is a rename nobody followed, the other is a copy nobody read. The second predicts more of itself nearby, when you find one, check its siblings.

**BODY RESTATEMENT is not TAUTOLOGY.** Tautology restates the *signature* and is usually one line. Body restatement restates the *implementation*, runs to twenty lines or more, and has a different cause: an author documenting their own work as they write it rather than documenting a contract for a caller. Report them separately or the second hides inside the first's count.

**ORPHANED is where volume becomes incorrectness, so do not treat the two as independent problems.** When a block grows past the point anyone will edit it, the next author adds a new block above rather than rewriting. Only the nearest binds. Everything above it is invisible to the reference generator and sits above a *different* declaration, where a reader takes it as documentation for that one. Detect it by parsing for two blocks separated only by whitespace, and for prose appearing after the first block tag. Both are structural. Re-attachment needs judgement, so propose rather than auto-fix, but always name the declaration the orphan actually describes.

## Phase 3, Fix the Provable, Propose the Rest

**Auto-fix SIGNATURE DRIFT only.** It is the one class with exactly one correct answer: the signature is the truth, the tag is the error. Remove a tag naming an argument that does not exist; correct a name that was renamed when the correspondence is unambiguous. Never invent a description for a parameter that was never documented.

**Everything else is proposed, not applied.** Tautology, history and tombstones look safe to delete and are usually right to delete, but a comment can carry, in a throwaway clause, the only record of a why. `lean-doc-comments.md` and `lean-docs.md` both forbid dropping that.

**TICKET REFERENCE is proposed in bulk, per instance, and never by substitution.** A ticket ID is not a claim about behaviour, so removing it cannot make a comment wrong. That is the same "exactly one correct answer" property that justifies auto-fixing signature drift. What stops it being a regex is the shape: references appear as `(PROJ-1222)`, as a `PROJ-1125:` prefix, mid-sentence as "Since PROJ-1262 …", and as whole sentences like "Tracked as PROJ-1298." A blind substitution leaves ungrammatical text. Propose the whole class in one batch, rewritten per instance so each sentence still reads.

The failure mode to warn against explicitly is the opposite of over-caution: **the ticket usually sits inside a sentence that is load-bearing.** Strip the number, keep the sentence. Deleting the line because it names a ticket is the more common and more costly error.

### Compressing a block that is load-bearing *and* bloated

This is the case the classification does not resolve, and it is the common one on a mature codebase: cutting the block is wrong, keeping it is wrong. **Keep the constraint, drop the journey.** Re-tense to the present and see what survives.

Twenty lines of connection-pool archaeology, six ticket numbers and the history of two prior designs becomes:

> Not transactional: the build fetches three images per applicant from object storage, so a
> transaction here holds a pooled connection across ~120 round trips for a large group and can
> starve the pool shared with the consumer flow. Validate before the lock.

Everything cut was how it was discovered. Nothing load-bearing was lost. Where re-tensing leaves nothing, the block was pure archaeology and can go; where it leaves a sentence, that sentence is the block.

**Show this example to any sub-agent you fan out to.** One worked before/after does more for consistency across parallel workers than any amount of rule text.

Report before touching anything:

```markdown
| Declaration | Documented | Signature says | Class | Action |
|-------------|-----------|----------------|-------|--------|
| `Repo.deleteBeyond(exemptSource, horizon)` | `allowedCityNames`, `saudiCountryIso` | 2 params, neither named | CLONE DRIFT | propose |
| `Repo.collect(event)` | `otelCollector`, plus a `@return` | 1 param `event`, returns void | SIGNATURE DRIFT | auto-fix |
```

State counts per class, and state plainly how many declarations your parser could not parse, an unparsed declaration is not a clean one.

## Phase 4, Verify

- The project's build and doc-reference generation still succeed. A malformed doc comment can fail a `javadoc`/`typedoc` build even when the code compiles.
- Re-run Phase 1 and confirm zero SIGNATURE DRIFT remains.
- No `LOAD-BEARING` block lost a clause. Diff what you removed, not just what you kept.
- Say plainly if the reference generator could not be run, and why.

## Phase 5, Stop the Regrowth

**5a. Get the rule in place, probe before you write.** The framework ships this rule as `lean-doc-comments.md` and `ar-install`/`ar-upgrade` install it, so **on an installed project it is already there before this skill runs.** Writing it again duplicates a file the framework owns; the copy is reverted on the next upgrade, and until then the standard has no identifiable owner.

```bash
standards_dir=$(jq -r '.standards_location // "docs/ai-rules"' .claude/config_hints.json 2>/dev/null || echo docs/ai-rules)
ls "$standards_dir"/lean-doc-comments.md >/dev/null 2>&1 && echo PRESENT || echo ABSENT
jq -r '[.bootstrap_rules[]? | sub("^.*/";"")] | if index("lean-doc-comments.md") then "project-owned" else "framework-owned" end' \
  .claude/config_hints.json 2>/dev/null
```

| Probe says | What to do |
|------------|------------|
| **PRESENT** | **Do not rewrite it.** Confirm it still states the contract, report the owner, go to **5b**. |
| **PRESENT but contradicts the rule** | Report the divergence and the owner. Edit only if project-owned; if framework-owned the fix belongs upstream, record `external, deferred`. |
| **ABSENT** | Write it. |

**5b. Wire it in**, or the drift returns:

| Wire | Where |
|------|-------|
| Signature drift is a review finding | the project's code-review rule |
| The linter enforces what it can | the project's existing static analysis, where it has a doc-comment check |
| Contributors and agents are pointed at it | `AGENTS.md`, `CLAUDE.md`, or `CONTRIBUTING` |

**Prefer a gate over a rule where one exists.** This is the one documentation family a linter can police: most ecosystems ship a doc-comment check that catches signature drift at build time. A rule asks people to remember; a gate does not. If the project has such a check available and off, say so and propose enabling it, that closes the class permanently and makes this skill's next run boring.

## Final Report

Per class: how many found, how many fixed, how many proposed, how many declarations went unparsed. Then the surface before and after, and the one thing that would stop the class recurring.

## Edge Cases

- **Generated sources**, never edit. Fix the generator or template.
- **Overrides and interface implementations**, an inherited contract is documented once on the interface; a bare `{@inheritDoc}` or an empty override block is correct, not missing.
- **A convention-named declaration documents itself**: an ORM derived query, a generated builder, a plain getter. The name is the contract and the correct doc comment is none. This is the highest-yield deletion in a data-access layer, and it needs saying because "delete the whole block" otherwise feels out of bounds. Document one only when it does something its name does not imply.
- **Annotation and decorator strings are code, not comments**: a route description, a display name, a log message. Some are served to API consumers or are a test report's identifiers, so editing one is a behaviour-visible change. Leave them, and say so in the report rather than silently skipping them.
- **A published symbol**, correct the claim, flag any change to the shape of what consumers read.
- **A codebase with almost no doc comments**, report that and stop. Absence is not this skill's defect to fix; inventing doc comments to raise a number is.
