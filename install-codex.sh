#!/usr/bin/env bash
#
# install-codex.sh, install Agentic Repos' GLOBAL layer for Codex on this machine.
#
#   ./install-codex.sh                 Link ar-* skills for Codex, render devkit
#                                      agents, install scripts + hints, wire
#                                      ~/.codex/AGENTS.md and config.toml.
#   ./install-codex.sh -n              Dry run: print what would change, touch nothing.
#   ./install-codex.sh -f              Force: replace a real dir sitting at a link target.
#   ./install-codex.sh --target PATH   Also write PATH's repo-local .codex layer
#                                      (config.toml + the PreToolUse git-guard hook).
#   ./install-codex.sh --target-only PATH
#                                      ONLY that repo. Leaves ~/.codex, ~/.agents and
#                                      ~/.claude untouched.
#   ./install-codex.sh --check-only    Run the shell checks, install nothing.
#   ./install-codex.sh -h              Help.
#
# This is the Codex half of ./install.sh, and the two are deliberately symmetrical.
# Both link the SAME skills/ directory, and both register the SAME guard script.
# There is no generated mirror of the skills for Codex to fall out of step with,
# because there is no second copy: ~/.claude/skills and ~/.agents/skills point at
# one source. Edit skills/ and both harnesses see it.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; DIM='\033[2m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$SCRIPT_DIR"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
AGENTS_HOME="$HOME/.agents"

DRY_RUN=false; FORCE=false; CHECK_ONLY=false; TARGET=""; TARGET_ONLY=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--dry-run)  DRY_RUN=true ;;
    -f|--force)    FORCE=true ;;
    --check-only)  CHECK_ONLY=true ;;
    --target)      shift; TARGET="${1:-}" ;;
    --target-only) shift; TARGET="${1:-}"; TARGET_ONLY=true ;;
    -h|--help)     sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'; exit 0 ;;
    *) echo -e "${RED}Unknown arg: $1${NC}"; exit 1 ;;
  esac
  shift
done

say()  { echo -e "$@"; }
step() { echo -e "\n${BLUE}==>${NC} $*"; }
run()  { if $DRY_RUN; then printf '  would run:'; printf ' %q' "$@"; echo; else "$@"; fi; }

command -v jq >/dev/null 2>&1 || { echo -e "${RED}jq is required. brew install jq${NC}" >&2; exit 1; }
[ -d "$FRAMEWORK_DIR/skills" ] || { echo -e "${RED}$FRAMEWORK_DIR is not the Agentic Repos root${NC}" >&2; exit 1; }
$TARGET_ONLY && [ -z "$TARGET" ] && { echo -e "${RED}--target-only needs a path${NC}" >&2; exit 1; }

GUARD_SRC="$FRAMEWORK_DIR/scripts/ar-session/guard-default-branch.sh"

# ---------------------------------------------------------------------------
# --check-only: prove the pieces hold together, install nothing.
# ---------------------------------------------------------------------------
if $CHECK_ONLY; then
  step "Checks"
  rc=0
  for f in "$GUARD_SRC" "$FRAMEWORK_DIR/scripts/ar-session/session-start.sh"; do
    bash -n "$f" && say "  ${GREEN}ok${NC} syntax $(basename "$f")" || { say "  ${RED}FAIL${NC} syntax $f"; rc=1; }
  done
  # codex-install-cases.sh drives THIS installer, so running it from here would
  # re-enter --check-only forever. The guard lets that suite call the installer
  # while stopping the installer from calling the suite back.
  for c in "$FRAMEWORK_DIR"/scripts/ar-lint/*-cases.sh; do
    [ -f "$c" ] || continue
    if [ "${AR_CHECK_RUNNING:-0}" = 1 ]; then
      say "  ${DIM}skip${NC} $(basename "$c") (already inside a check run)"; continue
    fi
    if AR_CHECK_RUNNING=1 bash "$c" >/dev/null 2>&1; then say "  ${GREEN}ok${NC} $(basename "$c")"
    else say "  ${RED}FAIL${NC} $(basename "$c") (re-run it directly to see why)"; rc=1; fi
  done
  if [ -f "$FRAMEWORK_DIR/.codex/hooks.json" ]; then
    m=$(jq -r '.hooks.PreToolUse[0].matcher // empty' "$FRAMEWORK_DIR/.codex/hooks.json")
    [ "$m" = '^Bash$' ] && say "  ${GREEN}ok${NC} .codex/hooks.json matcher is ^Bash\$" \
      || { say "  ${RED}FAIL${NC} .codex/hooks.json matcher is '$m', expected ^Bash\$"; rc=1; }
  fi
  [ "$rc" -eq 0 ] && say "\n${GREEN}All checks passed.${NC}" || say "\n${RED}Checks failed.${NC}"
  exit "$rc"
fi

say "${BLUE}Agentic Repos, Codex install${NC} ${DIM}($FRAMEWORK_DIR)${NC}"
$DRY_RUN && say "${YELLOW}(dry run, nothing will change)${NC}"

# Claude model tiers -> Codex model + reasoning effort. An agent whose model is
# unset or unrecognised inherits the parent Codex session's model, so no key is
# written for it. Keep in step with docs/CODEX.md.
codex_model_for() {
  case "$1" in
    haiku)  echo 'gpt-5.6-luna medium' ;;
    sonnet) echo 'gpt-5.6-terra medium' ;;
    opus)   echo 'gpt-5.6 high' ;;
    *)      echo '' ;;
  esac
}

# Front-matter field of a devkit agent file ("tools: Read, Bash" -> "Read, Bash").
agent_field() { sed -n "1,/^---$/!d; s/^$1:[[:space:]]*//p" "$2" 2>/dev/null | head -1; }
agent_body()  { awk 'BEGIN{n=0} /^---$/{n++; next} n>=2' "$1" 2>/dev/null; }

# Render one devkit agent (a flat <name>.md with YAML front matter) as a Codex
# custom agent. Read-only is the default; an agent that can run a command or
# write a file needs workspace-write, or every build it runs prompts.
render_agent() {
  local src="$1" dst="$2" name desc tools model sandbox pair cm re tmp
  name=$(basename "$src" .md)
  desc=$(agent_field description "$src"); [ -n "$desc" ] || desc="Agentic Repos agent: $name"
  tools=$(agent_field tools "$src")
  model=$(agent_field model "$src")
  sandbox="read-only"
  printf '%s' "$tools" | grep -Eq '(^|[,[:space:]])(Write|Edit|Bash)([,[:space:]]|$)' && sandbox="workspace-write"
  pair=$(codex_model_for "$model"); cm="${pair%% *}"; re="${pair##* }"
  tmp=$(mktemp)
  {
    echo "You are the $name agent, invoked from an Agentic Repos workflow."
    printf '%s' "$tools" | grep -Eq '(^|[,[:space:]])ToolSearch([,[:space:]]|$)' && \
      echo "Use the MCP servers inherited from the parent Codex session for external lookups. If a server is unavailable, report that limitation rather than inventing a result."
    [ "$(agent_field background "$src")" = "true" ] && \
      echo "This role is background-oriented: the parent should spawn it without blocking independent work where the Codex client supports that."
    echo
    agent_body "$src"
  } > "$tmp"
  mkdir -p "$(dirname "$dst")"
  {
    printf 'name = %s\n' "$(jq -Rn --arg v "$name" '$v')"
    printf 'description = %s\n' "$(jq -Rn --arg v "$desc" '$v')"
    [ -n "$pair" ] && printf 'model = "%s"\nmodel_reasoning_effort = "%s"\n' "$cm" "$re"
    printf 'sandbox_mode = "%s"\n' "$sandbox"
    printf 'developer_instructions = %s\n' "$(jq -Rs . < "$tmp")"
  } > "$dst"
  rm -f "$tmp"
}

# Idempotently replace a marker-delimited block in a markdown file.
replace_block() {
  local file="$1" start="$2" end="$3" body="$4" s e t
  touch "$file"
  s=$(grep -cF "$start" "$file" || true); e=$(grep -cF "$end" "$file" || true)
  [ "$s" -ne "$e" ] && { say "  ${YELLOW}unbalanced markers in $file, skipping${NC}"; return 0; }
  if [ "$s" -gt 0 ]; then
    t=$(mktemp); awk -v a="$start" -v b="$end" '$0==a{k=1;next} $0==b{k=0;next} !k' "$file" > "$t" && mv "$t" "$file"
  fi
  # Strip trailing blank lines before re-appending. Without this the separator
  # blank line below is added afresh on every run and the file grows by one line
  # each time, which makes the whole install non-idempotent for no visible reason.
  t=$(mktemp); awk 'NF{p=NR} {l[NR]=$0} END{for(i=1;i<=p;i++) print l[i]}' "$file" > "$t" && mv "$t" "$file"
  { [ -s "$file" ] && echo ""; echo "$start"; printf '%s\n' "$body"; echo "$end"; } >> "$file"
}

# Ensure the two posture keys and [agents] exist in a config.toml, without
# disturbing a posture the project already chose for itself.
ensure_codex_config() {
  local cfg="$1"
  if $DRY_RUN; then say "  ${DIM}would ensure${NC} $cfg"; return 0; fi
  mkdir -p "$(dirname "$cfg")"; touch "$cfg"
  if grep -Eq '^[[:space:]]*(approval_policy|sandbox_mode)[[:space:]]*=' "$cfg"; then
    say "  ${DIM}kept${NC} $cfg (it already sets a posture)"
  else
    { echo '# Agentic Repos: edit inside the repo without asking, prompt only to leave the sandbox.'
      echo '# The protected-branch policy is enforced by .codex/hooks.json, not by prompts.'
      echo 'approval_policy = "on-request"'
      echo 'sandbox_mode = "workspace-write"'
    } | cat - "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
    say "  ${GREEN}wrote${NC} posture into $cfg"
  fi
  grep -q '^\[agents\]' "$cfg" || printf '\n[agents]\nenabled = true\nmax_concurrent_threads_per_session = 4\n' >> "$cfg"
}

if ! $TARGET_ONLY; then
  # -------------------------------------------------------------------------
  # 1. Dependency: agentic-devkit. Agents come from there, never from this repo.
  # -------------------------------------------------------------------------
  step "Dependency: agentic-devkit"
  DEVKIT_DIR="${AGENTIC_DEVKIT_DIR:-}"
  if [ -z "$DEVKIT_DIR" ]; then
    for cand in "$(dirname "$FRAMEWORK_DIR")/agentic-devkit" "$HOME/agentic-devkit" "$HOME/Repos/agentic-devkit"; do
      [ -d "$cand/agents" ] && { DEVKIT_DIR="$cand"; break; }
    done
  fi
  if [ -n "$DEVKIT_DIR" ] && [ -d "$DEVKIT_DIR/agents" ]; then
    say "  ${GREEN}found${NC} ${DIM}$DEVKIT_DIR${NC}"
  else
    say "  ${YELLOW}not found.${NC} Run ./install.sh first, it bootstraps the devkit."
    say "  ${YELLOW}      ${NC} Skills will still be linked; no agents will be rendered."
    DEVKIT_DIR=""
  fi

  # -------------------------------------------------------------------------
  # 2. Skills: link the SAME source ~/.claude/skills points at.
  # -------------------------------------------------------------------------
  step "Skills (~/.agents/skills/ -> symlinks into this repo)"
  run mkdir -p "$AGENTS_HOME/skills"
  for d in "$FRAMEWORK_DIR"/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    name="$(basename "$d")"; target="$AGENTS_HOME/skills/$name"
    if [ -L "$target" ] && [ "$(readlink "$target")" = "${d%/}" ]; then
      say "  ${GREEN}●${NC} $name ${DIM}(linked)${NC}"; continue
    fi
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      if $FORCE; then run rm -rf "$target"; else
        say "  ${YELLOW}▲${NC} $name, a real dir exists at target; re-run with -f to replace"; continue
      fi
    fi
    run ln -sfn "${d%/}" "$target"; say "  ${GREEN}linked${NC} $name"
  done

  # -------------------------------------------------------------------------
  # 3. Agents: render devkit agents into Codex custom agents.
  #    These ARE copies, because Codex needs TOML and the devkit ships markdown.
  #    They are regenerated on every run, so the devkit stays the one source.
  # -------------------------------------------------------------------------
  step "Agents (~/.codex/agents/*.toml, rendered from agentic-devkit)"
  if [ -n "$DEVKIT_DIR" ]; then
    run mkdir -p "$CODEX_HOME/agents"
    n=0
    for a in "$DEVKIT_DIR"/agents/*.md; do
      [ -f "$a" ] || continue
      case "$(basename "$a")" in README.md) continue ;; esac
      if $DRY_RUN; then n=$((n+1)); continue; fi
      render_agent "$a" "$CODEX_HOME/agents/$(basename "$a" .md).toml"; n=$((n+1))
    done
    say "  ${GREEN}rendered${NC} $n agents"
  else
    say "  ${DIM}skipped (no devkit)${NC}"
  fi

  # -------------------------------------------------------------------------
  # 4. Scripts: the guard and the session hook, on the Codex path too.
  # -------------------------------------------------------------------------
  step "Scripts (~/.codex/scripts/)"
  run mkdir -p "$CODEX_HOME/scripts"
  for sd in ar-freshness ar-sonarqube ar-session ar-lint; do
    src="$FRAMEWORK_DIR/scripts/$sd"; [ -d "$src" ] || continue
    starget="$CODEX_HOME/scripts/$sd"
    if [ -e "$starget" ] && [ ! -L "$starget" ]; then
      if $FORCE; then run rm -rf "$starget"; else
        say "  ${YELLOW}▲${NC} $sd, a real dir exists at target; re-run with -f to replace"; continue
      fi
    fi
    run ln -sfn "$src" "$starget"; say "  ${GREEN}linked${NC} $sd"
  done

  # -------------------------------------------------------------------------
  # 5. Hints, guidance block, posture, state.
  # -------------------------------------------------------------------------
  step "Discovery (~/.codex/ar-framework-hints.md + ~/.codex/AGENTS.md)"
  if ! $DRY_RUN; then
    cp "$FRAMEWORK_DIR/templates/ar-framework-hints.md" "$CODEX_HOME/ar-framework-hints.md" 2>/dev/null \
      && say "  ${GREEN}installed${NC} ar-framework-hints.md"
    replace_block "$CODEX_HOME/AGENTS.md" \
      "<!-- >>> Agentic Repos (managed by install-codex.sh) >>> -->" \
      "<!-- <<< Agentic Repos <<< -->" \
      "Agentic Repos is installed for Codex. Skills are discoverable under \`~/.agents/skills/\`; custom agents under \`~/.codex/agents/\`. Read \`~/.codex/ar-framework-hints.md\` for the catalog.

In any repo carrying \`config_hints.json\` or \`AGENTS.md\`: read the project's rules before writing code, drive real work through \`ar-taskflow\`, never commit or push on the default branch, and capture friction with \`ar-record-improvement\`.

Where a shared skill uses Claude phrasing, translate it: \"Task subagent\" or \`subagent_type\` means spawn the matching custom agent from \`~/.codex/agents/\`; \"launch agents in parallel\" means spawn them concurrently and synthesize their results in this thread; a foreground agent is awaited before the next dependent step. Paths under \`.claude/\` are compatibility data, never an instruction to run \`claude\`."
    say "  ${GREEN}registered${NC} ~/.codex/AGENTS.md block"
  fi

  step "Posture + state"
  ensure_codex_config "$CODEX_HOME/config.toml"
  if ! $DRY_RUN; then
    HEAD_SHA="$(git -C "$FRAMEWORK_DIR" log -1 --format=%H -- . 2>/dev/null || echo unknown)"
    VERSION="$(jq -r '.framework_version // "unknown"' "$FRAMEWORK_DIR/config_hints.json" 2>/dev/null || echo unknown)"
    cat > "$CODEX_HOME/.agentic-repos-state.json" <<EOF
{ "framework_path": "$FRAMEWORK_DIR", "framework_version": "$VERSION", "framework_sha": "$HEAD_SHA", "installed_at_epoch": $(date +%s) }
EOF
    say "  ${GREEN}wrote${NC} ~/.codex/.agentic-repos-state.json"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Repo-local Codex layer: posture + the PreToolUse git guard.
#    The guard is the SAME script Claude Code runs. No bridge, no second
#    predicate to keep in step, because there is only one predicate.
# ---------------------------------------------------------------------------
if [ -n "$TARGET" ]; then
  step "Target repo ($TARGET)"
  [ -d "$TARGET/.git" ] || { echo -e "${RED}$TARGET is not a git repository${NC}" >&2; exit 1; }
  ensure_codex_config "$TARGET/.codex/config.toml"
  if $DRY_RUN; then
    say "  ${DIM}would register${NC} the PreToolUse git guard in $TARGET/.codex/hooks.json"
  else
    mkdir -p "$TARGET/.codex"
    hooks="$TARGET/.codex/hooks.json"
    [ -f "$hooks" ] || echo '{"description":"Agentic Repos repository safety hooks for Codex.","hooks":{}}' > "$hooks"
    # Prefer a guard the repo carries itself, so the hook works before any global
    # install (this framework repo is the case that matters). Otherwise use the
    # globally installed one, which is where a normal target project finds it.
    if [ -f "$TARGET/scripts/ar-session/guard-default-branch.sh" ]; then
      gcmd='bash "$(git rev-parse --show-toplevel)/scripts/ar-session/guard-default-branch.sh"'
    else
      gcmd='bash "$HOME/.claude/scripts/ar-session/guard-default-branch.sh"'
    fi
    tmp=$(mktemp)
    # Keyed on the command, so re-running never duplicates it, and any hook the
    # project added itself is preserved.
    jq --arg c "$gcmd" '
      .hooks //= {} | .hooks.PreToolUse //= [] |
      if ([.hooks.PreToolUse[]?.hooks[]?.command] | index($c)) then .
      else .hooks.PreToolUse += [{"matcher":"^Bash$","hooks":[{"type":"command","command":$c,"timeout":10,"statusMessage":"Checking protected-branch policy"}]}]
      end' "$hooks" > "$tmp" && mv "$tmp" "$hooks"
    say "  ${GREEN}registered${NC} PreToolUse git guard in .codex/hooks.json"
  fi
  say "  ${YELLOW}note:${NC} Codex requires you to trust a project hook once. Open ${DIM}/hooks${NC},"
  say "  ${YELLOW}     ${NC} inspect the Agentic Repos guard, and trust it. ${RED}Until you do, the${NC}"
  say "  ${YELLOW}     ${NC} ${RED}hook does not run and protected-branch enforcement is OFF.${NC}"
fi

say "\n${GREEN}Done.${NC} ${DIM}Restart Codex or open a new thread to rediscover skills and agents.${NC}"
