---
alwaysApply: false
---
# Inline Comment Standards

Governs **implementation comments**, comments inside a body, explaining a line or a block. Declaration-attached blocks are `lean-doc-comments.md`. Prose files are `lean-docs.md`.

An inline comment has no signature to be checked against, so nothing can prove it wrong. It is the least verifiable documentation in the repository and the most likely to outlive what it describes. **Deleting one can destroy the only record of a why**, so this rule removes a narrow, provable set and leaves judgment to a human.

## What Earns an Inline Comment

- **WHY this line is not the obvious one**, the workaround, the ordering constraint, the deliberate inefficiency
- A **non-obvious consequence** of the surrounding code
- A **reference to the authority** that forced the choice: an upstream bug, a spec clause, a partner's undocumented behaviour

If the answer is "what this line does", delete it and let the code say it. If the code cannot say it, the fix is a clearer name, not a comment.

## Rules

**No commented-out code.** Ever. `git` remembers it and nobody trusts it. A block of disabled code is an unanswered question in the middle of a file.

**No line-restating comments.** `// increment the counter` above `counter++` is noise that survives every rename.

**A stale TODO is worse than no TODO.** A `TODO`/`FIXME` referencing closed work, a shipped release, or a person who has left teaches the next reader that TODOs here are decoration. Either it names live work, or it goes.

**An obsolete workaround note is a trap.** "Workaround for upstream bug X" outlives the upstream fix and stops the next person removing the workaround. When the note survives, verify the bug still exists; when it does not, remove note and workaround together.

**A directive is not a comment.** `// noinspection`, `// CHECKSTYLE:OFF`, a pragma, a type hint, anything the toolchain reads is code wearing comment syntax. It is exempt from every rule above, including when a neighbouring annotation makes it look redundant.

**Present tense, no narration.** No "used to do X", no dated notes, no "as discussed".

**No ticket IDs, with two structural exceptions.** The reason is the same as in
`lean-doc-comments.md`: `git blame` carries the ticket correctly, the reader cannot open the tracker
from the call site, and nobody re-checks the reference once the ticket closes.
`// PROJ-1234: the restricted-countries gate` loses nothing by becoming
`// The restricted-countries gate`.

Two references stay, because another rule in this file already requires them:

- **The ID inside a `TODO`/`FIXME`/`XXX` marker.** "A stale TODO is worse than no TODO" above needs
  the marker to name live work, and the ID is what makes that checkable. Strip it and you get an
  unowned marker, which `code-review.md` flags in its own right.
- **An ID that points outside this codebase**: an upstream project's bug, a spec clause, a vendor
  ticket. "A reference to the authority that forced the choice" is listed above as something that
  *earns* a comment, and no `git blame` of this repo can supply it.

Both exceptions are **structural, not a judgement call**: either the reference sits inside a marker
keyword, or it names a tracker this team does not own. That is what keeps them from becoming the
"unless the ticket matters" escape hatch this rule removed, which every author can talk themselves
past.

The trap specific to inline comments is that the ticket usually sits inside a sentence that *is*
load-bearing. **Strip the number, keep the sentence.** Deleting the whole line because it names a
ticket is the mistake this rule most often causes, and it is the one that loses information.

## Never Delete the Only Record of a Why

Removing an inline comment is the one edit in this family that can lose information permanently, because there is no signature to reconstruct it from. Before deleting any comment that carries a reason, confirm the reason is recorded elsewhere, a doc comment, a rule, a commit message you can name. If it is not, **move it, do not drop it**.

## Audit

Run `ar-optimize-inline-comments`. It proposes and never auto-deletes: every finding in this file needs a human who knows why the line is there.
