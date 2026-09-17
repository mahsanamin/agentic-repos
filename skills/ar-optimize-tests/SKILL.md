---
name: ar-optimize-tests
description: Audit a project's test suite for cost. Reads per-class time from the result files the runner already wrote, classifies every test class by the layer it actually runs at, reports what is paying for a framework it does not need and what no pipeline runs at all, then applies only the mechanical fixes and stages the rest behind a coverage-preserving invariant. Say "ar-optimize-tests", "audit the test suite", or "the test suite is slow" to run.
disable-model-invocation: true
---

**Version:** 1.0.0

## Purpose

Make a suite cost less without proving less.

Two facts make that tractable. **The cost is already written down**, the runner emitted a per-class result file on its last run, so cost is read, not estimated. And **the layer a test runs at is derivable from its own markers**, so the classification needs no list anyone has to maintain.

The defect is almost never that a test exists. It is that a test which needs no framework pays for a whole application, because the neighbouring test did and copying it was the path of least resistance. Nothing in a green suite reports that.

**Reduce what the suite costs. Never reduce what it covers.**

## Scope Boundary

**This skill owns test sources**: which layer each class runs at, what it costs, and whether any pipeline runs it. The boundary against the other four `ar-optimize*` skills is stated once, in `~/.claude/ar-framework-hints.md` → **Scope boundary**.

A finding outside this scope is recorded as `external, deferred` and left alone.

Three installed rules divide the same subject, and this skill owns exactly one question:

| Rule | Question |
|------|----------|
| `test-change-policy.md` | **when** a test may change |
| `test-scope-policy.md` | **what** a test asserts |
| `test-layer-policy.md` | **which layer** it runs at, this skill's subject |

This skill does not re-decide what a test asserts. It decides what a test should have to boot in order to assert it.

The line runs through duplication, so draw it explicitly rather than deferring the whole subject:

| Duplication | Whose |
|-------------|-------|
| the same behaviour proven twice **at two different layers**, once cheaply, once by booting an application | **in lane.** It is a cost finding, and W2 reports it |
| two tests asserting the same behaviour at the **same** layer | `test-scope-policy.md`, `external, deferred` |

Four defect classes are commonly found alongside this skill's work and are **not** its own. Name them in the report so the deferral is auditable rather than a catch-all: assertions that only verify a mocked internal collaborator; assertions of a framework guarantee; coupling to an exact log string; and coupling to call order or exact call counts. Each is a `test-scope-policy.md` finding.

## When to Run

- The suite or the pipeline is slow, and nobody can say which classes are responsible
- Before adding a module that will lengthen it
- Periodic maintenance, or after a release that moved structure
- Scoped to one module, or to the classes a PR touched (see Scoped Mode)

**⏱ Cost.** The two halves are not comparable, and the split is the point:

| Half | Cost | Default |
|------|------|---------|
| Phases 0-3, measure, classify, report | reads files the runner already wrote and parses test sources. **No suite re-run, no network.** Minutes | safe to run anywhere |
| Phase 4, apply | one mechanical concern is a small diff. One semantic concern on a large suite is a **large agentic job** | **opt-in per concern, never one button**, on either side |

Never present Phase 4 as a single approval. Every concern is selected, applied and reverted on its own, and each one's cost is stated before it is offered.

## Scoped Mode

When a caller supplies a file or module list (on stdin under `--scope`, in the prompt, or via `.claude/ar-optimize-tests.scope`, consumed and deleted on read), skip Phase 1a discovery and treat that list as the inventory. Run every other phase unchanged.

State up front:

```text
Scoped test audit: {N} class(es) / {M} module(s) (from {source}).
Classes outside this scope are not audited or changed in this run.
```

Two numbers stay repository-wide even in scoped mode, because a scoped denominator makes them meaningless: the **per-module totals** a scoped class's time is a share of, and the **distinct heavyweight context count**, which is a property of the whole run. Report both as repository-wide and say so.

## Phase 0, Understand the Target (**EDIT NOTHING**)

**0a. Resolve the seam.** Stack specifics come from the project, never from this skill.

```bash
cfg=.claude/config_hints.json
jq -r '.test_layers // "ABSENT"' "$cfg" 2>/dev/null
jq -r '.verify | {full_command, targeted_command, always_full_paths, comment_only_skip}' "$cfg" 2>/dev/null
standards_dir=$(jq -r '.standards_location // "docs/ai-rules"' "$cfg" 2>/dev/null || echo docs/ai-rules)
```

The `test_layers` block is the stack seam, and it mirrors how `verify.full_command` already works, the procedure is generic, the values are the target's:

```json
{
  "test_layers": {
    "source_globs":         ["<glob per test source set>"],
    "result_glob":          "<glob for the runner's per-class result files>",
    "test_markers":         ["<what makes a method an executable test>"],
    "assertion_markers":    ["<what counts as an assertion>"],
    "non_test_markers":     ["<what marks a file in the test tree as support, not a test>"],
    "markers": {
      "rung_2_sliced":        { "any_of": ["<marker>"] },
      "rung_3_real_database": { "any_of": ["<marker>"] },
      "rung_4_full_context":  { "any_of": ["<marker>"] },
      "substitute":           { "any_of": ["<marker>"] }
    },
    "web_surface_markers":  ["<what shows a class drives only the request surface>"],
    "context_key_markers":  ["<marker whose value set distinguishes one heavyweight context from another>"],
    "cache_defeating_flags":["<flag that forces a full rerun>"],
    "baseline_path":        "<where the dated baseline is written>"
  }
}
```

**Precedence, in order: the seam block, then the installed stack rule, then detection from the repository.** Report which one supplied each value.

**No default marker map ships with this skill.** A marker list is stack knowledge, and stack knowledge belongs in the project, a default table here would be wrong for most targets while looking authoritative on all of them.

So when none of the three sources yields a map, the answer is a procedure, not a table:

1. **Derive a candidate map** from the target's own test sources and installed rules, cluster the markers that actually appear, and rank them by how much each one costs in the result files.
2. **Report the seam `UNCONFIGURED`** and show the derived map, naming the evidence for each marker.
3. **Withhold every phase that depends on it**, the Phase 2 census, the necessity pass, all six views, and all of Phase 4, and say which are withheld.
4. **Check the derived order against the rule's ladder, not just the derived terms**, see Phase 2's third trap. A map read off a target's own testing guide can correspond term-for-term while running in a different direction at the top.
5. **Proceed only once the map is confirmed**, and offer it as the `test_layers` block so the next run does not repeat this.

A guessed map produces a confident census of the wrong thing, and every later phase inherits it silently.

**0b. Find the rules.** The three above, in `{standards_dir}`. **They win on specifics**, read them before contradicting anything, and note which are present.

**0c. Locate the result files** the runner already wrote, and their timestamp. Absent or stale changes what Phase 1 can claim.

**0d. Read what each pipeline job actually selects**, not the default command. A suite is commonly larger than any one job runs: a tag excluded for every module, a module gated to run only when named, a module disabled outright. Enumerate every job and the selection it applies.

**0e. Branching and review convention.** Follow the project's; never invent one.

Then ask the user **only** what the repo cannot answer. Expect three:

1. The **scope**, if the suite is large.
2. **Autonomy:** propose-then-wait, or execute-and-report. Phase 4's semantic side is never covered by either answer.
3. Whether a staged rewrite needs a ticket before anyone starts it.

## Phase 1, Measure

### 1a. Inventory

Every test class per module and per source set, with its file size. Count separately, and report separately, the files in the test tree that carry markers but contain **no executable test**, support, base and builder classes. They are not tests, they are not fast tests, and they must not reach a work-list.

### 1b. Read the cost, do not estimate it

Parse the result files for per-class time. Report per-class time, per-module totals, and each class's share.

**Never re-run the suite to fill this in**, unless the user asks. A re-run measures this machine today; the result files record what the pipeline actually paid, which is the number the work is judged against.

Three guards, each of which changes what may be claimed:

- **Report the result files' timestamp.** Older than the last change to the sources they describe means the cost column is indicative, and must be labelled that way.
- **Report how many inventoried classes have no result row.** An unmeasured class is not a fast class. It is commonly a class nothing runs, which 1c settles.
- **Never fill an empty cost cell with an estimate.** Empty and labelled beats plausible and wrong.

Where the runner has emitted **no result output at all**, the state of any repository whose suite has not been run, and so the commonest first-run condition, say so once, label the whole column `UNMEASURED`, and report every step that ranks by cost as **unavailable**. Do not silently reorder those steps by class size or by rung: a proxy presented in a cost column reads as a measurement. Classification still runs; it needs no timings.

### 1c. Find what no job runs

Cross the inventory against every job's selection from 0d. A class that compiles but is selected by nothing costs compile time and buys no evidence.

Separate two findings that look identical and are not:

| Finding | What it means |
|---|---|
| **excluded on the record** | a marker, tag or gate deliberately holds it back, and something says so | 
| **selected by nothing** | no job's selection reaches it, and nothing records that as intended |

The first is a decision to confirm. The second is the finding.

### 1d. Read the previous baseline; do not write one yet

Read the baseline a previous run left, if there is one, and diff this run's measurements against it, that is the only way "did this get better" is answerable later. Path from `test_layers.baseline_path`, defaulting inside `{standards_dir}`.

**Write nothing here.** Phases 0-3 create, edit and delete no file, and the baseline's own content needs the Phase 2 census and the Phase 3 counts, which do not exist yet. The baseline is composed as part of the Phase 3 report and written **once**, in 4d, after the gate.

## Phase 2, Classify Every Test Class by Rung

**The ladder is the installed layer rule's, not this skill's.** Read `test-layer-policy.md` and use its rungs verbatim, the numbering, the names, and the ordering. Where that rule and this section could differ, **it wins**; Phase 0b already says so, and a skill that renames the rule's rungs makes every finding it reports unciteable.

| Rung | Context | Belongs here |
|------|---------|--------------|
| **1** | No framework context, the subject constructed directly, its collaborators substituted | logic: mapping, calculation, branching, validation, error translation. **The default** |
| **2** | Sliced framework context, one layer loaded, what sits behind it substituted | behaviour only that layer can fail: routing, request binding, status codes, serialisation |
| **3** | Real-database suite, the same engine and version as production | anything a real database can contradict: query semantics, constraints, migrations, transaction behaviour, persisted state |
| **4** | Full application context, the whole application wired up | **only when the wiring is the subject:** startup, the dependency graph, configuration binding, a filter chain end to end |

**Cost rises with the rung; evidence does not.** Rung 4 is on the ladder, reachable, never a default.

**An in-memory substitute is off the ladder entirely.** A stand-in engine is **not rung 3**, it carries none of rung 3's authority, while costing as much as a context to boot. Classify it as `substitute`, never as a rung, and count it separately. What evidence it *can* support is the installed database rules' call, not this skill's and not the layer rule's.

**Where a target's rung-3 service is not a database**, its rung-3 marker is still whatever the seam declares, and the same deferral applies: the authority question belongs to the installed rules for that service. Classify from the seam; do not invent a rung the ladder does not have.

Assign from the seam's marker map, **highest matching rung wins**, with the substitute check taking precedence over rung 3. Derived, never listed: a class added tomorrow classifies itself, and there is no list to go stale.

### Grep produces candidates. Only reading produces verdicts.

Two failures are measured, not hypothetical, and both produce findings that look mechanical and are fiction.

- **A file in the test tree is not a test.** Base classes, support classes and configuration holders carry the same markers as real tests, and a scan for "boots a context and asserts nothing" returns all of them. **Confirm an executable test exists in the class before it reaches a verdict column**, and report the marker-bearing non-tests as their own count.
- **Markers span lines.** Declaration sets and multi-value marker arguments wrap, and a nested delimiter inside a string truncates a naive scan and silently shifts every later result, a second argument from the next line gets read as if it were the first. Match balanced and multi-line. **A count from a line scan is not reportable**, and a line scan cannot count the distinct-context metric at all.

- **A local vocabulary can map onto the rule's terms and not onto its order.** A target commonly has its own testing guide with its own names, and those names usually correspond one-for-one to the rule's rungs. **The correspondence is not the check; the ordering is.** A guide that treats booting the whole application as its *cheap* end-to-end tier puts that tier below its real-database tier, where the rule puts it above, so a map built from the local names reads as aligned and ranks two rungs backwards, and every view built on it inherits that silently.

  **Build the map from what each marker makes the test do, never from what the target calls it.** A marker that boots the whole application is rung 4 whatever the local name for it, and a marker that substitutes the real engine is off the ladder whatever tier the guide assigns it. Where the local order and the rule's order disagree, **report the disagreement, do not resolve it.** The target's guide may be the thing that needs changing, and that is a finding, not an input.

**Validate the parser before you trust a count.** Take a sample, check it by hand against the source, and only then report numbers. State plainly how many classes could not be parsed, an unparsed class is not a clean one.

### The evidence table

**It is the mandate for every later phase.** A class is not on a work-list until it appears here.

```markdown
| Class | Markers found | Rung | Measured | Assertions | Selected by |
|-------|---------------|------|----------|------------|-------------|
| a/OrderRules | none | 1 | 0.4s | 12 | unit job |
| a/OrderApi | full context, request surface | 4 | 31.2s | 8 | unit job |
| a/OrderStore | in-memory stand-in | substitute | 12.9s | 6 | unit job |
| a/LegacyFlow | full context | 4 |, | 3 | nothing |
```

Report the census per rung, plus the substitute count: classes, measured total, and share of the suite.

### 2b. Necessity, does this test earn its place at all?

Everything above answers *is this test at the right rung?* This step answers the other question: **should it exist?** Without it, "the higher-layer test already covers this, so drop the cheaper one" can be asserted and never measured, and a suite gets re-layered without getting smaller or faster.

**A test earns its place only if it can fail for a reason nothing else catches.** Two corollaries:

- **Do not test what you do not own.** A query method whose declaration *is* the query tests the framework, not this project's code. The installed rules already say this; this step counts how often it happens.
- **A test of logic earns its place when the logic genuinely varies with its inputs** and is not a library guarantee. A function with one path and no branching rarely does.

For each test in scope, record three things and one verdict:

| Column | What goes in it |
|---|---|
| **Asserts** | the observable this assertion is about, in the target's own terms, not the method name |
| **Also asserted by** | every other test asserting the same observable, or `nothing else` |
| **Subject** | `our logic` or `library guarantee`, whose behaviour would have to change for this to fail |
| **Verdict** | `KEEP` / `redundant-with-{other}` / `library-guarantee` / `no-oracle` |

`no-oracle` is the fourth answer and it is not `KEEP`: a test that cannot fail for any change to this project is neither necessary nor redundant, it is inert. Report it distinctly.

**The unit of comparison is the asserted behaviour, never the entry point.** A rung-2 test on a request path asserting routing, request binding and response shape with the service substituted is **not** made redundant by a rung-3 test on the same path, they fail for different reasons. Two tests share an entry point far more often than they share an assertion, so an entry-point match is a candidate for reading, never a redundancy verdict. A necessity pass built on entry-point matching deletes real coverage and reports it as deduplication.

**⏱ Scope, and its cost.** This step reads assertions, so it is bounded by default to the classes already on a Phase 3 work-list plus the rung-3 suite they would be compared against, the only pairs a removal decision can turn on. A full-suite necessity pass is available on request and costs a read of every test class; say which scope ran, and never present a bounded pass as a suite-wide overlap figure.

**Pair it with the red control.** Necessity analysis without 4b's red control is exactly how a real coverage hole gets justified as deduplication: the analysis says the other test covers it, and nothing checks that the other test can fail. A `redundant-with-{other}` verdict is a candidate for 4b, never an approval to delete.

**Where this and the layer views disagree, they are answering different questions, say both.** W3 says a substitute-backed class claims authority it does not have and the direction of travel is **up**, never down. This step can find that the same class's assertion is a library guarantee, or already made at the rung above. Those are not opposite verdicts: W3 gives the only correct direction for a move, and this step says whether the move is worth making at all. Report the pair, *this class must move up to be worth anything, and its assertion is already made up there*, and let 4b stage one decision, rather than resolving it here in either direction.

## Phase 3, The Work-Lists, then Propose (**REQUIRED GATE**)

### The six views

| View | What it holds | Read it as |
|------|---------------|-----------|
| **W1, context-load-only** | a **class** whose only cost is booting a context: no assertion at all, or an assertion that cannot fail because the boot already proved it | **re-layer or rewrite, never delete**, the boot is a smoke check even when the assertion is dead |
| **W2, rung 4 whose subject is not the wiring** | rung-4 classes that drive only the request surface, rung 2 is where that behaviour belongs, **and the entry points reached by more than one suite**: report how many this suite and the rung-3 suite both reach, how many each reaches alone | rung 2 is where request-surface behaviour belongs. A shared entry point is a **candidate for W6 to read**, never a redundancy verdict: two suites reaching the same path routinely fail for different reasons |
| **W3, substitutes claiming authority** | off-ladder classes whose subject a real database can contradict | they claim rung-3 authority they do not have. Move **up** to rung 3, never down |
| **W4, run by nothing** | 1c's "selected by nothing", with "excluded on the record" listed separately | the second is a decision, the first is dead weight |
| **W5, distinct heavyweight contexts** | the count of distinct context keys booted across the run. **A heavyweight class carrying no key marker has the empty key set, which counts as one context**, the default one, so two runs over the same repository return the same number | each distinct key is one more full boot the suite pays for; converging two saves a boot without touching a single assertion |
| **W6, necessity** | 2b's verdicts: `redundant-with-{other}`, `library-guarantee` and `no-oracle`, each with the assertion it is about and the test that also asserts it. `KEEP` rows are not listed, only counted | the only view that answers whether a test should exist. Every row is a **candidate for 4b**, and a removal is staged only once the red control has shown the named cover can fail. State which scope 2b ran at, since a bounded pass cannot speak for the classes it did not read |

W5 is the cheapest win in the list and the least visible: it changes no test's meaning, so nothing but the marker sets has to be reviewed.

**W1 is class-level only.** A dead or tautological assertion sitting inside a class of real tests is a different finding: nothing is booting on its account, so there is no cost to recover, and "never delete, the boot is a smoke check" does not reach it. That is a method-level assertion-quality finding, `test-scope-policy.md`'s. Record it `external, deferred` and keep it out of this view, or W1 stops being a list of contexts the suite could stop paying for.

**One guard on W2, because it produces the most tempting wrong answer.** A request-surface entry point absent from every suite's request surface is **not** an untested entry point. A test can exercise the same code by constructing it directly and never going near a request. So W2 reports what is proven **twice**, never what looks unproven, and any "covered by neither" figure it shows carries that caveat beside it, or it is a false verdict wearing a count.

### The two classes of work

| Class | What it is | Who applies it |
|-------|------------|----------------|
| **MECHANICAL** | one correct answer, visible in a diff, revertible on its own | Phase 4a |
| **SEMANTIC** | moves a class to a different layer; the replacement must prove what the original proved | Phase 4b, **never unattended** |

### The gate

Report, and **change nothing until the user answers** unless Phase 0 agreed execute-and-report, and that agreement never covers 4b:

- The Phase 2 evidence table, the rung census, and the substitute count
- The six views, with counts and measured time per view
- Per concern: what it changes, its cost, and what reverting it costs
- Before/after **measured** totals where a before-number exists, and plainly that no after-number is measured yet
- Everything you are **not confident about**, and every candidate a reading did not confirm

**Order matters, and it is not negotiable: mechanical first.** It changes the measurement. Deciding semantic work against pre-mechanical numbers picks the wrong classes.

## Phase 4, Execute

### 4a. Mechanical, four concerns, each selected on its own

**1. Strip cache-defeating flags from the project's own commands.** A flag that forces a full rerun discards the build's own up-to-date check *and* its cache, so every run rebuilds everything. The up-to-date check already reruns a task when its inputs change, that is its contract.

**Probe before applying.** Where an installed rule still mandates the flag, the rule wins on specifics: **report the contradiction and apply nothing.** A strip that leaves a project's own installed rule contradicting its build commands is worse than the flag.

```bash
# Presence is not polarity. Print the matching lines and READ them; never branch on the exit code.
grep -rn -- '<flag>' "$standards_dir" 2>/dev/null
```

| What the matched line says | Verdict |
|---|---|
| prescribes the flag ("use it", "always pass it") | **MANDATED**, record `external, deferred`, name the rule file, stop this concern |
| **forbids** the flag | **CLEAR**, the rule agrees with the strip; proceed |
| no match at all | **CLEAR** |
| matches but the intent is unreadable | **AMBIGUOUS**, confirm with the user; do not guess either way |

**A presence-only probe gets the forbidding case exactly backwards**: it reports MANDATED, disables the concern permanently, and names a rule that bans the flag as the reason for keeping it. Read the line.

On CLEAR, strip, and keep any forced rerun that a state the build system does not track as an input genuinely needs, naming that state.

**Removing a bypass flag makes a cached result more likely, not less.** So this concern is only safe where a cached result is still reported as cached rather than as freshly verified. Confirm the project's test-running step does that, and never weaken it to make this concern applicable.

**2. Remove a wipe step from container image builds.** It discards the layer cache the build exists to reuse.

**No installed rule stands behind this one**, do not borrow one that is about something adjacent. So justify it from the target's own build definition, and probe first the same way concern 1 does: a stack rule may actively *prescribe* the step this would remove, and where it does, the rule wins and this concern reports instead of applying.

**3. Install the layer rule.** Probe first, see Phase 5a. Do not author a rule the framework ships.

**4. Give the change-scope gate values to read.** Fill `verify.targeted_command`, `verify.always_full_paths` and `verify.comment_only_skip`. Absent, the gate has nothing to read and every change costs a full suite, whatever its size.

**An absent key and an empty one are different statements, and only one of them is yours to write.** Absent means nobody has said; empty means a team said "nothing here forces a full run". Test with a key-presence check, never with a default-if-falsy, the latter cannot tell them apart. So propose a value for an absent key and leave a deliberately empty one alone: writing an empty list into an absent key silently records a decision nobody made.

Two constraints on what you may propose. A targeted command that secretly runs everything makes the whole axis a no-op that still reports as targeted, never write a full command into the targeted key. And the comment-only skip is safe only where comments cannot reach the built artifact; where they can, leave it off.

**Verify 4a:** the project's own gate still passes, **and the suite still selects the same set of classes.** A mechanical change that changes selection is not mechanical, revert it and move it to 4b.

### 4b. Semantic, staged, never applied unattended

Produce a plan per class: current layer, target layer, what the replacement must prove, and what the move costs to run. **W6's rows arrive here too**, a `redundant-with-{other}` verdict is a removal proposal, a `library-guarantee` or `no-oracle` verdict is a removal proposal with no replacement to name, and all three are staged, never applied.

**Two invariants, because a count catches deletion but not dilution.**

1. **Count non-decreasing, two numbers, both required.** The **static assertion inventory** from the seam's `assertion_markers`, and the **per-class executed test count** the runner already wrote in the result files. Both after >= before, per class.

   One number is not enough, and the gap is not hypothetical: where the seam counts a data-driven test as one marker, replacing a five-case one with a single-case one holds the static count exactly while five executed assertions become one. The static count comes from the source, the executed count from the result files, and only together do they see that.
2. **Subject preserving.** Each assertion still asserts the same observable, at the same or stronger fidelity. An assertion whose subject changes, a state assertion becoming a non-null, a rung-3 assertion becoming a substitute, is **listed individually for explicit sign-off**, never folded into the count.

The second is the one that matters. A rewrite can hold its count exactly while every assertion in it proves less, and the suite still goes green, nothing but this check reports that.

3. **Red control, a named replacement is not a replacement until it has been shown to fail.** For every deletion that names another test as its cover, run this before the deletion is staged as done:

   1. Remove or break the production line the deleted test pinned.
   2. Run the named replacement.
   3. It must go **RED**. If it stays green, the replacement does not cover the deleted path, restore the original test, or write a real replacement and repeat.
   4. Restore the production line and confirm green again.

   Record, per deletion: the production line broken, the replacement run, and the observed failure. A deletion with no recorded red control is not staged.

   **A named replacement can be in the right module, at the right rung, testing the right constraint, and still not touch the deleted path**, reproducing the *setup* rather than covering the *code*. "Named a replacement" is a claim about intent and reads as compliance; only the red control tells the two apart. This is the same distinction the layer rule states generally: a check that cannot distinguish "passed" from "never ran" is not a gate.

   **⏱ Cost:** one extra run of the named replacement per deletion, inside 4b only, which is never applied unattended. Where a deletion names several replacements, each is controlled separately; a red from one does not cover another.

**Evidence for both:** run the affected classes before and after and diff the assertion inventory, not just its size. Where the target exposes a coverage seam, add a coverage-report delta: a count delta cannot see a suite that sits outside the coverage aggregation.

Three further constraints, each of which has bitten:

- **Never edit a test to make it pass.** `test-change-policy.md` governs here, and its diagnosis fork sends an over-coupled test to **stop and surface**, not to a quiet rewrite, and not to this skill's judgement. A change whose only effect is to make an assertion pass is the defect, not the fix. This skill re-layers tests; it is not a make-it-green engine, and the distinction has to hold in the installed copy, not just in intent.
- **Moving up to rung 3 can lower reported coverage while raising evidence.** A rung-3 suite is commonly outside the coverage aggregation. State that consequence in the plan: the invariant can hold while the quality gate regresses.
- **Never move a class down a rung to save time.** Substitute → rung 3 costs more and proves more; that is the correct direction. The saving comes from rung 4 → rung 2, where the extra wiring was proving nothing, since the wiring was not the subject.

### 4c. Reconcile with the tracker, do not start a parallel list

**This is the one phase that leaves the machine.** Declare its round-trip in the cost statement before offering it, and take the tracker's identity from the project, an existing `config_hints` tracker key, or the Phase 0 question, never from a guess.

Query the tracker for open items about suite duration, test cost or flakiness, and map each work-list entry onto one where it exists.

| Outcome | Report as |
|---|---|
| a work-list entry matches an open item | covered, reference it, add nothing |
| a work-list entry matches nothing | not tracked |
| an open item describes what the scan did not find | unconfirmed, the item may be stale, or the scan may be blind |

The third row is the one worth reading twice: a scan that finds nothing is not proof the item is wrong.

**With no tracker configured or reachable, report the work-lists unreconciled and say which.** Never invent a reference, and never substitute a list of your own, a parallel list is the thing this step exists to prevent.

### 4d. Write the baseline, the run's only write outside 4a and 4b

The single write of the file 1d read. Record the date, the per-module totals, the Phase 2 rung census and substitute count, the six view counts, the distinct-context count, and the result files' own timestamp, with the post-mechanical numbers, and only the numbers that were actually measured. Path from `test_layers.baseline_path`, defaulting inside `{standards_dir}`.

## Phase 5, Stop the Regrowth (**do not skip**)

Without this the census returns, because the path of least resistance has not moved.

**5a. Get the rule in place, probe before you write.** The framework ships `test-layer-policy.md` and the installers put it into every target, so on an installed project **it is already there before this skill runs.** Authoring it again duplicates a file the framework owns; the copy is reverted on the next upgrade, and until then the standard has no identifiable owner.

```bash
ls "$standards_dir"/test-layer-policy.md >/dev/null 2>&1 && echo PRESENT || echo ABSENT
# A rule listed in bootstrap_rules has diverged deliberately and the upgrader leaves it alone.
# Match on basename, the field holds bare filenames on some targets and full paths on others.
jq -r '[.bootstrap_rules[]? | sub("^.*/";"")] | if index("test-layer-policy.md") then "project-owned" else "framework-owned" end' \
  .claude/config_hints.json 2>/dev/null
```

| Probe says | What to do |
|------------|------------|
| **PRESENT** | **Do not rewrite it.** Confirm it still states the points below, report the owner, go straight to **5b**, the half that is genuinely per-project, and the half usually missing |
| **PRESENT but contradicts the points below** | Report the divergence and the owner. Edit only if project-owned; if framework-owned the fix belongs upstream, so record `external, deferred` and leave it alone |
| **ABSENT**, but only after the fallback below | **Write it** there |

**A name-only probe is not enough to report ABSENT.** The rule may have shipped, or been renamed, under a different filename; concluding ABSENT then tells the user to author a rule the framework already owns, and the next upgrade overwrites their copy. So before reporting ABSENT, search `{standards_dir}` for an equivalent policy by content, a rule stating which layer a new test belongs on. Found under another name, report **PRESENT under another name**, cite it, and go to 5b.

The rule must state: a new test runs at the cheapest rung that can still fail for the reason it exists; rung 1, no framework context, is the default; behaviour only the request layer can fail belongs at rung 2; anything a real database can contradict belongs at rung 3; a full application context is rung 4 and only when the wiring is the subject; an in-memory substitute is not rung 3 at all and carries none of its authority; and a test above rung 1 says in one line what forced it there.

**5b. Wire it in**, or it is decoration:

| Wire | Where |
|------|-------|
| A new full-context class, or a new class on an in-memory stand-in, is a **blocking** finding that names the layer it belongs on | the project's code-review rule |
| Each new test declares the layer it runs at and why | the project's test checklist or template |
| The change-scope gate has real values | the three `verify.*` keys |
| The baseline is re-measured | whatever step already reads the result files |
| Contributors and agents are pointed at the rule | `AGENTS.md`, `CLAUDE.md`, or `CONTRIBUTING` |

**A wiring point that covers less than the inventory is not wired.** Check each one's coverage against Phase 1a and name the gap.

**Prefer a gate over a rule.** This is the one family here a pipeline can police outright: the census is derived from markers with no list to maintain, so a job can fail the build when the full-context count rises. A rule asks people to remember; a gate does not, and it makes this skill's next run boring. If the project can host that check, propose it.

## Final Report

Per layer: classes, measured time, share. Then per view: count and measured time. Then what 4a changed, what 4b staged, what 4c reconciled, and the baseline's path.

State the before and after as **measured** numbers, or state plainly that the after is not measured yet and what would measure it. A projected saving presented as an achieved one is the single most misleading thing this skill can output.

Close with the assertion count before and after every applied change, and the one wiring point that would stop the class recurring.

## Edge Cases

- **No result files**, classify and report layers with the cost column empty and labelled. Never estimate. Never re-run the suite to fill it unless the user asks, and say which of the two happened.
- **Result files older than the sources**, report the timestamp and label the column indicative. A stale number carried into a fresh report is laundered as newly checked.
- **A marker-bearing file with no executable test**, not a test. Excluded from every view, reported as a count.
- **A class held back on the record**, a deliberate exclusion or quarantine is a decision, not dead weight. Confirm before proposing anything.
- **Generated tests**, never edit. Fix the generator or the template.
- **A project with a coverage threshold**, it cannot lose assertions to a rewrite. The invariant is what keeps the threshold honest, so run it even when the user waives review.
- **A suite already entirely at the lowest layer it can be**, report a clean bill of health with the census and the totals. Finding little to move is a valid outcome.
- **The whole suite is one layer because the seam says so**, suspect the marker map before the suite. Re-check 0a's precedence and say which source supplied it.
