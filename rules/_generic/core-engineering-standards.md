---
alwaysApply: false
---
# Core Engineering Standards (language-neutral)

Fallback rule set for any stack without a curated `rules/<stack>/`. Language-neutral, it states *what* to check; the project's actual idioms come from the code itself. Installed when no per-stack rules apply; superseded per-topic by a curated stack rule when one exists.

## Endpoints / API
- Reconstruct each endpoint's full path from how this codebase declares routes (router, decorator, annotation, config, whatever it uses). Verify request/response shapes against the actual handler.
- Validate and bound all client input at the boundary.

## Data access & transactions
- Keep a transaction/connection open only for the work that needs it, never across an external network call.
- No query inside a loop where a batch/set-based fetch is possible (N+1).
- Schema changes ship with a migration; never assume production has an un-migrated column/value.

## Error handling
- Don't swallow errors; wrap with context as they propagate. Fail loudly at boundaries, not silently mid-flow.
- Distinguish expected (handled) from unexpected (surfaced) errors.

## Observability
- Instrument the paths that matter (counts, latency, failures); keep metric/log naming consistent with siblings. Logging/metrics must not block or be inside a hot transaction.

## Security
- Never log secrets/tokens/PII. Authenticate/authorize at the boundary. Validate before trusting.

## Structure & conventions
- Place new code per the project's existing module/package layout; respect layer direction.
- Mirror the nearest existing code's naming and patterns, match the codebase, don't impose a foreign style.

## Tests
- Follow `test-change-policy.md`: behaviour-preserving changes leave existing tests untouched (they're the regression oracle); contract/feature changes update only what the contract delta invalidates.
- Run the project's own test command (from `config_hints.json` / repo docs); never assume a build tool.
