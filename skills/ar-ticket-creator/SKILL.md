---
name: ar-ticket-creator
description: Create one well-formed, PR-sized ticket from your current work, using the project's configured issue tracker. Say "ar-ticket-creator", "create ticket", or "spin off a ticket". For large multi-PR features use ar-taskflow-planner instead.
disable-model-invocation: true
---

# Ticket Creator

Streamlines the recurring "I'm on a branch and want to spin off a clean ticket for this work" flow: one PR-sized ticket, fast, no spec, no decomposition, no story branch.

**Tracker-agnostic:** create the ticket using the row for your `tracker.type` in the **Tracker Dispatch Table** (`<standards_location>/mcp-integration.md`, resolve `standards_location` from `.claude/config_hints.json`), `gh issue create` for github, `createJiraIssue` for jira, Linear MCP for linear, a manual identifier for none. Steps that mention epics, `createJiraIssue`/`editJiraIssue`, or the Atlassian MCP below are the **Jira path**; a github user substitutes `gh issue create` (no epic concept, use a label/milestone if desired).

## Front-door complexity gate (decide scope FIRST)

This skill and `ar-taskflow-planner` are **siblings, not a merge**. Route by complexity before doing anything else:

| The work is… | Use | Produces |
|---|---|---|
| **One PR-sized change** (a bug fix, a small enhancement, a single task under an epic) | **ar-ticket-creator** (this skill) | one `Task` ticket under an epic |
| **A large, multi-PR feature** (needs architecture discussion, a spec, sequential sub-tasks) | **ar-taskflow-planner** | spec doc + N raw prompts + a `Story` ticket + story branch + manifest |

Running the planner for a single bug fix is overkill; that gap is what this skill fills. If during this flow the work turns out to be multi-PR, **stop and hand off to `ar-taskflow-planner`**.

## Writing convention (SINGLE SOURCE OF TRUTH, do not restate)

The ticket body MUST follow the **Raw Prompt Writing Convention** in the ar-taskflow-planner skill (Content Rules 1 & 5 especially: *describe WHAT not HOW; no class names, file paths, or method signatures*, the prompt-understanding phase discovers those from the codebase when a session picks the ticket up). Read that section; do not duplicate it here, if the two ever drift, the planner is canonical. (If a shared `docs/ai-rules/` rule has been extracted from it, reference that instead.)

**This convention is INVIOLABLE and outranks any epic-embedded ticket-creation template.** An epic's template may shape *structure, labels, and brevity*, but it may NOT reintroduce line numbers, file paths, or internal class/method names, even if it explicitly asks for them (e.g. "symptom + key file:line"). When an epic template requests code locations, translate them to intent level and flag the conflict to the user (see Nice-to-haves). Never let a nice-to-have template override the single-source-of-truth rule.

Why it matters: **the ticket is the SOURCE for executing the task via task-flow.** It must be readable by a *human* (grasp the intent fast) AND sufficient for an *AI/LLM* to execute against the real code. So:

- **Intent + contract level only. NO line numbers, file paths, or internal class/method names.**
- **DO capture the non-derivable decisions:** root cause in domain terms; the behavioural contract; agreed specs (rules, acceptance/reference cases, request/response payloads); external-API contract facts (field/param names, error codes); explicit scope + out-of-scope; a clear "Done when".
- **Suggested structure:** `What's broken` / `Why (root cause)` / the change split into parts / `Out of scope` / `Done when`. Fenced code blocks for payloads and reference cases.
- **Enumerate EVERY agreed deliverable as a discrete, explicitly-named item, including ones only *implied* by a decision.** The ticket must stand alone: the future session that picks it up has none of the conversation, so anything left implicit is effectively missing. Decompose the agreed change into named deliverables, each with its own scope line (which side owns it) and its own "Done when" criterion. In particular, for every "a human / operator / another team can do X" behaviour, identify the interface that behaviour *requires* (commonly a new internal API endpoint) and list it as a first-class deliverable, do **not** compress an implied deliverable into a one-word "action." Where deliverables are **coupled** (shipping one without the other strands the system in a broken or half-built state, e.g. removing an automatic path without adding the manual one that replaces it), state the coupling in the ticket so it cannot be half-shipped. This stays intent/contract level: naming a required endpoint is a *deliverable*, not implementation leakage (no class names, signatures, or file paths).

## Behaviour when invoked

1. **(Jira path) Ask the user which Epic** to create the ticket under (epic key or URL). **Always ask, do NOT search Jira for epics or try to infer one** (epic discovery is slow and error-prone; the user knows the epic). Wait for their answer before proceeding. For github there is no epic, skip this and (optionally) ask for a label/milestone instead.
2. **Ask for the basic requirement / raw intent.**
3. **Verify the requirement against the codebase, MANDATORY pre-finalize gate.** Before writing the ticket, fact-check every request/response contract, field name, error shape, enum, and API-behaviour claim in the requirement against the real source **and** the project rules. The ticket is the SOURCE that drives task-flow execution, if the requirement contradicts reality, a clean-looking ticket drives a wrong implementation. Shape/contract claims must be **verified, not assumed** (this is stronger than a light intent-read; you still don't read broadly, that's the prompt-understanding phase's job later). On the outcome:
   - **Conflict or genuine ambiguity, interactive:** ask the user a clarifying question (e.g. `AskUserQuestion`) and resolve it BEFORE writing the ticket. Do not paper over it.
   - **Conflict, auto / non-interactive (no human to ask):** REJECT the ticket and FAIL the task, surfacing the conflict explicitly. Never emit a plausible-but-wrong ticket.
   - **⏱ Cost note:** this gate verifies contract claims on every ticket (and may add one clarifying round-trip in interactive mode). It runs pre-creation precisely because catching a contract mismatch here is cheap; catching it after a wrong PR is not.
4. **Create the ticket using the Create-ticket row for your `tracker.type`** in the Tracker Dispatch Table (`<standards_location>/mcp-integration.md`). For github: `gh issue create --title ... --body ...` (multi-line body is fine). **(Jira path)** create in Jira via the Atlassian MCP as a child of the epic, because `createJiraIssue` double-escapes newlines, create first with a stub, then set the multi-line description via a follow-up `editJiraIssue` with `contentFormat: "markdown"`, and verify with `responseContentFormat: "markdown"` (the echoed description must show real newlines).
5. **Ask for priority** if not given (the project's scheme, e.g. P0/P1/P2) and set it.
6. **Match status/assignee to reality**, if the ticket covers work that's already done/in-progress, transition it to its true state (e.g. Ready for QA) and assign correctly in the same step; never leave a finished item at To Do.
7. **Code-location leak scan (MANDATORY, cheap).** Before declaring done, run a quick deterministic scan of the ticket body for convention leaks, line numbers (`:NNN`), file paths, internal class/method names, and strip or translate any to intent level. This is a non-LLM check that runs on **every** ticket (it is the one defect class an epic template most often reintroduces); it is independent of, and far cheaper than, the optional deeper verification below.
8. **(Optional) Deeper verification of the created ticket**, the post-creation fidelity + cold-read checks (see below). Skippable via `--verify` / `--no-verify` or a yes/no prompt. **⏱ Cost note:** this adds a fresh sub-agent round-trip + an `editJiraIssue` reconciliation, not free, so it is opt-in, not mandatory on every ticket (unlike the step-7 leak scan, which always runs).
9. **Return the created ticket key + URL + priority** (and a one-line verification verdict if the optional check ran).

## Post-creation verification (optional, hybrid, fidelity + cold-read)

Run **two complementary checks**. Key insight: a *fresh* sub-agent's lack of conversation context is a **feature**, it's the closest stand-in for the future task-flow session that will pick the ticket up with zero memory of how it was authored.

- **Fidelity check, SAME session (inline, cheap).** Only the authoring session has the conversation, so only it can confirm the ticket captured *everything the user said*, including late course-corrections (scope changes, dropped cases, mid-discussion decisions). Explicitly confirm **every deliverable the conversation agreed on is present as an explicit, discrete item, not merely implied** by another change. A fresh agent can't do this, nothing to compare against.
- **Standalone + accuracy check, FRESH sub-agent (independent).** Spawn a sub-agent given **only the ticket text + read access to the repo** (NOT the conversation). Ask it to: (a) flag anything ambiguous, missing, or that silently assumes prior context; (b) fact-check technical claims against the actual code; (c) catch any leaked line-numbers / file paths / internal class names (convention violations); (d) surface any required deliverable that appears only *implied* rather than stated, would a reader with zero prior context know all the concrete things to build? It returns structured findings. A same-session self-review can't do this honestly, it "knows what we meant" and rubber-stamps gaps a cold reader trips on.

The authoring session reconciles the sub-agent's findings and edits the ticket before declaring done. **If only one check is kept, keep the fresh sub-agent**, it catches the defect class self-review structurally cannot; the fidelity pass is nearly free to bolt on.

## Nice-to-haves

- If the target epic's description carries a ticket-creation prompt template, honour its **structure and brevity**, then reconcile it against the Writing convention before using it: translate any requested code locations (file:line, class/method names) into intent-level descriptions, and flag the conflict to the user. The Writing convention wins, a template may shape layout, never reintroduce code locations. If the epic template itself violates the convention (asks for file:line), note it to the user so the epic owner can fix the template at source.
- Confirm the tracker integration is reachable (github: `gh auth status`; jira/linear: the MCP is connected per the dispatch table's Check-configured row); fail gracefully with a clear message if not.
- Default issue type `Task`, with `Bug` / `Story` override.
- Screenshots: only truly public URLs can be embedded (the MCP has no file upload); private links must be attached manually.

## Relationship notes

- The cold-read sub-agent verification (above) is **new to both** this skill and the planner, consider promoting it to verify the planner's raw prompts too.
- Ticket = intent + non-obvious decisions, not the code's current shape. Same principle the planner's convention encodes.
