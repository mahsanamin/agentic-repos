#!/usr/bin/env bash
#
# Contract tests for install.sh (the Claude Code global layer).
#
# Runs entirely against a disposable HOME, so it never touches the machine's real
# ~/.claude, ~/.zshrc or ~/.bashrc. Run it after any edit to install.sh:
#
#   bash scripts/ar-lint/install-cases.sh
#
# Exit 0 = all cases passed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$FW/install.sh"
[ -f "$INSTALLER" ] || { echo "FAIL: no install.sh at $INSTALLER" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf 'FAIL  %s\n' "$1"; }
want() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }

SANDBOX=$(mktemp -d); trap 'rm -rf "$SANDBOX"' EXIT
H="$SANDBOX/home"; mkdir -p "$H"

# A stand-in devkit whose installer does nothing, so these cases do not depend on
# a real clone and never reach the network.
DEVKIT="$SANDBOX/agentic-devkit"; mkdir -p "$DEVKIT/agents"
printf '#!/usr/bin/env bash\nexit 0\n' > "$DEVKIT/install.sh"; chmod +x "$DEVKIT/install.sh"

runinst() { HOME="$H" SHELL=/bin/bash AGENTIC_DEVKIT_DIR="$DEVKIT" \
              bash "$INSTALLER" "$@" >"$SANDBOX/out.log" 2>&1; }

echo "== first install =="
runinst; want $? "installer exits 0"
[ -L "$H/.claude/skills/ar-taskflow" ]; want $? "skills are symlinked, not copied"
[ "$(readlink "$H/.claude/skills/ar-taskflow")" = "$FW/skills/ar-taskflow" ]
want $? "the symlink points back at the framework's own skills/"
[ -L "$H/.claude/scripts/ar-session" ]; want $? "ar-session scripts linked"
[ -L "$H/.claude/scripts/ar-lint" ];    want $? "ar-lint scripts linked"
[ -f "$H/.claude/.agentic-repos-state.json" ]; want $? "state snapshot written"
[ -f "$H/.claude/ar-framework-hints.md" ];     want $? "hints file installed"

echo "== hooks =="
jq -e '[.hooks.SessionStart[]?.hooks[]?.command] | map(test("session-start.sh")) | any' \
  "$H/.claude/settings.json" >/dev/null; want $? "SessionStart hook wired"
jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | map(test("guard-default-branch.sh")) | any' \
  "$H/.claude/settings.json" >/dev/null; want $? "PreToolUse guard wired"
jq -e '[.hooks.PreToolUse[]?] | map(select(.matcher == "Bash")) | length >= 1' \
  "$H/.claude/settings.json" >/dev/null; want $? "the guard is matched on Bash"

echo "== idempotency: a second run must change nothing =="
cp -r "$H/.claude" "$SANDBOX/claude-before"
cp "$H/.bashrc" "$SANDBOX/bashrc-before" 2>/dev/null || touch "$SANDBOX/bashrc-before"
runinst; want $? "second run exits 0"
# The state snapshot carries an install timestamp, so it is expected to differ.
diff -r -x '.agentic-repos-state.json' "$SANDBOX/claude-before" "$H/.claude" >/dev/null 2>&1
want $? "a second run leaves ~/.claude byte-identical (no growing blocks)"
diff "$SANDBOX/bashrc-before" "$H/.bashrc" >/dev/null 2>&1
want $? "a second run leaves the shell rc byte-identical"
[ "$(grep -c 'Agentic Repos (managed by install.sh)' "$H/.bashrc")" -eq 1 ]
want $? "exactly one managed block in the shell rc"
[ "$(grep -c 'Agentic Repos hint (managed by install.sh)' "$H/.claude/CLAUDE.md")" -eq 1 ]
want $? "exactly one hint block in the global CLAUDE.md"
[ "$(jq '[.hooks.PreToolUse[]?.hooks[]?.command] | map(select(test("guard-default-branch.sh"))) | length' "$H/.claude/settings.json")" -eq 1 ]
want $? "the guard hook is not registered twice"

echo "== the shell rc exports what the skills need =="
grep -q 'export AR_FRAMEWORK_DIR=' "$H/.bashrc";     want $? "AR_FRAMEWORK_DIR exported"
grep -q 'export AGENTIC_DEVKIT_DIR=' "$H/.bashrc";   want $? "AGENTIC_DEVKIT_DIR exported"

echo "== --no-hooks leaves settings alone (plugin users) =="
H2="$SANDBOX/home2"; mkdir -p "$H2"
HOME="$H2" SHELL=/bin/bash AGENTIC_DEVKIT_DIR="$DEVKIT" bash "$INSTALLER" --no-hooks >/dev/null 2>&1
want $? "--no-hooks exits 0"
[ ! -f "$H2/.claude/settings.json" ] || \
  ! jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | map(test("guard-default-branch.sh")) | any' \
    "$H2/.claude/settings.json" >/dev/null 2>&1
want $? "--no-hooks wired no guard hook"
[ -L "$H2/.claude/skills/ar-taskflow" ]; want $? "--no-hooks still linked the skills"

echo "== dry run touches nothing =="
H3="$SANDBOX/home3"; mkdir -p "$H3"
HOME="$H3" SHELL=/bin/bash AGENTIC_DEVKIT_DIR="$DEVKIT" bash "$INSTALLER" -n >/dev/null 2>&1
want $? "dry run exits 0"
[ ! -d "$H3/.claude/skills" ]; want $? "dry run created no skill links"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ] || exit 1
