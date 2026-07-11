---
name: ar-api-dd-compare
description: Audit what the code ASSUMES against what production ACTUALLY does, using Datadog traces, and turn mismatches into fix tickets. Say "ar-api-dd-compare" or "trace audit". On-demand only (Datadog MCP is interactively authenticated).
disable-model-invocation: true
---

# API Datadog Compare (trace-vs-code audit)

Pull a Datadog trace, build a runtime profile, diff it against what the code claims, emit fix tickets with a verifiable runtime budget. Catches runtime-shape defects that diff review and unit tests miss.

Detect this repo's language/framework and reason in its idioms, the heuristics below describe runtime shapes, not any one language.

## Prerequisites

- **Datadog MCP connected** (interactively authenticated). This is an **on-demand** skill, not for cron/headless runs. If the MCP isn't available, say so and stop.
- The target repo is checked out so the skill can read the code behind the traced endpoint.

## Flow

1. **Ask for a Datadog trace**, a trace URL, or an endpoint/resource name + time window to find one. (Don't hunt blindly; ask the user for the trace they care about.)
2. **Pull the trace** via the Datadog MCP and build a **runtime profile**:
   - per-resource/outbound call counts and durations
   - target hosts (and whether public-edge vs internal)
   - sequential-vs-parallel timeline of independent calls
   - repeated DB statements / outbound requests
3. **Read the relevant code** behind the traced path and extract its **declared assumptions**: caching (annotation/decorator/wrapper + TTL), async/parallel constructs, configured base URLs/hosts, locally-synced tables that back a resource, and any doc/comment claims about behaviour.
4. **Diff assumed-vs-actual** using the heuristics catalog below.
5. **Present findings**, each with trace evidence (counts, ms), a code-level root-cause hypothesis, and an estimated saving. Wait for the user to confirm which to act on.
6. **Create fix tickets** (on confirmation) following **`ar-ticket-creator`** conventions, including always asking the user for the epic. **Every ticket's "Done when" embeds a runtime budget** (e.g. "at most one currency-rate fetch per request") so re-running this audit verifies the fix objectively.

## Heuristics catalog (runtime shape → likely defect)

1. **Same outbound/DB call repeated N times in one trace** → an ineffective or bypassed cache (e.g. an in-object cache that only applies at the public entry point and is skipped on internal self-calls), or a missing request-scope memoization.
2. **Code declares caching but the trace shows a fetch on every request** → claim/reality mismatch; the cache isn't taking effect.
3. **Independent outbound calls running strictly sequentially** → parallelization candidate.
4. **An outbound call hits a public edge host while sibling services use an internal endpoint** → wrong/ slow routing.
5. **A live external call for data that an existing sync job already lands in a local store** → replace the live call with the local read.
6. **The same write/read repeated far beyond the row count it touches** → flush amplification / N+1.
7. **Auth/token acquisition inside the request hot path** → token-cache candidate.

(Extend the catalog as new shapes are found, keep each entry as "runtime signal → hypothesis", language-neutral.)

Reference `ar-ticket-creator` for ticket writing, don't restate its convention.
