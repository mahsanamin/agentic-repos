#!/usr/bin/env bash
#
# Regression suite for scripts/ar-session/guard-default-branch.sh.
#
# The guard decides whether an arbitrary shell string is allowed to run, so its
# behaviour is a contract, not an implementation detail. Every refusal it makes
# and every command it must NOT block has a case here. Run it after any edit to
# the guard:
#
#   bash scripts/ar-lint/git-guard-cases.sh
#
# Each case builds a throwaway git repo, checks out the branch under test, feeds
# the guard a realistic hook payload, and asserts the exit status. Exit 0 = all
# cases passed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/../ar-session/guard-default-branch.sh"
[ -f "$GUARD" ] || { echo "FAIL: guard not found at $GUARD" >&2; exit 1; }

pass=0; fail=0

# Build a disposable repo whose default branch is $1 and whose checked-out
# branch is $2. Echoes the path.
mkrepo() {
  local defbranch="$1" onbranch="$2" d
  d=$(mktemp -d)
  git -C "$d" init -q -b "$defbranch"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  echo x > "$d/f"; git -C "$d" add f; git -C "$d" commit -qm init
  # Give it an origin/HEAD so the guard's default-branch lookup has a real answer.
  git -C "$d" remote add origin "$d"
  git -C "$d" fetch -q origin 2>/dev/null
  git -C "$d" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$defbranch" 2>/dev/null
  [ "$onbranch" != "$defbranch" ] && git -C "$d" checkout -q -b "$onbranch"
  echo "$d"
}

# check <expect: refuse|allow> <description> <default-branch> <on-branch> <command>
check() {
  local expect="$1" desc="$2" defb="$3" onb="$4" command="$5"
  local repo rc out
  repo=$(mkrepo "$defb" "$onb")
  out=$(cd "$repo" && printf '%s' "$(jq -n --arg c "$command" \
        '{session_id:"s",cwd:".",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')" \
        | CLAUDE_PROJECT_DIR="$repo" bash "$GUARD" 2>&1)
  rc=$?
  rm -rf "$repo"
  if [ "$expect" = refuse ] && [ "$rc" -eq 2 ]; then
    pass=$((pass+1)); printf '  ok    refuse  %s\n' "$desc"
  elif [ "$expect" = allow ] && [ "$rc" -eq 0 ]; then
    pass=$((pass+1)); printf '  ok    allow   %s\n' "$desc"
  else
    fail=$((fail+1))
    printf 'FAIL  expected %s, got exit %s: %s\n      cmd: %s\n      out: %s\n' \
      "$expect" "$rc" "$desc" "$command" "$out"
  fi
}

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run these cases" >&2; exit 1; }

echo "== 1. expanded command word carrying a gated operation =="
check refuse 'expanded command word + push --force'   main feature 'CMD=$(which git); $CMD push --force'
check refuse 'backtick command word + commit'         main feature '`echo git` commit -m x'
check allow  'expansion with no gated git operation'  main feature 'D=$(pwd); ls $D'

echo "== 2. bare force-push is refused everywhere =="
check refuse 'push --force on a feature branch'       main feature 'git push --force origin feature'
check refuse 'push -f on a feature branch'            main feature 'git push -f origin feature'
check refuse 'push +refspec on a feature branch'      main feature 'git push origin +feature'
check refuse 'force-push via absolute path'           main feature '/usr/bin/git push --force origin feature'

echo "== 3. push --all / --mirror =="
check refuse 'push --all'                             main feature 'git push --all origin'
check refuse 'push --mirror'                          main feature 'git push --mirror origin'

echo "== 4. --force-with-lease is branch-scoped =="
check allow  'lease on own feature branch'            main feature 'git push --force-with-lease origin feature'
check refuse 'lease while on main'                    main main    'git push --force-with-lease origin main'
check refuse 'lease while on develop'                 main develop 'git push --force-with-lease origin develop'
check refuse 'lease while on release/1.2'             main release/1.2 'git push --force-with-lease origin release/1.2'
check refuse 'lease targeting a shared destination'   main feature 'git push --force-with-lease origin feature:develop'

echo "== 5. rebase =="
check allow  'rebase on a feature branch'             main feature 'git rebase origin/main'
check refuse 'rebase while on main'                   main main    'git rebase origin/main'
check refuse 'rebase while on staging'                main staging 'git rebase origin/main'
check allow  'rebase --continue on main'              main main    'git rebase --continue'
check allow  'rebase --abort on main'                 main main    'git rebase --abort'

echo "== 6. whole-tree checkout / restore =="
check refuse 'git checkout .'                         main feature 'git checkout .'
check refuse 'git restore .'                          main feature 'git restore .'
check refuse 'git restore --staged --worktree .'      main feature 'git restore --staged --worktree .'
check allow  'git restore --staged . (unstage only)'  main feature 'git restore --staged .'
check allow  'git checkout of a named path'           main feature 'git checkout -- src/app.js'
check allow  'git checkout -b newbranch'              main feature 'git checkout -b newbranch'

echo "== 7. reset =="
check refuse 'git reset --hard'                       main feature 'git reset --hard HEAD~1'
check refuse 'git reset --keep'                       main feature 'git reset --keep HEAD~1'
check allow  'git reset --soft'                       main feature 'git reset --soft HEAD~1'
check allow  'git reset of a path (unstage)'          main feature 'git reset src/app.js'

echo "== 8. git clean =="
check refuse 'git clean -fd'                          main feature 'git clean -fd'
check allow  'git clean -n (dry run)'                 main feature 'git clean -n'
check allow  'git clean --dry-run'                    main feature 'git clean --dry-run'

echo "== 9. commit / push landing on the default branch =="
check refuse 'commit while on main'                   main main    'git commit -m "x"'
check refuse 'commit while on master'                 master master 'git commit -m "x"'
check refuse 'push HEAD:main from a feature branch'   main feature 'git push origin HEAD:main'
check refuse 'checkout main then commit, one command' main feature 'git checkout main && git commit -m "x"'
check refuse 'checkout - then commit (unresolvable)'  main feature 'git checkout - && git commit -m "x"'
check allow  'commit on a feature branch'             main feature 'git commit -m "x"'
check allow  'push a feature branch'                  main feature 'git push origin feature'
check allow  'checkout -b then commit, one command'   main feature 'git checkout -b other && git commit -m "x"'

echo "== non-git commands are never blocked =="
check allow  'ls'                                     main main    'ls -la'
check allow  'a path containing the word git'         main main    'ls ~/digit/legit'
check allow  'grep for the string git'                main main    'grep -r "git" .'

echo "== degrade by scope when the payload cannot be read =="
# A guard that cannot parse its input must not refuse everything (that blocks `ls`)
# and must not allow everything (that silently drops protection). It refuses git
# and allows the rest with a warning.
degrade() {
  local expect="$1" desc="$2" payload="$3" repo rc
  repo=$(mkrepo main feature)
  (cd "$repo" && printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$repo" bash "$GUARD" >/dev/null 2>&1)
  rc=$?
  rm -rf "$repo"
  if [ "$expect" = refuse ] && [ "$rc" -eq 2 ]; then pass=$((pass+1)); printf '  ok    refuse  %s\n' "$desc"
  elif [ "$expect" = allow ] && [ "$rc" -eq 0 ]; then pass=$((pass+1)); printf '  ok    allow   %s\n' "$desc"
  else fail=$((fail+1)); printf 'FAIL  expected %s, got exit %s: %s\n' "$expect" "$rc" "$desc"; fi
}
degrade refuse 'unparseable payload naming a git command' 'not json but mentions git push --force'
degrade allow  'unparseable payload naming no git command' 'not json, just ls'
degrade allow  'empty payload, no git command to classify'  ''
degrade refuse 'valid JSON with no command field, git in the raw text' '{"tool_input":{"x":"git push"}}'

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ] || exit 1
