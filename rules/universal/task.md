---
alwaysApply: false
---
# Development Task Guidelines

**For the complete task workflow, use the `ar-taskflow` skill.**

Say "ar-taskflow" to start a structured development workflow with:
- Ticket-first or ticket-late approach
- Phase-based progression (Understand → Plan → Code → Document)
- Automatic task tracking and archiving

## Quick Reference

This file contains quick guidelines that `ar-taskflow` references.

### Branch Naming

Format: `feature/{namespace}-<ticket>-<short-description>`

Examples:
- `feature/svc-183-simplify-verify-api`
- `feature/{namespace}-204-fix-payment-mapping`

### Never Fabricate Data

If implementation requires:
- Configuration data (URLs, API keys, mappings)
- Business rules or domain-specific logic
- Integration details (endpoints, schemas)
- Any data not in the codebase

**STOP and ASK** the user before implementing.

### Git Safety

- Never commit directly to `main`
- Never use `git add .` or `git add -A`
- Stage only files intentionally edited for the task
- Reference JIRA ticket in commit message
- Never bypass with `--no-verify`

### Testing Before Commit

Run the project's test suite before committing. Check AGENTS.md for the correct test command for your platform.

### Coding Standards

Follow your project's coding standards in the configured standards directory. Check AGENTS.md for the list of applicable rule files.
