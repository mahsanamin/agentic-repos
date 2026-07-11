#!/usr/bin/env bash
#
# ar-session/session-start.sh, Agentic Repos SessionStart hook.
#
# Wired into ~/.claude/settings.json by ./install.sh (or shipped as a plugin
# hook) so it fires at the start of EVERY Claude Code session, in every repo.
# Its job: when the current project is agent-ready (declares itself via
# config_hints.json / AGENTS.md), remind the session to follow the agent-ready
# workflow instead of doing ad-hoc work.
#
# Emits the modern SessionStart JSON form: hookSpecificOutput.additionalContext
# is injected into the session. Silent (empty output, exit 0) in projects that
# are not agent-ready, so it is harmless everywhere.
#
# Reads the hook payload on stdin (JSON) but only needs the cwd, which it takes
# from $CLAUDE_PROJECT_DIR (falling back to PWD).

set -euo pipefail

proj="${CLAUDE_PROJECT_DIR:-$PWD}"

# Is this project agent-ready? Look for the config seam this framework writes.
cfg=""
for c in "$proj/.claude/config_hints.json" "$proj/config_hints.json"; do
    [ -f "$c" ] && { cfg="$c"; break; }
done
[ -z "$cfg" ] && [ ! -f "$proj/AGENTS.md" ] && exit 0   # not agent-ready: stay silent

name="this project"
if [ -n "$cfg" ] && command -v jq >/dev/null 2>&1; then
    n=$(jq -r '(.project.name // .name // empty)' "$cfg" 2>/dev/null || true)
    # Clamp: a repo-supplied name goes into model-facing context, so strip
    # newlines, cap length, and keep a safe charset to blunt prompt-injection.
    n=$(printf '%s' "$n" | tr -d '\n\r' | LC_ALL=C tr -cd '[:alnum:] ._-' | cut -c1-60)
    [ -n "$n" ] && name="$n"
fi

read -r -d '' ctx <<EOF || true
[Agentic Repos] $name is an agent-ready repository. Follow its established workflow rather than improvising:
- Read AGENTS.md and the coding rules under the project's standards location before writing code. Project rules override global defaults.
- Drive any real change (a fix, a feature, a ticket) through the ar-taskflow skill (raw prompt, understand, plan, code, document, PR) rather than ad-hoc edits.
- Never commit or push on the default branch; work on a feature branch (a worktree via a_g_worktree_init is preferred).
- The moment a rule is wrong, a skill misfires, or a better default emerges, capture it with ar-record-improvement.
EOF

if command -v jq >/dev/null 2>&1; then
    jq -n --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
else
    # Fallback: plain stdout is still added to context (legacy form).
    printf '%s\n' "$ctx"
fi
exit 0
