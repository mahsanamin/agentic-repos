---
name: ar-dd-api-performance
description: Scan a window of Datadog traffic (default last day, production), sample traces for APIs over the latency/error thresholds, cross-reference this repo's code, and maintain per-API optimization report files under the workspace Performance_Findings directory, then commit them. On-demand only. Say "ar-dd-api-performance", "api performance scan", "which APIs are slow", or "update the performance reports".
disable-model-invocation: true
---

# Datadog API Performance Scan

Discover which APIs were hit in the configured window (default: the last day), find the slow ones, explain *why* they are slow (which internal calls, which code), and keep one living report file per slow API per environment. Re-runs are cheap and idempotent: a report is only rewritten when its findings actually change, that's what makes this safe to run daily in a loop without drowning the findings directory in noise.

Sibling of `ar-api-dd-compare`: that skill is a one-off deep audit of a trace the user hands you; this skill is the automated sweep that *finds* the endpoints worth auditing and tracks them over time.

Detect this repo's language/framework at runtime and reason in its idioms, nothing below is Java-specific except the examples.

## Prerequisites

- **Datadog MCP connected** (interactively authenticated). If unavailable, say so and stop. This matters for loops: a cron/headless run without the MCP must fail loudly, not silently produce an empty report.
- The repo this skill lives in is checked out, code cross-referencing reads the *current working tree*.

## Configuration (resolve once per run, persist on first run)

Read `.claude/skill.config`. The skill owns a `datadog_performance` block:

```json
"datadog_performance": {
  "service": "{your-service-name}",
  "env": "production",
  "latency_threshold_ms": 200,
  "error_rate_threshold_pct": 5,
  "window": "now-1d",
  "samples_per_api": 4
}
```

- **Missing block (first run):** auto-detect the service via `search_datadog_services` using the repo directory name. Proceed without asking only when the match is unambiguous: an exact name match, or a single candidate that contains / is contained by the dir name. Confirm the candidate has span traffic (`aggregate_spans` count > 0 in the window), write the block with the defaults above, and tell the user what was persisted.
- **Zero or multiple plausible candidates:** stop with a clear message listing what was found, never scan a guessed service. On any resolution failure, persist nothing to `skill.config`.
- Note: `skill.config` may contain non-JSON trailer lines after the JSON object, preserve them when writing.

**Run-time overrides (session-only):** the invocation may override any config value in plain words or `key=value` form, "run on staging", "ar-dd-api-performance env=staging", "scan the last 6 hours" (`window=now-6h`), "threshold 500ms". Apply overrides for this run only, **never persist them to `skill.config`**; the block always holds the defaults. Typical usage: the configured default env (production) runs in the scheduled loop; staging is invoked manually on demand (e.g. to watch an API being optimized while it's still in testing).

**Findings root** (priority order):
1. `paths.performance_findings_root` in `.claude/skill.config` (explicit override)
2. Derived: `coding_tasks_root = dirname(paths.tasks_root)`; replace the `_Coding_Tasks` suffix of its basename with `_Performance_Findings`, as a sibling directory. Example: `.../{workspace}/{Project}_Coding_Tasks` → `.../{workspace}/{Project}_Performance_Findings`. If the basename has no `_Coding_Tasks` suffix, use `dirname(coding_tasks_root)/Performance_Findings`.
3. Fallback (no tasks_root): `.claude/performance-findings/` in this repo.

Reports **always** live under an environment directory placed directly inside `DataDog/`: `{findings_root}/Backend/DataDog/{Env}/API_Performance/` where `{Env}` is the capitalized env name (`Production/`, `Staging/`). Env-first keeps each environment an independent tracking universe, its own report files, its own `_index.md`, its own fingerprints and History, and leaves room for future sibling report categories per env (e.g. `DataDog/Production/DB_Performance/`). A staging sweep can never add noise to production stats or vice versa. If files from an older skill layout exist (`DataDog/API_Performance/` root or `DataDog/API_Performance/{Env}/`), move them into `{Env}/API_Performance/` before proceeding (one-time migration, note it in that env's run log). Create directory trees only when you reach the write step (step 6), a run that stops early (prerequisites, resolution failure) must leave no orphan directories behind.

## Flow

### 1. Discover the window's API traffic

`aggregate_spans` over `service:{service} env:{env} @span.kind:server` for the window, grouped by `resource_name` (limit 200), computing on `@duration` (**nanoseconds!**): `COUNT`, `P50`, `P95`, `MAX`. If the response reports dropped percentile computes, retry once with the field spelled `duration`, which spelling works varies with the query shape. Run a second aggregation with ` status:error` appended to get per-resource error counts; join the two to compute error rate.

Keep only buckets whose `resource_name` starts with an HTTP verb (`GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS` + space). The two filters are both necessary: the verb-prefix rule drops framework-handler duplicates (`FooController.bar`) and db/cache spans, while `@span.kind:server` drops verb-prefixed **outbound client** spans (e.g. `GET /ext/api/v3/Document/Fees` to an external host) that would otherwise show up as phantom APIs and get their own bogus report files. If zero verb-prefixed buckets survive, drop the `@span.kind:server` filter and retry once (some tracers don't tag it), but then check surviving buckets' sampled spans for an external `peer.hostname`/`http.url` and exclude any that are outbound calls.

Display a one-screen traffic table (endpoint, hits, p50/p95 ms, error %), marking which rows breach the gate.

### 2. Gate

An API is **flagged** when, in this window:
- `p95 > latency_threshold_ms`, **or**
- `error_rate ≥ error_rate_threshold_pct` (slow OR broken both deserve a file)

Also load the set of **previously tracked** APIs (existing files in this env's `{Env}/API_Performance/`). Three populations result:
- *flagged + tracked* → refresh
- *flagged + new* → create
- *not flagged + tracked* → if it had traffic this window, re-evaluate (it may have recovered); if it had **no traffic**, leave the file completely untouched and mark "no traffic this window" only in the index.

### 3. Analyze each flagged API (parallelize)

When more than 2 APIs need analysis, fan out one subagent per API (steps 3a-4), each returning the report sections + fingerprint inputs; sanity-check each result against the actual diff/trace evidence before writing files (subagents can hallucinate). First verify the Datadog MCP tools are reachable from a subagent (they load via ToolSearch); if they are not, run the analyses inline sequentially instead.

#### 3a. Sample traces

For each flagged API (`samples_per_api` total, default 4):
- `search_datadog_spans` with `service:{service} env:{env} resource_name:"{VERB} {path}"`, sort `-@duration` → take the 2 slowest
- same query with `@duration:[{p95*0.8} TO {p95*1.2}]` → 1 "typical-slow" sample (**round to integer nanoseconds**, Datadog rejects float range bounds)
- 1 near the median (`@duration:[p50*0.8 TO p50*1.2]`, also integers)
- if the API was flagged for errors, swap one slot for a `status:error` sample

If the window has fewer hits than `samples_per_api`, use every available trace and mark the report header `(low-confidence, N={hits})`. Never confirm the repetition/cache heuristics (#1, #2) from a single trace, one request can't distinguish a legitimate cache miss from a bypassed cache; record such suspicions as hypotheses to re-check on a busier window, not as findings.

Then `get_datadog_trace` per sample. From the children of the entry span build the **breakdown**: group by `(service, operation_name or resource_name)`, sum durations, compute % of the entry-span duration, and classify each group (db / cache / outbound-http / internal compute). Note sequential-vs-parallel layout of the outbound calls (compare child start/end timestamps).

### 4. Cross-reference the code

Map the route to its handler in the working tree (search route path → controller/handler → service methods). For each significant breakdown group (≥10% of total or ≥100ms), find the code site that issues it (`file:line`): the client call, the repository/query, the cache annotation that should have prevented it.

Apply the heuristics catalog. If the `ar-api-dd-compare` skill is available (globally installed, or in this repo's `.claude/skills/`), read its catalog: it is the maintained, extended version. Otherwise use this compact copy (runtime signal → hypothesis):

1. Same outbound/DB call repeated N× in one trace → ineffective/bypassed cache or missing request-scope memoization
2. Code declares caching but trace shows a fetch every request → cache not taking effect
3. Independent outbound calls running strictly sequentially → parallelization candidate
4. Outbound call hits a public edge host while siblings use internal endpoints → wrong/slow routing
5. Live external call for data an existing sync job already lands locally → read the local store
6. Same write/read repeated far beyond the rows it touches → flush amplification / N+1
7. Auth/token acquisition inside the request hot path → token-cache candidate

Each finding needs trace evidence (counts, ms) + a code location + an estimated saving. No speculative findings, if the trace doesn't show it, it isn't a finding.

### 5. Status

Pick exactly one (first match wins):

| Status | Rule |
|---|---|
| 🔴 **Many Errors** | error rate ≥ `error_rate_threshold_pct` |
| 🚨 **Optimization Must** | p95 > 1s, **or** p95 > threshold with at least one concrete catalog finding (a fix exists) |
| ✅ **Normal** | p95 ≤ threshold **and** error rate < 1% (a tracked API that recovered) |
| ⚠️ **Needs Attention** | everything else, e.g. p95 between threshold and 1s with no concrete fix yet, or error rate in the 1%-threshold grey zone |

(⚠️ is deliberately the catch-all so every API always gets a status. Note a deliberate consequence: a sub-1s endpoint sampled at N=1 can never reach 🚨, findings require multi-trace evidence, and escalating on a single observation would be guessing. It will escalate on the first busy window that confirms a finding.)

### 6. Write / update report files

**Filename:** `{VERB}_{path}.md` with `/` → `_`, `{}` stripped, e.g. `POST_api_v1_items_id_verify.md`.

**File format:**

```markdown
<!-- ar-dd-api-performance
fingerprint: {status}|{p95_bucket}|{bottleneck_set}|{findings_ids}
last_run: {ISO timestamp}
last_changed: {ISO timestamp}
-->
# {VERB} {path}

**Status: 🚨 Optimization Must** · p95 {X}ms · {hits} hits/window · {err}% errors · window {window} ({dates}) · service {service} ({env})

## Where the time goes
| # | Call (service · operation) | Type | avg ms | % of request | Code site |
|---|---|---|---|---|---|
(one row per breakdown group ≥10% or ≥100ms, descending; note SEQUENTIAL/PARALLEL for outbound groups)

## Findings
(numbered; each: heuristic id, trace evidence, `file:line`, estimated saving, suggested fix, one sentence each)

## Sampled traces
(trace IDs + their durations, as links: https://app.datadoghq.com/apm/trace/{trace_id})

## History
| Date | Status | p95 | Change |
|---|---|---|---|
(append-only, newest first; one row per *change*, not per run; the first row is the creation: "Initial report")
```

**Change detection, the core invariant:** compute the fingerprint from
- status,
- p95 bucketed coarsely (nearest 100ms below 1s, nearest 500ms above, absorbs noise),
- the **unordered set** of bottleneck groups at ≥10% of total (capped at the 3 largest, same inclusion rule as the breakdown table), each as `service:operation` with %-of-total rounded to nearest 10%, sorted alphabetically before joining (an ordered list would churn when two similar-sized groups swap ranks between runs),
- the sorted set of finding IDs (heuristic id + code site).

If it equals the stored fingerprint → **do not touch the file** (the index records "verified, unchanged"). If it differs → rewrite the stats/breakdown/findings sections, update both timestamps, set the new status, and append one History row stating what changed (e.g. "p95 8.4s → 2.1s after {namespace}-XXX; sequential-calls finding resolved; status 🚨 → ⚠️").

### 7. Index

Rewrite `{Env}/API_Performance/_index.md` (the index of the environment being scanned) every run: a table of all tracked APIs (status, p95, error %, hits, last changed, link) sorted worst-first, plus a short run log line (`{timestamp}, {n} APIs seen, {m} flagged, {k} report files changed`). `{n}` is the count of distinct entry routes that survived BOTH step-1 filters (verb prefix + server-kind), not raw buckets, not folded client spans, so the number is comparable across runs. `{k}` counts per-API report files only, the index itself is rewritten every run by design and never counts as a change. The index is the only file that changes on a no-news run.

### 8. Persist (commit + push, automatic)

If `findings_root` lives inside a git repository, commit and push the run's changes automatically, reports are only useful if teammates and other machines can see them, and a loop that leaves work unpushed silently loses it:

```bash
cd {findings_root}
git add {relative path to Backend/DataDog/}
git commit -m "dd-api-performance: {env} sweep {YYYY-MM-DD}, {m} flagged, {k} reports changed"
git pull --rebase && git push
```

- Commit only when the run changed something (`{k}` > 0, an index update, or a migration); skip silently on a pure no-op.
- Scope the `git add` to the `Backend/DataDog/` tree, never sweep unrelated workspace changes into the commit.
- If the push fails (offline, auth), say so clearly and leave the commit local, do not retry-loop, and never force-push.
- If `findings_root` is not in a git repo, skip this step silently.

### 9. Summary to the user

End with: traffic table, flagged list with statuses, which files were created/updated/untouched, whether the findings commit was pushed, and the single worst finding of the run in one sentence.

## Portability

Copy the `ar-dd-api-performance/` folder to any repo + register in that repo's AGENTS.md. Everything project-specific comes from that repo's `.claude/skill.config` (auto-populated on first run) and its own Datadog connection. The heuristics catalog is self-contained above (with an upgrade path via `ar-api-dd-compare` when present); the verb-prefix entry-span rule and the heuristics are tracer-conventional, not stack-specific.

## Loop usage (hint, not implemented here)

Designed to be invoked daily (e.g. `/loop` or a scheduled agent). Caveat: the Datadog MCP is interactively authenticated, schedule it in a session where the MCP is connected; in headless runs the skill stops at the prerequisite check by design.
