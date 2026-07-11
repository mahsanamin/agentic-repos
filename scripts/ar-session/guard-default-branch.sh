#!/usr/bin/env bash
#
# ar-session/guard-default-branch.sh, Agentic Repos PreToolUse(Bash) guard.
#
# Wired globally into ~/.claude/settings.json by ./install.sh so it protects
# EVERY repo, not just ones that carry their own copy. Refusals:
#   1. Force-push in any form (--force, -f, or a leading + on a refspec).
#   2. A push whose destination is explicitly the default branch, from any local
#      branch (e.g. `push origin HEAD:main`, `push origin :master`).
#   3. commit / push while the code repo is ON its default branch (main/master/
#      origin HEAD), real work belongs on a feature branch.
#
# IMPORTANT: this is a BEST-EFFORT, defense-in-depth control. It statically
# inspects an arbitrary shell string, which cannot be made sound: a determined
# command (subshells, `bash -c`, aliases, decoy `cd`/`git -C`) can evade it. The
# AUTHORITATIVE control is server-side GitHub branch protection on the default
# branch (require a PR, block direct pushes and force-push). Treat this hook as a
# convenience seatbelt, not a security boundary.
#
# Reads the hook payload (JSON) on stdin; the command is at .tool_input.command.
# Exit 2 with a message on stderr blocks the tool call; exit 0 allows it. Only
# guards the repo rooted at $CLAUDE_PROJECT_DIR, so a commit into an unrelated
# docs/tasks repo elsewhere is unaffected.

# If jq is unavailable we cannot parse the payload; allow rather than spam an
# error on every Bash call machine-wide (the framework requires jq at install).
command -v jq >/dev/null 2>&1 || exit 0

cmd=$(jq -r '.tool_input.command' 2>/dev/null) || exit 0
[ -z "$cmd" ] && exit 0
[ "$cmd" = "null" ] && exit 0

g='(^|[;&|]|\$\(|`)[[:space:]]*git[[:space:]]+(-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?[[:space:]]+)*'

# Default-branch names to protect: the universal two plus this repo's origin/HEAD.
code=$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null)
codedef=$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
defbranches="main master"
[ -n "$codedef" ] && defbranches="$defbranches $codedef"

pushseg=$(printf '%s\n' "$cmd" | grep -oE "${g}push[^;&|]*")
if [ -n "$pushseg" ]; then
  # (1) Force in any form: --force / --force-with-lease / -f / a token starting with +
  if printf '%s\n' "$pushseg" | grep -Eq -- '--force|(^|[[:space:]])-f([[:space:]]|$)|(^|[[:space:]])\+[^[:space:]]+'; then
    echo 'Refuse: force-push (--force / -f / +refspec) is forbidden - never rewrite pushed history. If you truly must, do it manually outside the agent.' >&2
    exit 2
  fi
  # (2) Destination is explicitly the default branch (refspec dst), from any branch:
  #     HEAD:main, :main, feature:refs/heads/master, etc.
  for db in $defbranches; do
    if printf '%s\n' "$pushseg" | grep -Eq "(:|[[:space:]])(refs/heads/)?${db}([[:space:]]|\$)"; then
      echo "Refuse: pushing to the default branch ($db) is forbidden - open a PR from a feature branch. (Authoritative control: enable branch protection on $db.)" >&2
      exit 2
    fi
  done
fi

# (3) commit / push while the code repo itself is on its default branch.
if printf '%s\n' "$cmd" | grep -Eq "${g}(commit|push)([^[:alnum:]_-]|\$)"; then
  tdir=$(printf '%s\n' "$cmd" | sed -nE 's/.*(^|[;&|])[[:space:]]*(cd|git[[:space:]]+-C)[[:space:]]+([^[:space:];&|]+).*/\3/p' | head -1)
  [ -z "$tdir" ] && tdir="$PWD"
  tgt=$(git -C "$tdir" rev-parse --show-toplevel 2>/dev/null)
  br=$(git -C "$tdir" branch --show-current 2>/dev/null)
  def=$(git -C "$tdir" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
  if [ -n "$tgt" ] && [ "$tgt" = "$code" ] && { [ "$br" = main ] || [ "$br" = master ] || { [ -n "$def" ] && [ "$br" = "$def" ]; }; }; then
    echo 'Refuse: commit/push on the code repo default branch - use a feature branch (a worktree via a_g_worktree_init is preferred).' >&2
    exit 2
  fi
fi
exit 0
