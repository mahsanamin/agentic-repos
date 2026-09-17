---
alwaysApply: false
---
# Documentation Standards

What earns a place in this project's docs, and what does not. Applies to every doc outside the AI-instruction files (`AGENTS.md`, `CLAUDE.md`, and this rules directory), those are `ar-optimizer`'s scope.

A wrong doc is worse than a missing one, because it gets trusted.

This rule covers **doc files**, prose in `.md`, `.adoc`, `.rst`. Its two siblings cover in-source documentation: `lean-doc-comments.md` for declaration-attached blocks (Javadoc, docstrings, TSDoc) and `lean-inline-comments.md` for comments inside a body.

## What Earns a Doc

A doc earns its place only by carrying what the code cannot:

- **WHY** a non-obvious decision was made, and what breaks if it is undone
- A **TRAP**, with how to detect it and what to do
- A **CROSS-CUTTING FLOW** no single file shows
- A **PROCEDURE** spanning tools (deploy, rotate, restore)
- **WHAT IS LIVE RIGHT NOW**, where the repo does not derive it

Anything else is carried better by the code, by `git`, or by a generator.

## Rules

**One fact, one owner.** A fact lives in exactly one doc. Others link to it. Two homes means one drifts, and the reader cannot tell which.

> **Exempt:** a **generated** copy whose equality with its source is checkable on demand, a mirror, a lockfile, a rendered artifact. That is one owner plus a build product, not two homes. The exemption holds only while the check exists and runs; a generated copy nobody verifies is just a second home with better manners. Edit the source, never the copy.

**Name the source, don't transcribe it.** Do not enumerate endpoints, env vars, columns, modules, or scripts in prose, the list goes stale the next time someone adds one. Point at the source and give the command that lists the current answer.

**Present tense, no change logs.** No "as of {date}", no "previously X", no migration narratives, no resolved-incident writeups. `git log` does this better. A date or ticket number survives only if it changes what the reader does.

> **Exempt:** a changelog or migration file **read programmatically**, by an installer, upgrader, release tool, or dependency resolver, is an interface, not history. Keep it, keep its format, and keep its version identifiers stable. The exemption covers the consumed file only, not prose elsewhere that narrates the same changes.

**Delete, don't tombstone.** No struck-through "resolved", no "kept for reference", no commented-out sections. Removed means removed.

**Cut, don't append.** Fix the paragraph that is wrong. Never add a correct paragraph beside a wrong one, that is how a doc set doubles while getting less trustworthy.

**Don't document what does not exist.** No planned features, no payloads for unbuilt routes. Written down, they read as shipped.

**Re-verify numbers you keep.** Carrying a stale figure into a rewrite launders it as newly checked.

**Never delete the only record of a rationale.** If it is buried in a doc being cut, move it.

## Identifiers Referenced From Code Are an API

A doc path, numbered entry, or anchor referenced from source, config, CI, or a script must stay stable. Compress around it. Renumbering is never worth it.

```bash
grep -rnoE '(docs/[A-Za-z0-9_./-]+\.(md|adoc|rst))(#[A-Za-z0-9_-]+)?' \
  --exclude-dir={.git,node_modules,vendor,build,target,dist} .
```

## Audit

Run `ar-optimize-docs` to audit the doc set against these rules: it verifies each claim against the code, classifies every doc, and reports what to remove and where that information lives instead.
