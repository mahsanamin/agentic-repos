---
name: ar-install-tools
description: Install or refresh the global Agentic Repos layer on this machine (ar-* skills, scripts, session hook, default-branch guard). Say "ar-install-tools" or "setup tools".
disable-model-invocation: true
---

# Install Global Tools

Installs (or refreshes) the GLOBAL Agentic Repos layer on this developer's machine: the `ar-*` driver skills, framework scripts, the SessionStart hook, and the default-branch guard, all wired into `~/.claude/`.

This skill is a thin wrapper around `install.sh` at the framework repo root. The shell script is the canonical implementation and does all the work (bootstrapping agentic-devkit, symlinking skills, installing scripts, wiring hooks and shell-rc). Teammates who do not use Claude Code can run it directly.

## When to Run

- First time a developer starts using Agentic Repos (once per machine).
- After `git pull` in the framework repo picks up new skills or scripts.
- When shell startup prints "Framework is N commit(s) behind" (the freshness check telling you a teammate pushed new tools).

## Prerequisites

- `jq` installed (`brew install jq`).
- The framework repo cloned locally. `$AR_FRAMEWORK_DIR` points to it after a first install; otherwise use the repo root path.

## Steps

### 1. Run the installer

```bash
bash "${AR_FRAMEWORK_DIR:-.}/install.sh"
```

Run it from the framework root, or pass its path. That is the whole job. `install.sh` is idempotent (symlinks, not copies) so re-running only picks up what changed. It bootstraps agentic-devkit if missing.

### 2. Report the result

Surface the installer's bottom line back to the user:

```
Global Agentic Repos layer installed/refreshed.
Restart Claude Code (or start a new session) to pick up new skills + the session hook.
```

If `install.sh` reported a real dir blocking a skill symlink, tell the user to re-run with `-f`. If it warned that agentic-devkit was missing, tell them the clone step ran (or failed) so they can retry.
