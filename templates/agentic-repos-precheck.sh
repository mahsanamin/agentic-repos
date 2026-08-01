#!/usr/bin/env bash
# Agentic Repos: global-layer precheck (committed per-repo, opt-in).
#
# The ar-* driver skills, the devkit agents, and the global SessionStart/guard
# hooks are a per-machine layer that is NOT committed into a repo. A teammate who
# clones this repo without that layer gets none of it, and nothing signals the
# gap. This hook is the signal. It self-silences the moment the layer is present,
# so it never double-fires with the global hooks.
#
# Wiring (in this repo's .claude/settings.json):
#   SessionStart               -> bash .../agentic-repos-precheck.sh          (advisory, exit 0)
#   PreToolUse(Edit|Write|...) -> bash .../agentic-repos-precheck.sh --block  (exit 2 until installed)
#
# Usage: agentic-repos-precheck.sh [--block]

set -u

BLOCK=0
[ "${1:-}" = "--block" ] && BLOCK=1

CLAUDE_HOME="${HOME}/.claude"

# ar-* driver skills: install.sh symlinks them into ~/.claude/skills; the plugin
# ships them under ~/.claude/plugins. Detect either path.
skills_present() {
  [ -e "${CLAUDE_HOME}/skills/ar-taskflow" ] && return 0
  [ -d "${CLAUDE_HOME}/plugins" ] \
    && find "${CLAUDE_HOME}/plugins" -maxdepth 6 -type d -name ar-taskflow 2>/dev/null | grep -q . \
    && return 0
  return 1
}

# agentic-devkit (a_sag_* agents, a_sk_* atomic skills, worktree helpers). The
# plugin does NOT ship it, so a plugin-only install is incomplete.
devkit_present() {
  [ -f "${CLAUDE_HOME}/agents/a_sag_code_reviewer.md" ]
}

# Complete layer present -> stay silent.
skills_present && devkit_present && exit 0

msg=$(
  echo "──────────────────────────────────────────────────────────────"
  echo "⚠  Agentic Repos global layer not detected on this machine."
  echo
  if ! skills_present; then
    echo "This repo is agent-ready, but the ar-* driver skills, devkit agents, and"
    echo "session guards live in a per-machine layer that is not committed here."
    echo "Install it once, then reopen this repo:"
    echo
    echo "  Plugin (ar-* skills + hooks only):"
    echo "    /plugin marketplace add mahsanamin/agentic-repos"
    echo "    /plugin install agentic-repos"
    echo
    echo "  Complete layer (recommended - also installs agentic-devkit + shell helpers):"
    echo "    git clone https://github.com/mahsanamin/agentic-repos"
    echo "    cd agentic-repos && ./install.sh"
  else
    echo "The Claude Code plugin ships the ar-* skills + hooks but NOT agentic-devkit"
    echo "(the a_sag_* agents, a_sk_* atomic skills, and worktree helpers the ar-*"
    echo "skills call at runtime). Install the complete layer:"
    echo
    echo "    git clone https://github.com/mahsanamin/agentic-repos"
    echo "    cd agentic-repos && ./install.sh"
  fi
  echo "──────────────────────────────────────────────────────────────"
)

if [ "$BLOCK" -eq 1 ]; then
  printf '%s\n' "$msg" >&2
  exit 2
fi

printf '%s\n' "$msg"
exit 0
