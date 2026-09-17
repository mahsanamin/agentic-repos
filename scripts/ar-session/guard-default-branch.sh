#!/usr/bin/env bash
#
# ar-session/guard-default-branch.sh, Agentic Repos PreToolUse(Bash) guard.
#
# Wired globally into ~/.claude/settings.json by ./install.sh, and registered for
# Codex in .codex/hooks.json, so ONE predicate protects every repo on both
# harnesses. Refusals, in the order they are checked:
#
#   1. A command word that is an expansion ($(...) / backticks) carrying a git
#      operation this policy gates, because it cannot be resolved to a binary.
#   2. Bare force-push (--force, -f, or a leading + on a refspec), anywhere.
#   3. git push --all / --mirror, which push refs this guard cannot enumerate.
#   4. --force-with-lease onto a SHARED branch (main/master/develop/staging/
#      release/*, story/*, origin HEAD) or from a detached HEAD. Rewriting your
#      own feature branch stays allowed.
#   5. git rebase on a shared branch or from a detached HEAD. The in-progress
#      verbs (--continue/--abort/--skip/--quit/--edit-todo/--show-current-patch)
#      are always allowed, so a rebase can always be finished or backed out.
#   6. A whole-tree `git checkout .` / `git restore .`, which discards every
#      uncommitted change with no undo.
#   7. git reset --hard/--merge/--keep, same capability, same refusal.
#   8. git clean without -n/--dry-run, which deletes untracked files with no undo.
#   9. commit / push that would land on the code repo's DEFAULT branch, whether
#      by being on it, by an explicit push destination, or via a checkout earlier
#      in the same command.
#
# Checks 2-8 are about destruction and apply in any repository. Check 9 is scoped
# to the repo rooted at $CLAUDE_PROJECT_DIR, so committing into an unrelated docs
# or tasks repo is unaffected.
#
# IMPORTANT: this is a BEST-EFFORT, defense-in-depth control. It statically
# inspects an arbitrary shell string, which cannot be made sound: a determined
# command (subshells, `bash -c`, aliases, decoy `cd`/`git -C`) can evade it. The
# AUTHORITATIVE control is server-side branch protection on the default branch
# (require a PR, block direct pushes and force-push). Treat this as a seatbelt,
# not a security boundary.
#
# Reads the hook payload (JSON) on stdin; the command is at .tool_input.command.
# Exit 2 with a message on stderr blocks the tool call; exit 0 allows it.

set -u

payload=$(cat)

# Degrade BY SCOPE when the payload cannot be read. This hook sees every Bash
# call on the machine, so refusing everything would block `ls`; allowing
# everything would silently drop protection on exactly the commands that matter.
# Refuse git, allow the rest with a warning. ($1 says why.)
degrade() {
  if printf '%s' "$payload" | grep -Eq '(^|[^A-Za-z0-9_-])git([^A-Za-z0-9_-]|$)'; then
    echo "Refuse: $1, so this git command cannot be checked against the protected-branch policy." >&2
    exit 2
  fi
  echo "Warning: $1. Non-git commands still run; protected-branch enforcement is OFF." >&2
  exit 0
}

command -v jq >/dev/null 2>&1 || degrade "jq is not installed (Agentic Repos requires it; re-run ./install.sh)"
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null) \
  || degrade "the hook payload is not valid JSON"
[ -n "$cmd" ] && [ "$cmd" != "null" ] || degrade "the hook payload carried no .tool_input.command"

QUOTES="\"'"

# Match a git invocation as a command word: after a start/operator, optionally
# preceded by VAR=val assignments or `env`, optionally quoted, optionally a path.
G='(^|[;&|(]|\$\(|`)[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|env)[[:space:]]+)*["'"'"']?([^[:space:];&|]*/)?git["'"'"']?[[:space:]]+(-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?[[:space:]]+)*'

unquote() { local s=$1; s=${s#["$QUOTES"]}; s=${s%["$QUOTES"]}; printf '%s' "$s"; }

# --- 1. An expanded command word carrying a gated git operation --------------
# `$TOOL push --force` cannot be resolved to a binary here, so it cannot be
# cleared. Refuse it rather than let it through unchecked.
set -f
rest=$(printf '%s' "$cmd" | tr ';&|\n' '\003\003\003\003')
while [ -n "$rest" ]; do
  seg=${rest%%$'\003'*}
  case "$rest" in *$'\003'*) rest=${rest#*$'\003'} ;; *) rest='' ;; esac
  [ -n "$seg" ] || continue
  set -- $seg
  while [ $# -gt 0 ]; do
    case "$1" in [A-Za-z_][A-Za-z0-9_]*=*) shift ;; env) shift ;; *) break ;; esac
  done
  [ $# -gt 0 ] || continue
  word=$1; shift
  case "$word" in *'$'*|*'`'*) ;; *) continue ;; esac
  for a in "$@"; do
    case "$(unquote "$a")" in
      push|checkout|switch|rebase|commit|reset|clean|--force|-f|--force-with-lease|--force-with-lease=*)
        set +f
        echo "Refuse: the command word '$word' is an expansion, so it cannot be resolved to a binary, and this segment names a git operation the protected-branch policy gates. Invoke git directly." >&2
        exit 2 ;;
    esac
  done
done
set +f

# --- Branch facts -----------------------------------------------------------
# Follow a `cd` or `git -C` in the command so the branch is read where git runs.
tdir=$(printf '%s\n' "$cmd" | sed -nE 's/.*(^|[;&|])[[:space:]]*(cd|git[[:space:]]+-C)[[:space:]]+([^[:space:];&|]+).*/\3/p' | head -1)
[ -z "$tdir" ] && tdir="$PWD"
branch=$(git -C "$tdir" branch --show-current 2>/dev/null)
defbr=$(git -C "$tdir" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')

# Protected = the repo's default branch. Nothing commits or pushes here.
is_default() {
  case "$1" in
    "") return 1 ;;
    main|master) return 0 ;;
  esac
  [ -n "$defbr" ] && [ "$1" = "$defbr" ]
}
# Shared = anything other people base work on. Nothing REWRITES history here.
is_shared() {
  case "$1" in
    "") return 1 ;;
    main|master|develop|staging) return 0 ;;
    release/*|story/*) return 0 ;;
  esac
  [ -n "$defbr" ] && [ "$1" = "$defbr" ]
}

seg_of() { printf '%s\n' "$cmd" | grep -oE "${G}$1[^;&|]*"; }

# --- 2/3/4. push ------------------------------------------------------------
dests=''
pushseg=$(seg_of push)
if [ -n "$pushseg" ]; then
  spec=$(printf '%s\n' "$pushseg" | sed -E 's/^.*[[:space:]]push([[:space:]]+|$)/ /')
  bare=''; lease=''; allmirror=''; n=0
  for tok in $spec; do
    tok=$(unquote "$tok")
    case "$tok" in
      --force) bare=1; continue ;;
      --force-with-lease|--force-with-lease=*) lease=1; continue ;;
      --force-if-includes|--force-if-includes=*) continue ;;
      --all|--mirror) allmirror=1; continue ;;
      --*) continue ;;
      -*) case "$tok" in *f*) bare=1 ;; esac; continue ;;
      +*) bare=1 ;;
    esac
    n=$((n+1)); [ "$n" -eq 1 ] && continue    # first non-flag token is the remote
    d=${tok#+}; d=${d##*:}; d=${d#refs/heads/}
    dests="$dests $d"
  done
  if [ -n "$bare" ]; then
    echo 'Refuse: force-push (--force / -f / +refspec) is forbidden everywhere, it overwrites the remote with no check. Use --force-with-lease on your own feature branch.' >&2
    exit 2
  fi
  if [ -n "$allmirror" ]; then
    echo 'Refuse: git push --all / --mirror pushes every matching ref, the default branch included, and this guard cannot enumerate what they would send. Push an explicit refspec instead.' >&2
    exit 2
  fi
  if [ -n "$lease" ]; then
    hit=''
    if [ -z "$branch" ]; then hit='a detached HEAD'
    elif is_shared "$branch"; then hit="the shared branch '$branch'"
    else for d in $dests; do is_shared "$d" && { hit="push destination '$d'"; break; }; done
    fi
    if [ -n "$hit" ]; then
      echo "Refuse: --force-with-lease would rewrite $hit. Never rewrite a branch other people are based on; rewrite only your own feature branch." >&2
      exit 2
    fi
  fi
fi

# --- 5. rebase --------------------------------------------------------------
rebaseseg=$(seg_of rebase)
if [ -n "$rebaseseg" ]; then
  if printf '%s\n' "$rebaseseg" | grep -Eq -- '(^|[[:space:]])--(continue|abort|skip|quit|edit-todo|show-current-patch)([[:space:]]|$)'; then
    :                                          # finishing or backing out is always allowed
  elif [ -z "$branch" ]; then
    echo 'Refuse: rebase from a detached HEAD. The replayed commits are reachable from no branch, so a failed rebase leaves them recoverable only through the reflog. Check out a branch first.' >&2
    exit 2
  elif is_shared "$branch"; then
    echo "Refuse: rebase on the shared branch '$branch' rewrites history other people are based on. Rebase your feature branch instead." >&2
    exit 2
  fi
fi

# --- 6. whole-tree checkout / restore ---------------------------------------
if printf '%s\n' "$cmd" | grep -oE "${G}(checkout|restore)[^;&|]*" | while IFS= read -r ds; do
     dspec=$(printf '%s\n' "$ds" | sed -E 's/^.*[[:space:]](checkout|restore)([[:space:]]+|$)/ /')
     wide=''; staged=''; worktree=''
     for tok in $dspec; do
       case "$(unquote "$tok")" in
         --staged|--cached) staged=1 ;;
         --worktree) worktree=1 ;;
         .|./|:/) wide=1 ;;
       esac
     done
     # --staged alone only unstages; --worktree puts the working tree back in scope.
     [ -n "$wide" ] && { [ -z "$staged" ] || [ -n "$worktree" ]; } && echo HIT
   done | grep -q HIT; then
  echo "Refuse: a whole-tree checkout/restore of '.' discards every uncommitted change in the working tree with no undo, the same capability git reset and git clean are refused for. Name the paths to restore, or commit/stash first." >&2
  exit 2
fi

# --- 7. reset --hard / --merge / --keep -------------------------------------
resetseg=$(seg_of reset)
if [ -n "$resetseg" ] && printf '%s\n' "$resetseg" | grep -Eq -- '(^|[[:space:]])--(hard|merge|keep)([[:space:]]|$)'; then
  echo 'Refuse: git reset --hard/--merge/--keep discards every uncommitted change in the working tree with no undo. Commit or stash first, or use --soft; a plain git reset <path> only unstages and is allowed.' >&2
  exit 2
fi

# --- 8. git clean -----------------------------------------------------------
cleanseg=$(seg_of clean)
if [ -n "$cleanseg" ] && ! printf '%s\n' "$cleanseg" | grep -Eq -- '(^|[[:space:]])(--dry-run|-[A-Za-z]*n[A-Za-z]*)([[:space:]]|$)'; then
  echo 'Refuse: git clean deletes untracked files with no undo. git clean -n (or --dry-run) is allowed to list what it would remove; if the deletion is wanted, a human runs it.' >&2
  exit 2
fi

# --- 9. commit / push landing on the default branch -------------------------
if printf '%s\n' "$cmd" | grep -Eq "${G}(commit|push)([^[:alnum:]_-]|$)"; then
  tgt=$(git -C "$tdir" rev-parse --show-toplevel 2>/dev/null)
  code=$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null)

  # A checkout/switch earlier in the SAME command decides the branch the commit
  # lands on, so resolve its target rather than trusting the current branch.
  cotargets=''; unresolved=''
  coseg=$(printf '%s\n' "$cmd" | grep -oE "${G}(checkout|switch)[^;&|]*")
  if [ -n "$coseg" ]; then
    cospec=$(printf '%s\n' "$coseg" | sed -E 's/^.*[[:space:]](checkout|switch)([[:space:]]+|$)/ @@SEG@@ /')
    want=0; stop=0; cand=''; extra=0
    flush() { [ -n "$cand" ] && [ "$extra" -eq 0 ] && cotargets="$cotargets $cand"; cand=''; extra=0; }
    for tok in $cospec; do
      [ "$tok" = '@@SEG@@' ] && { flush; want=0; stop=0; continue; }
      tok=$(unquote "$tok")
      [ "$stop" -eq 1 ] && continue
      [ "$want" -eq 1 ] && { cotargets="$cotargets $tok"; want=0; stop=1; continue; }
      case "$tok" in
        --) cand=''; extra=0; stop=1; continue ;;
        -b|-B|-c|-C|--branch) want=1; continue ;;
        -b?*|-B?*) cotargets="$cotargets ${tok#??}"; stop=1; continue ;;
        -|*@\{-*) unresolved=1; continue ;;   # `checkout -` / `@{-N}`: target unknown
        -*) continue ;;
      esac
      if [ -z "$cand" ]; then cand="$tok"; else extra=1; fi
    done
    flush
  fi

  hit=''
  is_default "$branch" && hit="checked-out branch '$branch'"
  [ -z "$hit" ] && for d in $dests; do is_default "$d" && { hit="push destination '$d'"; break; }; done
  [ -z "$hit" ] && for c in $cotargets; do is_default "$c" && { hit="branch '$c', switched to earlier in this same command"; break; }; done
  [ -z "$hit" ] && [ -n "$unresolved" ] && hit="a checkout target this guard cannot resolve (git checkout - / @{-N}), which may be the default branch"

  if [ -n "$tgt" ] && [ "$tgt" = "$code" ] && [ -n "$hit" ]; then
    echo "Refuse: commit/push would land on the code repo default branch ($hit). Use a feature branch (a worktree via a_g_worktree_init is preferred)." >&2
    exit 2
  fi
fi

exit 0
