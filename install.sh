#!/usr/bin/env bash
#
# install.sh, install Agentic Repos' GLOBAL layer on this machine, in one command.
#
#   ./install.sh            Bootstrap agentic-devkit, link ar-* skills, install
#                           scripts, wire the session hook + default-branch guard,
#                           wire shell-rc, register the discovery hint.
#   ./install.sh -n         Dry run: print what would change, touch nothing.
#   ./install.sh -f         Force: repoint skill links that point elsewhere.
#   ./install.sh --no-hooks Skip wiring hooks into ~/.claude/settings.json (use
#                           this if you installed the agentic-repos plugin, which
#                           already provides the SessionStart hook + guard).
#   ./install.sh -h         Help.
#
# This installs PROCEDURE (the ar-* driver skills + scripts) globally. It does
# NOT touch any project, a repo gets its config + rules layer from `/ar-install`.
# Idempotent: safe to re-run after `git pull` to pick up new skills/scripts.
#
# Agentic Repos depends on agentic-devkit (agents, atomic skills, worktree, the
# link engine). This script REQUIRES it and bootstraps it if missing.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; DIM='\033[2m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$SCRIPT_DIR"

DRY_RUN=false
FORCE=false
NO_HOOKS=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=true ;;
    -f|--force)   FORCE=true ;;
    --no-hooks)   NO_HOOKS=true ;;
    -h|--help)    sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'; exit 0 ;;
    *) echo -e "${RED}Unknown arg: $1${NC}"; exit 1 ;;
  esac
  shift
done

say()  { echo -e "$@"; }
step() { echo -e "\n${BLUE}==>${NC} $*"; }
# Execute argv directly (never eval). In dry-run, print a shell-safe rendering.
run()  { if $DRY_RUN; then printf '  would run:'; printf ' %q' "$@"; echo; else "$@"; fi; }

command -v jq >/dev/null 2>&1 || { echo -e "${RED}jq is required. brew install jq${NC}" >&2; exit 1; }
[ -d "$FRAMEWORK_DIR/skills" ] || { echo -e "${RED}$FRAMEWORK_DIR is not the Agentic Repos root${NC}" >&2; exit 1; }

say "${BLUE}Agentic Repos, global install${NC} ${DIM}($FRAMEWORK_DIR)${NC}"
$DRY_RUN && say "${YELLOW}(dry run, nothing will change)${NC}"

# ---------------------------------------------------------------------------
# 1. Dependency: agentic-devkit (agents, atomic skills, worktree, link engine)
#    Locate it, or clone it, then run its own install.sh.
# ---------------------------------------------------------------------------
step "Dependency: agentic-devkit"
DEVKIT_DIR="${AGENTIC_DEVKIT_DIR:-}"
if [ -z "$DEVKIT_DIR" ]; then
  for cand in "$(dirname "$FRAMEWORK_DIR")/agentic-devkit" "$HOME/agentic-devkit" "$HOME/Repos/agentic-devkit"; do
    [ -f "$cand/install.sh" ] && { DEVKIT_DIR="$cand"; break; }
  done
fi
if [ -z "$DEVKIT_DIR" ]; then
  DEVKIT_DIR="$(dirname "$FRAMEWORK_DIR")/agentic-devkit"
  say "  ${YELLOW}not found, cloning${NC} agentic-devkit -> ${DIM}$DEVKIT_DIR${NC}"
  run git clone https://github.com/mahsanamin/agentic-devkit "$DEVKIT_DIR"
else
  say "  ${GREEN}found${NC} ${DIM}$DEVKIT_DIR${NC}"
fi
if [ -f "$DEVKIT_DIR/install.sh" ]; then
  say "  running its installer (links devkit agents + atomic skills + worktree)"
  run bash "$DEVKIT_DIR/install.sh" --link-only
elif ! $DRY_RUN; then
  say "  ${RED}warn:${NC} $DEVKIT_DIR/install.sh missing, devkit agents/skills may be absent"
fi
# Verify devkit actually linked what the ar-* skills invoke by name. Warn loudly
# (not fatal, since a devkit fork may name things differently), so a plugin-only
# or partial setup does not fail silently at runtime.
if ! $DRY_RUN && [ ! -e "$HOME/.claude/agents/a_sag_code_reviewer.md" ] && [ ! -e "$HOME/.claude/skills/a_sk_pr" ]; then
  say "  ${YELLOW}warn:${NC} devkit agents/skills not detected under ~/.claude (expected a_sag_*/a_sk_*)."
  say "  ${YELLOW}      ${NC} ar-* skills call devkit by name and will fail at runtime without it."
  say "  ${YELLOW}      ${NC} Fix: cd \"$DEVKIT_DIR\" && ./install.sh"
fi

# ---------------------------------------------------------------------------
# 2. Link ar-* skills globally (symlinks -> edit here = live everywhere).
#    Auto-discovers every skills/<dir>/SKILL.md. No per-repo copy.
# ---------------------------------------------------------------------------
step "Skills (~/.claude/skills/ -> symlinks into this repo)"
run mkdir -p "$HOME/.claude/skills"
for d in "$FRAMEWORK_DIR"/skills/*/; do
  [ -f "$d/SKILL.md" ] || continue
  name="$(basename "$d")"
  target="$HOME/.claude/skills/$name"
  if [ -L "$target" ] && [ "$(readlink "$target")" = "${d%/}" ]; then
    say "  ${GREEN}●${NC} $name ${DIM}(linked)${NC}"; continue
  fi
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    if $FORCE; then run rm -rf "$target"; else
      say "  ${YELLOW}▲${NC} $name, a real dir exists at target; re-run with -f to replace"; continue
    fi
  fi
  run ln -sfn "${d%/}" "$target"
  say "  ${GREEN}linked${NC} $name"
done

# ---------------------------------------------------------------------------
# 3. Install framework scripts (freshness, sonarqube fetch, session hook + guard).
#    Symlink the script dirs so they stay live on git pull.
# ---------------------------------------------------------------------------
step "Scripts (~/.claude/scripts/)"
run mkdir -p "$HOME/.claude/scripts"
for sd in ar-freshness ar-sonarqube ar-session; do
  src="$FRAMEWORK_DIR/scripts/$sd"
  [ -d "$src" ] || continue
  starget="$HOME/.claude/scripts/$sd"
  # Guard: a real (non-symlink) dir at the target would make `ln -sfn` nest a
  # link INSIDE it (~/.claude/scripts/ar-session/ar-session), silently breaking
  # the hook script paths. Replace it under -f, else warn and skip.
  if [ -e "$starget" ] && [ ! -L "$starget" ]; then
    if $FORCE; then run rm -rf "$starget"; else
      say "  ${YELLOW}▲${NC} $sd, a real dir exists at target; re-run with -f to replace"; continue
    fi
  fi
  run ln -sfn "$src" "$starget"
  $DRY_RUN || chmod +x "$src"/*.sh 2>/dev/null || true
  say "  ${GREEN}linked${NC} $sd"
done

# ---------------------------------------------------------------------------
# 4. Wire the SessionStart hook + default-branch guard into ~/.claude/settings.json.
#    Global so every session, in every repo, follows the agent-ready workflow and
#    is protected, no per-repo copy required. Idempotent (keyed by script path).
# ---------------------------------------------------------------------------
step "Hooks (~/.claude/settings.json: SessionStart + default-branch guard)"
SETTINGS="$HOME/.claude/settings.json"
SESSION_CMD="bash \"\$HOME/.claude/scripts/ar-session/session-start.sh\""
GUARD_CMD="bash \"\$HOME/.claude/scripts/ar-session/guard-default-branch.sh\""
if $NO_HOOKS; then
  say "  ${DIM}skipped (--no-hooks): the agentic-repos plugin provides these hooks${NC}"
elif $DRY_RUN; then
  say "  ${DIM}would ensure${NC} SessionStart -> session-start.sh and PreToolUse(Bash) -> guard-default-branch.sh in $SETTINGS"
else
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  tmp="$(mktemp)"
  jq --arg sc "$SESSION_CMD" --arg gc "$GUARD_CMD" '
    .hooks //= {} |
    .hooks.SessionStart //= [] |
    .hooks.PreToolUse //= [] |
    (if ([.hooks.SessionStart[]?.hooks[]?.command] | index($sc)) then .
     else .hooks.SessionStart += [{"hooks":[{"type":"command","command":$sc}]}] end) |
    (if ([.hooks.PreToolUse[]?.hooks[]?.command] | index($gc)) then .
     else .hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":$gc}]}] end)
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  say "  ${GREEN}wired${NC} SessionStart + PreToolUse guard"
fi

# ---------------------------------------------------------------------------
# 5. Wire shell-rc: export AR_FRAMEWORK_DIR + source the freshness check.
# ---------------------------------------------------------------------------
step "Shell-rc (AR_FRAMEWORK_DIR + freshness check)"
RC_FILE="$HOME/.zshrc"; [[ "${SHELL:-}" == */bash ]] && RC_FILE="$HOME/.bashrc"
MARKER_START="# >>> Agentic Repos (managed by install.sh) >>>"
MARKER_END="# <<< Agentic Repos <<<"
if $DRY_RUN; then
  say "  ${DIM}would wire${NC} $RC_FILE"
else
  touch "$RC_FILE"
  s=$(grep -cF "$MARKER_START" "$RC_FILE" || true); e=$(grep -cF "$MARKER_END" "$RC_FILE" || true)
  if [ "$s" -ne "$e" ]; then
    say "  ${RED}unbalanced markers in $RC_FILE, fix manually, skipping${NC}"
  else
    if [ "$s" -gt 0 ]; then
      t="$(mktemp)"; awk -v a="$MARKER_START" -v b="$MARKER_END" '$0==a{k=1;next} $0==b{k=0;next} !k' "$RC_FILE" > "$t" && mv "$t" "$RC_FILE"
    fi
    {
      echo ""; echo "$MARKER_START"
      printf 'export AR_FRAMEWORK_DIR=%q\n' "$FRAMEWORK_DIR"
      # Export the devkit dir too, so runtime skills can find its worktree
      # helpers without relying on the interactive shell being sourced.
      printf 'export AGENTIC_DEVKIT_DIR=%q\n' "$DEVKIT_DIR"
      echo '[ -f "$HOME/.claude/scripts/ar-freshness/check.sh" ] && source "$HOME/.claude/scripts/ar-freshness/check.sh"'
      echo "$MARKER_END"
    } >> "$RC_FILE"
    say "  ${GREEN}wired${NC} $RC_FILE ${DIM}(source it or open a new terminal)${NC}"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Framework state snapshot (consumed by ar-freshness/check.sh).
# ---------------------------------------------------------------------------
step "State snapshot (~/.claude/.agentic-repos-state.json)"
if ! $DRY_RUN; then
  HEAD_SHA="$(git -C "$FRAMEWORK_DIR" log -1 --format=%H -- . 2>/dev/null || echo unknown)"
  SKILLS_JSON="$(for d in "$FRAMEWORK_DIR"/skills/*/; do [ -f "$d/SKILL.md" ] && basename "$d"; done | jq -R . | jq -sc .)"
  cat > "$HOME/.claude/.agentic-repos-state.json" <<EOF
{ "framework_path": "$FRAMEWORK_DIR", "framework_sha": "$HEAD_SHA", "installed_at_epoch": $(date +%s), "global_skills": $SKILLS_JSON }
EOF
  rm -f "$HOME/.claude/.ar-last-freshness-check" 2>/dev/null || true
  say "  ${GREEN}wrote${NC} state"
fi

# ---------------------------------------------------------------------------
# 7. Hints file + global CLAUDE.md discovery pointer.
# ---------------------------------------------------------------------------
step "Discovery hint (~/.claude/ar-framework-hints.md + ~/.claude/CLAUDE.md)"
if ! $DRY_RUN; then
  cp "$FRAMEWORK_DIR/templates/ar-framework-hints.md" "$HOME/.claude/ar-framework-hints.md" 2>/dev/null && say "  ${GREEN}installed${NC} ar-framework-hints.md"
  if [ "${AR_SKIP_GLOBAL_HINT:-0}" != "1" ]; then
    GC="$HOME/.claude/CLAUDE.md"; HS="<!-- >>> Agentic Repos hint (managed by install.sh) >>> -->"; HE="<!-- <<< Agentic Repos hint <<< -->"
    touch "$GC"
    if [ "$(grep -cF "$HS" "$GC" || true)" -eq "$(grep -cF "$HE" "$GC" || true)" ]; then
      if grep -qF "$HS" "$GC"; then t="$(mktemp)"; awk -v a="$HS" -v b="$HE" '$0==a{k=1;next} $0==b{k=0;next} !k' "$GC" > "$t" && mv "$t" "$GC"; fi
      {
        echo ""; echo "$HS"
        echo "Agentic Repos is installed. Read \`~/.claude/ar-framework-hints.md\` for the catalog of global \`ar-*\` skills and helpers. In any repo that has \`config_hints.json\`/\`AGENTS.md\`, follow its agent-ready workflow: read the project rules, drive real work through \`ar-taskflow\`, never commit on the default branch, and capture friction with \`ar-record-improvement\`."
        echo "$HE"
      } >> "$GC"
      say "  ${GREEN}registered${NC} global CLAUDE.md pointer"
    else
      say "  ${YELLOW}unbalanced hint markers in $GC, skipping${NC}"
    fi
  fi
fi

say "\n${GREEN}Done.${NC} ${DIM}Global procedure linked. Run ${NC}/ar-install${DIM} inside a repo to give it the config + rules layer.${NC}"
say "${DIM}Restart Claude Code (or start a new session) to pick up new skills + the session hook.${NC}"
