---
alwaysApply: false
---
# Doc Comment Standards

Governs **doc comments**, the block attached to a declaration: Javadoc, KDoc, TSDoc/JSDoc, Python docstrings, XML doc comments, rustdoc, PHPDoc. In-body comments are `lean-inline-comments.md`. Prose files are `lean-docs.md`.

A doc comment is a **claim about a signature that sits next to that signature**. That makes it the one kind of documentation a machine can prove wrong, and the one kind that drifts silently, because nothing compiles it.

It is also read every time the declaration is. **The reader has the body.** A doc comment earns its lines only by carrying what reading the code will not tell you; everything else is a second copy of the implementation that rots on its own schedule.

## What Earns a Doc Comment

- **WHY** this exists, or why it is not the obvious implementation, and what breaks if someone "fixes" it
- A **CONTRACT** the signature cannot express: nullability, ordering, idempotency, units, ranges, thread-safety, transactional expectations
- A **TRAP** for the caller, and what to do instead
- A **SIDE EFFECT** that the name does not imply
- **Non-obvious lifecycle**: what must be called first, what invalidates the result
- **Which sibling to call instead**, when two near-identical declarations differ by audience or scope

Nothing else earns one.

## The Two Tests

Both are mechanical, and both exist because the qualitative list above cannot hold the line on its own: an author weighing their own comment can always answer yes.

**The name test.** If the declaration's name already states the contract, the block adds nothing: **delete it entirely**. `findAllByOperatorId(Integer operatorId)` needs no comment. This deletes most of an ORM repository's derived queries. Document one only when the query is **not** what the name implies.

**Proportionality.** A block longer than the code it documents must justify that with a reason from the list above. It is not automatically wrong (a three-line method can hide a real trap), but it is always a question to answer.

## Rules

**Never restate the signature.** `getName()` does not need "Gets the name". `@param id the id` documents nothing. Delete the tag rather than filling it. A partial tag set is correct.

**Never restate the body.** A numbered list walking through what the method does step by step is a second copy of the implementation sitting directly above it. It rots separately and is read twice. Delete it. If a sequence genuinely matters to a *caller*, meaning ordering or what must happen first, state that as a contract in one sentence, not as a transcript.

**Every documented name must exist.** A `@param` naming an argument the method does not take is a false claim. This is mechanically checkable, check it.

**No ticket IDs, no commit hashes, no author names.** `git log` and `git blame` carry these, and carry them correctly. A ticket number in a doc comment is a lookup the reader cannot perform from the call site and a claim nobody re-checks once the ticket closes. There is no "unless it matters" exception: if the ticket holds something the caller needs, put *that thing* in the comment.

One reference stays: **an ID that points outside this codebase**, meaning an upstream project's bug, a spec clause, or a vendor ticket. It is the authority that forced a non-obvious choice, and no `git blame` of this repo can supply it. The test is structural, not a judgement call: the tracker belongs to someone else. `lean-inline-comments.md` carves the same exception, plus one for `TODO` markers, which do not appear in doc comments.

**Keep the constraint, drop the journey.** "It used to be X, then we found Y, so now it is Z" is three facts where one is load-bearing. Document Z and why Z must stay. No "previously", "no longer", "was built to", "as of {date}".

**Never clone a doc comment.** Copying a block from a sibling declaration and not adapting it produces confidently wrong documentation. If two declarations genuinely share a contract, say so once and reference it.

**Do not contradict the code.** A comment claiming behaviour the annotations or body deny is a defect, not a style issue. When they disagree, the code is right and the comment is the bug.

**Document the contract, not the implementation.** An implementation detail in a doc comment becomes a lie the first time the implementation changes without the caller-visible behaviour changing.

**No essay headings.** If a block needs an `<h2>` it is too long. Compress it, or move it to a reference doc and link.

**Delete, don't tombstone.** No commented-out signatures, no "kept for reference".

**One block per declaration.** A second block stacked above an existing one is attached to nothing, because most languages bind only the block nearest the declaration. The orphan is invisible to the reference generator and sits above a *different* declaration than the one it describes, where it reads as documentation for that one. This is how a block that grew too long to edit becomes a block that is wrong.

## Never Lose a Why

Cutting is the default, with one exception that outranks it: **never delete the only record of a non-obvious decision.** If a block being shortened holds the sole rationale for something a future reader would otherwise "simplify" away, that rationale survives into the shorter block. When genuinely unsure whether a clause is load-bearing, keep it. Three surplus lines cost a little; a deleted why costs an outage.

## How to Compress

Keep the constraint, drop the narrative. Twenty lines of connection-pool archaeology becomes:

> Not transactional: the build fetches three images per applicant from object storage, so a
> transaction here holds a pooled connection across ~120 round trips for a large group and can
> starve the pool shared with the consumer flow. Validate before the lock.

That is the whole load-bearing content. Everything cut was how it was discovered.

## Generated API Reference Is an Interface

Where doc comments are published as API reference (javadoc, typedoc, sphinx, DocC), they are consumed outside the repo. Treat a published symbol's doc comment the way `lean-docs.md` treats an externally consumed doc: correct it freely, and flag rather than delete.

## Audit

Run `ar-optimize-doc-comments`. It verifies each documented name against the real signature, and auto-fixes only the class with exactly one correct answer.
