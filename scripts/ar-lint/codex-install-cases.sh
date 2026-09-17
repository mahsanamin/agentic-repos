#!/usr/bin/env bash
#
# Contract tests for install-codex.sh.
#
# Everything here runs against disposable HOME / CODEX_HOME / target directories,
# so it never touches the machine's real Codex setup. Run it after any edit to
# install-codex.sh:
#
#   bash scripts/ar-lint/codex-install-cases.sh
#
# Exit 0 = all cases passed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$FW/install-codex.sh"
[ -f "$INSTALLER" ] || { echo "FAIL: no install-codex.sh at $INSTALLER" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf 'FAIL  %s\n' "$1"; }
want() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
FAKE_HOME="$SANDBOX/home"; FAKE_CODEX="$FAKE_HOME/.codex"
mkdir -p "$FAKE_HOME"

# A stand-in devkit, so these cases do not depend on a real clone being present.
DEVKIT="$SANDBOX/agentic-devkit"; mkdir -p "$DEVKIT/agents"
cat > "$DEVKIT/agents/a_sag_fake_writer.md" <<'A'
---
name: a_sag_fake_writer
description: Writes things.
tools: Read, Write, Bash
model: opus
---
Body of the writer agent.
A
cat > "$DEVKIT/agents/a_sag_fake_reader.md" <<'A'
---
name: a_sag_fake_reader
description: Reads things.
tools: ToolSearch
model: haiku
---
Body of the reader agent.
A
cat > "$DEVKIT/agents/a_sag_fake_plain.md" <<'A'
---
name: a_sag_fake_plain
description: No model pinned.
tools: Read
---
Body of the plain agent.
A
echo "not an agent" > "$DEVKIT/agents/README.md"

runinst() { HOME="$FAKE_HOME" CODEX_HOME="$FAKE_CODEX" AGENTIC_DEVKIT_DIR="$DEVKIT" \
              bash "$INSTALLER" "$@" >"$SANDBOX/out.log" 2>&1; }

echo "== global install =="
runinst; want $? "installer exits 0"

[ -L "$FAKE_HOME/.agents/skills/ar-taskflow" ]; want $? "ar-taskflow is a SYMLINK under ~/.agents/skills (not a copy)"
[ "$(readlink "$FAKE_HOME/.agents/skills/ar-taskflow")" = "$FW/skills/ar-taskflow" ]
want $? "the symlink points back at the framework's own skills/"
[ -f "$FAKE_CODEX/ar-framework-hints.md" ]; want $? "hints file installed"
grep -q "Agentic Repos is installed for Codex" "$FAKE_CODEX/AGENTS.md" 2>/dev/null
want $? "~/.codex/AGENTS.md carries the managed block"
[ -f "$FAKE_CODEX/.agentic-repos-state.json" ] && \
  [ "$(jq -r .framework_path "$FAKE_CODEX/.agentic-repos-state.json")" = "$FW" ]
want $? "state file records the framework path"
grep -q 'approval_policy = "on-request"' "$FAKE_CODEX/config.toml"; want $? "config.toml sets approval_policy"
grep -q 'sandbox_mode = "workspace-write"' "$FAKE_CODEX/config.toml"; want $? "config.toml sets sandbox_mode"
grep -q '^\[agents\]' "$FAKE_CODEX/config.toml"; want $? "config.toml declares [agents]"
[ -L "$FAKE_CODEX/scripts/ar-session" ]; want $? "scripts linked onto the Codex path"

echo "== rendered agents =="
[ -f "$FAKE_CODEX/agents/a_sag_fake_writer.toml" ]; want $? "devkit agent rendered to TOML"
[ ! -e "$FAKE_CODEX/agents/README.toml" ]; want $? "the devkit's README.md is not rendered as an agent"
grep -q 'model = "gpt-5.6"' "$FAKE_CODEX/agents/a_sag_fake_writer.toml" && \
  grep -q 'model_reasoning_effort = "high"' "$FAKE_CODEX/agents/a_sag_fake_writer.toml"
want $? "opus maps to gpt-5.6 / high"
grep -q 'model = "gpt-5.6-luna"' "$FAKE_CODEX/agents/a_sag_fake_reader.toml" && \
  grep -q 'model_reasoning_effort = "medium"' "$FAKE_CODEX/agents/a_sag_fake_reader.toml"
want $? "haiku maps to gpt-5.6-luna / medium"
! grep -q '^model = ' "$FAKE_CODEX/agents/a_sag_fake_plain.toml"
want $? "an agent with no model pinned inherits the session model (no model key)"
grep -q 'sandbox_mode = "workspace-write"' "$FAKE_CODEX/agents/a_sag_fake_writer.toml"
want $? "an agent with Write/Bash gets workspace-write"
grep -q 'sandbox_mode = "read-only"' "$FAKE_CODEX/agents/a_sag_fake_reader.toml"
want $? "an agent with no shell or write tools stays read-only"
grep -q 'inherited from the parent Codex session' "$FAKE_CODEX/agents/a_sag_fake_reader.toml"
want $? "a ToolSearch agent is told to use inherited MCP servers"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$FAKE_CODEX/agents" <<'PY' >/dev/null 2>&1
import sys,pathlib
try: import tomllib
except ImportError: sys.exit(0)
for f in pathlib.Path(sys.argv[1]).glob("*.toml"):
    d = tomllib.loads(f.read_text())
    assert {"name","description","sandbox_mode","developer_instructions"} <= d.keys(), f
PY
  want $? "every rendered agent is valid TOML with the required keys"
else
  echo "  SKIP  TOML validation (no python3 on this host)"
fi

echo "== idempotency =="
cp -r "$FAKE_CODEX" "$SANDBOX/codex-before"
runinst; want $? "second run exits 0"
diff -r "$SANDBOX/codex-before" "$FAKE_CODEX" >/dev/null 2>&1
want $? "a second run changes nothing (no duplicated AGENTS.md block)"
[ "$(grep -c 'Agentic Repos (managed by install-codex.sh)' "$FAKE_CODEX/AGENTS.md")" -eq 1 ]
want $? "exactly one managed block marker in ~/.codex/AGENTS.md"

echo "== target repo layer =="
TGT="$SANDBOX/target"; mkdir -p "$TGT"
git -C "$TGT" init -q -b main; git -C "$TGT" config user.email t@example.com; git -C "$TGT" config user.name T
echo x > "$TGT/f"; git -C "$TGT" add f; git -C "$TGT" commit -qm init
# A hook the project added itself, which the installer must preserve.
mkdir -p "$TGT/.codex"
echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}' > "$TGT/.codex/hooks.json"

runinst --target-only "$TGT"; want $? "--target-only exits 0"
[ "$(jq -r '.hooks.PreToolUse[0].matcher' "$TGT/.codex/hooks.json")" = '^Bash$' ]
want $? "the Codex PreToolUse matcher is ^Bash\$"
jq -e '.hooks.PreToolUse[0].hooks[0].command | test("guard-default-branch.sh")' "$TGT/.codex/hooks.json" >/dev/null
want $? "the hook runs the same guard script Claude Code runs"
jq -e '[.hooks.SessionStart[]?.hooks[]?.command] | index("echo mine")' "$TGT/.codex/hooks.json" >/dev/null
want $? "a hook the project already had is preserved"
[ -f "$TGT/.codex/config.toml" ]; want $? "target gets a .codex/config.toml"

runinst --target-only "$TGT"
[ "$(jq '[.hooks.PreToolUse[]?.hooks[]?.command] | length' "$TGT/.codex/hooks.json")" -eq 1 ]
want $? "re-running does not register the guard twice"

echo "== --target-only does not touch the global layer =="
cp -r "$FAKE_CODEX" "$SANDBOX/codex-b4-target"
TGT2="$SANDBOX/target2"; mkdir -p "$TGT2"; git -C "$TGT2" init -q -b main
runinst --target-only "$TGT2"
diff -r "$SANDBOX/codex-b4-target" "$FAKE_CODEX" >/dev/null 2>&1
want $? "--target-only left ~/.codex untouched"

echo "== a project's own posture is not overwritten =="
TGT3="$SANDBOX/target3"; mkdir -p "$TGT3/.codex"; git -C "$TGT3" init -q -b main
printf 'approval_policy = "never"\n' > "$TGT3/.codex/config.toml"
runinst --target-only "$TGT3"
grep -q 'approval_policy = "never"' "$TGT3/.codex/config.toml"
want $? "a project that already chose a posture keeps it"

echo "== a non-git target is refused =="
NOGIT="$SANDBOX/nogit"; mkdir -p "$NOGIT"
runinst --target-only "$NOGIT"
[ $? -ne 0 ]; want $? "installing into a non-git directory fails loudly"

echo "== --check-only installs nothing =="
CLEAN_HOME="$SANDBOX/home2"; mkdir -p "$CLEAN_HOME"
HOME="$CLEAN_HOME" CODEX_HOME="$CLEAN_HOME/.codex" AGENTIC_DEVKIT_DIR="$DEVKIT" \
  bash "$INSTALLER" --check-only >"$SANDBOX/check.log" 2>&1
want $? "--check-only exits 0"
[ ! -d "$CLEAN_HOME/.codex" ] && [ ! -d "$CLEAN_HOME/.agents" ]
want $? "--check-only wrote nothing"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ] || exit 1
