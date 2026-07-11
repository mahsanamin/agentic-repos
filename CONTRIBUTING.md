# Contributing to the Agentic Repos

This framework is consumed by other repos via `ar-install` / `ar-upgrade`. That means every change here is shipped to all installed projects on their next upgrade, small, intentional commits matter more than usual.

## Where to make changes

| You want to… | Edit |
|---|---|
| Change a workflow skill (e.g. `ar-taskflow`) | `skills/<name>/SKILL.md` |
| Change a workspace-only skill | `workspace-skills/<name>/SKILL.md` |
| Change a reusable agent | not here: agents live in `agentic-devkit` (`a_sag_*`) |
| Change a coding rule shipped to targets | `rules/<platform>/<rule>.md` |
| Change a framework-operational command (installer) | `.claude/commands/<name>/SKILL.md` |
| Change a global helper script | `scripts/<area>/...` |
| Update the install/upgrade procedure | `setup.md` |

## Workflow

1. Branch off `main`.
2. Make the change.
3. Use the `ar-add-improvement` command (inside this repo) to:
   - Decide the version bump (see [`VERSIONING.md`](./VERSIONING.md)).
   - Update `config_hints.json` → `framework_version` (canonical source).
   - Update the `Version:` line in [`CLAUDE.md`](./CLAUDE.md).
   - Add a precise `CHANGELOG.md` entry, the entry **drives the incremental update**, so list affected files explicitly under `**Added:**` / `**Removed:**` / `**Changed:**`.
4. Test the change by installing into a real target project (`ar-install` for greenfield, `ar-upgrade` for incremental).
5. Open a PR. The PR description should explain *why* and link to any originating task / discussion.
6. After merge, every developer should `git pull && ./install.sh` from this repo to refresh the global layer.

## Version bumps in short

- **Patch** (`x.y.Z`): bug fixes, wording, optional additions, existing installs keep working without re-running setup.
- **Minor** (`x.Y.0`): new skills/rules, additive enhancements.
- **Major** (`X.0.0`): breaking changes, skill interfaces, schema, required structure.

Full rules in [`VERSIONING.md`](./VERSIONING.md).

## Writing skills and rules

Follow the official Claude Code authoring guidelines:

- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices)
- [How Claude Code Works](https://code.claude.com/docs/en/how-claude-code-works)

Key principles enforced by `ar-optimizer`:

- Don't document what's inferable from code.
- Avoid redundancy and rule echoes.
- Keep rules token-efficient.
- Use YAML frontmatter for skills.

## What NOT to commit

- `.claude/settings.local.json` (per-user; already gitignored).
- Anything containing project-specific identifiers (Jira namespaces, internal URLs) that aren't truly universal, those should live in the *target* project's `config_hints.json`, not in the framework source.
- Secrets, keys, or `.env` files.
