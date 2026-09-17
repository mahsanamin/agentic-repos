# Codex support

Agentic Repos runs on Codex as well as Claude Code. Both harnesses read the same skills and are held
to the same protected-branch policy, because both point at the same files. There is no second copy of
anything.

## How it is wired

| Thing | Claude Code | Codex |
|---|---|---|
| Skills | `~/.claude/skills/ar-*` | `~/.agents/skills/ar-*` |
| Agents | `~/.claude/agents/` (from agentic-devkit) | `~/.codex/agents/*.toml` (rendered from the same devkit sources) |
| Scripts | `~/.claude/scripts/` | `~/.codex/scripts/` |
| Discovery hint | `~/.claude/ar-framework-hints.md` | `~/.codex/ar-framework-hints.md` |
| Instructions | `~/.claude/CLAUDE.md` block | `~/.codex/AGENTS.md` block |
| Git guard | `PreToolUse` in `~/.claude/settings.json` | `PreToolUse` in the repo's `.codex/hooks.json` |

Both skill paths are **symlinks into this repository's `skills/`**. Edit a skill once and both
harnesses see the change on their next session. Nothing is generated, so nothing can drift, and there
is no mirror-check step to run before committing.

Agents are the one exception: Codex needs TOML and agentic-devkit ships Markdown, so
`install-codex.sh` renders them. They are re-rendered on every run, and the devkit stays the single
source. Never hand-edit a file under `~/.codex/agents/`.

## Install

```bash
./install.sh            # Claude Code layer, and bootstraps agentic-devkit
./install-codex.sh      # Codex layer
```

Run `./install.sh` first: it is what clones and installs agentic-devkit, and `install-codex.sh`
renders its agents. Re-run both after a `git pull`. Both are idempotent.

Add a repo's own Codex layer, which is the `.codex/config.toml` posture plus the git-guard hook:

```bash
./install-codex.sh --target /absolute/path/to/repo
./install-codex.sh --target-only /absolute/path/to/repo   # leaves ~/.codex and ~/.agents alone
```

Restart Codex, or open a new thread, so it rediscovers skills and agents.

## The guard is one script, not two predicates

Claude Code and Codex both run `scripts/ar-session/guard-default-branch.sh`. Claude Code gets it from
`~/.claude/settings.json`, wired by `install.sh`; Codex gets it from the repo's `.codex/hooks.json`,
wired by `install-codex.sh`. The script reads the hook payload on stdin, which both harnesses deliver
in the same shape, and exits 2 to refuse.

That matters because a policy expressed twice is a policy that will disagree with itself. One script
means one behaviour and one regression suite:

```bash
bash scripts/ar-lint/git-guard-cases.sh
```

What it refuses is listed at the top of the guard itself. In short: force-push anywhere,
`--force-with-lease` or a rebase onto a shared branch, whole-tree discards, `git reset --hard`,
`git clean` without a dry run, and any commit or push that would land on the repo's default branch.

If the payload cannot be read, the guard **degrades by scope**: it refuses git commands and allows
everything else with a warning. A blanket refusal would block `ls`, and a blanket allow would drop
protection on exactly the commands that need it.

## Trust the hook, or it does not run

Codex requires you to review and trust a project hook once:

1. Open `/hooks` in Codex.
2. Find the Agentic Repos protected-branch hook.
3. Trust it.

**Until you do, the hook does not run and it does not announce itself.** Only `AGENTS.md` carries the
policy, as prose. Treat a fresh Codex install as unprotected until you have confirmed the trust step.
The repository's `.codex/` layer must be trusted too.

## Permissions

`.codex/config.toml` ships `approval_policy = "on-request"` and `sandbox_mode = "workspace-write"`:
Codex edits inside the repo without asking, and prompts only to leave the sandbox (network, paths
outside the workspace). The installer writes those two keys only when the file sets neither, so a
project that has chosen its own posture keeps it.

## Rendered agents

| Claude tier | Codex model | Reasoning effort |
|---|---|---|
| `haiku` | `gpt-5.6-luna` | medium |
| `sonnet` | `gpt-5.6-terra` | medium |
| `opus` | `gpt-5.6` | high |

An agent whose `model:` is absent or unrecognised gets no model key and inherits the parent Codex
session's model and effort.

Sandbox mode is derived from the agent's declared tools: an agent that can run `Bash` or write files
gets `workspace-write`, everything else is `read-only`. A read-only sandbox would prompt or fail on
every build, `git` or `gh` call such an agent makes.

`background: true` survives as an instruction in the agent's prompt, because Codex has no
custom-agent `background` key. MCP configuration is inherited from the parent session; an agent whose
tools include `ToolSearch` is told to use the inherited servers and to report an unavailable
integration rather than invent a result.

## Reading a Claude-worded skill

The `ar-*` skills are written once for both harnesses, so some of them use Claude's vocabulary. On
Codex, translate it:

- "Task subagent" or `subagent_type` means spawn the matching custom agent from `~/.codex/agents/`.
  Where none matches, spawn a bounded default subagent carrying that agent's instructions.
- "Launch these agents in parallel" means spawn them concurrently, wait for every result, and
  synthesize in the parent thread.
- A foreground agent is awaited before the next dependent step.
- A background test run uses Codex's non-blocking process support with a bounded timeout.
- A path under `.claude/` is compatibility data. It is never an instruction to run `claude`,
  `claude init`, or `claude mcp`. Use `/init` and `codex mcp`.

## Verify

```bash
./install-codex.sh --check-only
```

This syntax-checks the shipped scripts, runs every `scripts/ar-lint/*-cases.sh` suite, and asserts
the `.codex/hooks.json` matcher is `^Bash$`. It installs nothing.

The hook contract (the `PreToolUse` event, the `Bash` tool name, and `tool_input.command`) is fixed by
Codex's own hooks documentation. `codex-install-cases.sh` asserts the registered event and matcher, so
a change on this side fails a test. It cannot detect a rename on Codex's side: re-read the hooks
documentation when bumping the pinned CLI.
