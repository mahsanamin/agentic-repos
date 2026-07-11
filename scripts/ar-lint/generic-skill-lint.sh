#!/usr/bin/env bash
# generic-skill-lint.sh, W7: enforce the generic-skill invariant in the framework SOURCE.
#
# Skills/agents must carry ZERO language/stack idioms; stack-specific knowledge lives in
# rules/ (adapted per stack by the installer). This is the framework-repo twin of the
# target-side Step 16b guardrail. Run from the framework root (or anywhere, it cd's to its repo).
#
# Exit 0 = clean. Exit 1 = a skill/agent body contains a hardcoded language idiom.
#
# Exemptions:
#   - skills/ar-global-pr-reviewer/ , global skill, reviews ANY repo at runtime via detect-and-branch
#   - skills/ar-optimizer/          , global tool that NAMES idioms in its own detection heuristics
#   - lines clearly marked illustrative: "e.g.", "example", "Example", "Bad:", "illustrative", "<file>"

set -uo pipefail
cd "$(dirname "$0")/../.." 2>/dev/null || cd "$(git rev-parse --show-toplevel)" || exit 2

IDIOMS='gradlew|@RestController|@GetMapping|@PostMapping|@PutMapping|@DeleteMapping|@RequestMapping|@Transactional|JpaRepository|CrudRepository|@SpringBootTest|@Entity|@Column|checkstyleMain|\*Test\.java|src/test/java|application\.(yml|properties)|\bpom\.xml\b|Mockito|AssertJ|Lombok|Javadoc|deleteAll|saveAll|@DataJpaTest|Testcontainers|dirty.?check'
ALLOW='e\.g\.|[Ee]xample|illustrative|Bad:|<file>|whichever|or the project'

violations=0
while IFS= read -r f; do
  case "$f" in
    *ar-global-pr-reviewer*|*ar-optimizer*) continue ;;  # exempt globals
  esac
  hits=$(grep -nE "$IDIOMS" "$f" 2>/dev/null | grep -vE "$ALLOW")
  if [ -n "$hits" ]; then
    echo "❌ $f"
    echo "$hits" | sed 's/^/     /' | cut -c1-140
    violations=$((violations + $(printf '%s\n' "$hits" | grep -c .)))
  fi
done < <(find skills agents -name 'SKILL.md' -o -name 'AGENT.md' 2>/dev/null)

echo ""
if [ "$violations" -gt 0 ]; then
  echo "❌ generic-skill-lint FAILED: $violations language idiom(s) in skill/agent bodies."
  echo "   Move stack-specifics into rules/ (per-stack tier) and have the skill defer to them."
  echo "   See docs/plans/stack-agnostic-adaptation.md (Model A, locked)."
  exit 1
fi
echo "✅ generic-skill-lint passed: no language idioms in skill/agent bodies."
