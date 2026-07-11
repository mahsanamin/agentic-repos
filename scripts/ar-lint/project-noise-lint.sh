#!/usr/bin/env bash
# project-noise-lint.sh, SURFACE project-based-noise candidates in the framework repo.
#
# Twin of generic-skill-lint.sh. That script hard-fails on STACK idioms in skill/agent
# bodies (unambiguous). This one surfaces BUSINESS / PROJECT noise, a source project's
# identity leaking into the project-AGNOSTIC framework. Two shapes of noise:
#
#   1. PROJECT_NOISE, a real project's identity inside an INSTALLED artifact (rules/,
#      skills/, agents/, templates/, setup.md): name, package, dev path, ticket, email,
#      SHA, dated incident note, version-history prose. Rules carry stack idioms; they
#      must never carry a real project's identity.
#   2. PROJECT_SCOPED_ARTIFACT, a whole file whose NAME or DOMINANT CONTENT binds the
#      generic framework to ONE specific project: a "<project>-feedback.md" mining doc,
#      a doc that declares a "Source project:", a file named after a product line. The
#      framework keeps the DISTILLED GENERIC OUTPUT (rules); the project-bound analysis
#      belongs in the source project or scratch space, NOT committed here. This is the
#      class the docs/ tree hides, so docs/ IS scanned (it used to be exempt; that was
#      the blind spot that let docs/plans/acme-spring-boot-feedback.md through).
#
# Noise-vs-legitimate is CONTEXTUAL, so this script emits CANDIDATES grouped by finding
# type for the /ar-self-reviewer judgment pass (and the human) to adjudicate.
# The unambiguous hard-fail lives in generic-skill-lint.sh; this is the wide net.
#
# Scope (default --changed is the useful one, a clean PR adds zero noise):
#   project-noise-lint.sh                # CHANGED files vs main (git diff), default
#   project-noise-lint.sh --all          # every scanned artifact (audit; noisy on legacy)
#   project-noise-lint.sh <file> [file…] # the given files (used by evals)
#
# Scanned: rules/ skills/ agents/ templates/ setup.md (PROJECT_NOISE) AND docs/ (mostly
# PROJECT_SCOPED_ARTIFACT). NOT scanned: CHANGELOG.md (the designated history, it may name
# the project that motivated a change), README/VERSIONING, .claude/commands/ (dev tools).
#
# Exit 0 = no candidates. Exit 1 = at least one candidate to adjudicate. Exit 2 = usage error.

set -uo pipefail
cd "$(dirname "$0")/../.." 2>/dev/null || cd "$(git rev-parse --show-toplevel)" || exit 2

# CUSTOMIZE THIS: a `|`-separated list of YOUR product/project line slugs that must not
# name or dominate a framework file. Keep it to genuine product lines, NOT shared
# libraries/platforms (e.g. the base framework) or generic repo-name patterns, which
# legitimately recur across rules and would false-fire. The defaults below are fictional
# placeholders for the framework's own self-tests; replace them with your real product
# lines. The structural signals below (Source-project line, *-feedback filename) catch
# project-bound docs even when the slug isn't listed, so this list is a bonus, not the
# only defense. Override at runtime with PROJECT_SLUGS=... in the environment.
PROJECT_SLUGS="${PROJECT_SLUGS:-acme|widgets|frobnicator}"

# Exempt lines: parameterized placeholders, labelled examples, git-URL tooling, and the
# standard tokens that share a shape with noise but never are (UTF-8, AC-1, RFC-7231…).
ALLOW='\{[a-zA-Z_]+\}|XXX|NNN|example\.com|@email\.com|noreply@|e\.g\.|[Ee]xample|illustrative|<[a-z]+>|git@github\.com|github\.com[:/](\{|owner|<)|UTF-8|UTF-16|ISO-8601|SHA-256|SHA-1|RFC-[0-9]|HTTP-[0-9]|\bAC-[0-9]|\bTBD\b|localhost'

# Line-based candidate signals: "scope|TYPE|regex". scope=all fires in installed artifacts
# AND docs; scope=inst fires only in installed artifacts (a date/SHA/ticket/version-history
# line is installed-artifact noise but normal narrative in a design doc).
SIGNALS=(
  "all|PROJECT_NOISE|/Volumes/|/Users/[A-Za-z]|/home/[a-z]"           # a developer's absolute checkout path
  "all|PROJECT_NOISE|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(com|io|net|org)"  # real person/team email
  "inst|PROJECT_NOISE|com\.example\.[a-z][a-z0-9]+"                      # literal pkg (com.example.<realname>) vs {project}
  "inst|PROJECT_NOISE|\b[A-Z]{2,6}-[0-9]{1,6}\b"                      # JIRA-style literal ticket id
  "inst|PROJECT_NOISE|\b20[0-9]{2}-[01][0-9]-[0-3][0-9]\b"           # dated incident note in an artifact
  "inst|PROJECT_NOISE|\b[0-9a-f]{12,40}\b"                           # commit SHA pasted into prose
  "inst|RATIONALE_BLOAT|\(NEW in v[0-9]|\(v[0-9][0-9.]* (fix|change|design)\)|previously was|pre-v[0-9]|the v[0-9][0-9.]* design"
  # PROJECT_SCOPED_ARTIFACT, structural giveaway that a whole file is project-bound:
  "all|PROJECT_SCOPED_ARTIFACT|[Ss]ource project|[Ss]ource repo|[Mm]ined from|[Ff]eedback from .*-(service|services)\b"
)

is_installed_artifact() { case "$1" in rules/*|skills/*|agents/*|templates/*|setup.md) return 0;; *) return 1;; esac; }
is_doc()                 { case "$1" in docs/*) return 0;; *) return 1;; esac; }

# --- resolve scope ---
declare -a FILES=()
mode="${1:-}"
if [ "$mode" = "--changed" ] || [ -z "$mode" ]; then
  while IFS= read -r f; do
    if is_installed_artifact "$f" || is_doc "$f"; then [ -f "$f" ] && FILES+=("$f"); fi
  done < <(git diff --name-only main...HEAD 2>/dev/null)
elif [ "$mode" = "--all" ]; then
  while IFS= read -r f; do FILES+=("$f"); done < <(
    find rules skills agents templates docs -type f \( -name '*.md' -o -name '*.json' \) 2>/dev/null
    [ -f setup.md ] && echo setup.md
  )
else
  FILES=("$@")
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "✅ project-noise-lint: no scanned artifacts in scope (nothing changed vs main)."
  exit 0
fi

candidates=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  base=$(basename "$f")

  # (A) Filename signal, a file named after a project / as a project-feedback artifact.
  #     This fires regardless of where the file lives. It is the loudest PROJECT_SCOPED
  #     signal and needs no content read.
  if printf '%s' "$base" | grep -qE "(-|^)(feedback|retro|postmortem|post-mortem|mining)(-|\.|$)" \
     || printf '%s' "$base" | grep -qiE "$PROJECT_SLUGS"; then
    printf '• [PROJECT_SCOPED_ARTIFACT] %s\n' "$f"
    printf '     filename names a specific project / is a project-feedback artifact: %s\n' "$base"
    candidates=$((candidates+1))
  fi

  # (B) Line signals (skip exempt lines).
  scan=$(grep -nvE "$ALLOW" "$f" 2>/dev/null)
  [ -z "$scan" ] && continue
  for sig in "${SIGNALS[@]}"; do
    sscope="${sig%%|*}"; rest="${sig#*|}"; type="${rest%%|*}"; rx="${rest#*|}"
    # scope=inst signals (date/SHA/ticket/pkg/version-history) are installed-artifact noise
    # but normal narrative in a design doc, suppress them for docs/.
    if is_doc "$f" && [ "$sscope" = "inst" ]; then continue; fi
    hits=$(printf '%s\n' "$scan" | grep -E "$rx")
    if [ -n "$hits" ]; then
      printf '• [%s] %s\n' "$type" "$f"
      printf '%s\n' "$hits" | sed 's/^/     /' | cut -c1-160
      candidates=$((candidates + $(printf '%s\n' "$hits" | grep -c .)))
    fi
  done

  # (C) Content-density signal, a product/project slug repeated through a file's body is a
  #     PROJECT_SCOPED candidate even if the filename is innocent (e.g. an "analysis.md" all
  #     about one project). Threshold ≥3 keeps a single illustrative mention from firing.
  slughits=$(printf '%s\n' "$scan" | grep -ioE "$PROJECT_SLUGS" | sort | uniq -c | awk '$1>=3{print $1" x "$2}')
  if [ -n "$slughits" ]; then
    printf '• [PROJECT_SCOPED_ARTIFACT] %s\n' "$f"
    printf '     a specific project/product name dominates this file:\n'
    printf '%s\n' "$slughits" | sed 's/^/     /'
    candidates=$((candidates+1))
  fi
done

echo ""
echo "project-noise-lint: ${#FILES[@]} file(s) scanned · $candidates candidate(s)"
if [ "$candidates" -gt 0 ]; then
  echo "⚠️  Candidates to adjudicate (NOT auto-blocking, the judgment pass + human decide):"
  echo "   PROJECT_NOISE → genericize: real name/package → {project}; path → a config seam;"
  echo "     ticket/email/SHA/incident-date → delete (the CHANGELOG records the why)."
  echo "   PROJECT_SCOPED_ARTIFACT → this file is bound to ONE project; the framework is"
  echo "     project-agnostic. Keep only the distilled GENERIC output (rules); move the"
  echo "     project-specific analysis to the source project or scratch space, not here."
  echo "   Domain-shaped NAMES (a DTO/field that reveals a project's business) are NOT"
  echo "     regex-detectable, the /ar-self-reviewer judgment pass covers those."
  exit 1
fi
echo "✅ project-noise-lint: no noise candidates in scope."
exit 0
