# Commit Message Template

## Format

```
{Short summary - what changed and why, max 72 chars}

{Optional 1-2 sentences of tech context if it adds value.}
```

## Guidelines

- First line: readable by anyone (product, QA, engineer)
- Body: brief tech context, what components/files changed, only if helpful
- Keep it under 3 lines total
- No checklists, no bullet lists of files
- No conventional commit prefixes (feat:, fix:) unless the repo uses them
- No ticket numbers unless explicitly asked
- No tool or assistant attribution trailers; commits are authored by the developer

## Examples

```
Fix payment failure when user switches currency mid-checkout

Updated currency conversion to lock rate at cart creation.
Affects PaymentService and CurrencyProxy.
```

```
Add support service provider filtering by country

New endpoint GET /support-services?country=GB with a spec filter.
```

```
Bump the web framework to the latest patch for a security fix
```
