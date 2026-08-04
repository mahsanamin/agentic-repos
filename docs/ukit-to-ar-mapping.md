# Migrating from `ukit-*` to `ar-*` / `a_*`

`ukit-*` is a locally renamed copy of the AA framework — the predecessor of Agentic Repos.
Nearly every skill has a direct successor. This table is what a teammate needs to switch.

Install the successors once per machine:

```bash
git clone <your fork of agentic-devkit> ~/agentic-devkit && ~/agentic-devkit/install.sh
git clone <your fork of agentic-repos>  ~/agentic-repos  && ~/agentic-repos/install.sh
# restart Claude Code
```

## Skills — direct successors

| `ukit-*` | Successor | Notes |
|---|---|---|
| `ukit-task-flow` | `ar-taskflow` | Same Raw Prompt → Understand → Plan → Code → Document flow |
| `ukit-task-flow-planner` | `ar-taskflow-planner` | |
| `ukit-task-flow-review` | `ar-taskflow-review` | |
| `ukit-task-flow-resume` | `ar-taskflow-resume` | |
| `ukit-task-flow-remember` | `ar-taskflow-remember` | |
| `ukit-task-flow-fix-comments` | `ar-taskflow-fix-comments` | |
| `ukit-optimizer` | `ar-optimizer` | |
| `ukit-record-improvement` | `ar-record-improvement` | |
| `ukit-global-pr-reviewer` | `ar-global-pr-reviewer` | |
| `ukit-init-mcps` | `ar-init-mcps` | |
| `ukit-init-skills` | `ar-init-skills` | |
| `ukit-ticket-creator` | `ar-ticket-creator` | |
| `ukit-api-dd-compare` | `ar-api-dd-compare` | |
| `ukit-dd-api-performance` | `ar-dd-api-performance` | |

## Skills — successor lives in agentic-devkit

| `ukit-*` | Successor |
|---|---|
| `ukit-commit` | `a_sk_commit` |
| `ukit-pr` | `a_sk_pr` |
| `ukit-review-pr` | `a_sk_review_pr` |
| `sonarqube-test-coverage` | `a_sk_sonarqube_coverage` |

## ⚠️ Check for local skills with no successor

An installation that has been in use for a while usually grows skills that were written
locally and never existed upstream. These have **no `ar-*` equivalent** and are lost if
the `ukit-*` directory is deleted wholesale. Audit before you delete:

```bash
# skills present locally that have no ar- counterpart
for s in .claude/skills/ukit-*; do
  n=$(basename "$s" | sed 's/^ukit-/ar-/')
  [ -d ~/.claude/skills/"$n" ] || echo "NO SUCCESSOR: $(basename "$s")"
done
```

Typical categories that come back with no match:

| Category | Why it has no successor |
|---|---|
| Machine/dev-environment onboarding | Team-specific tooling list |
| Release or build-notes generation | Project-specific release process |
| Chat-based status reports | `a_r_l_weekly_status_report` is the nearest, but it is git/notes-driven rather than chat+tracker driven — **partial overlap only** |

Decide per skill: port it to `ar-*` / `a_sk_*` naming, keep it as-is, or drop it. Copy the
source somewhere version-controlled **before** any migration deletes it.

## Agents

| `ukit-*` | Successor |
|---|---|
| `ukit-code-reviewer` | `a_sag_code_reviewer` |
| `ukit-commit-writer` | `a_sag_commit_writer` |
| `ukit-doc-writer` | `a_sag_task_doc_writer` |
| `ukit-plan-verifier` | `a_sag_plan_verifier` |
| `ukit-pr-writer` | `a_sag_pr_writer` |
| `ukit-test-runner` | `a_sag_test_runner` |

`mcp-unity` is a project agent, unrelated to the framework. Leave it.

## Shell helpers

| `ukit_*` | Successor |
|---|---|
| `ukit_g_worktree_init` | `a_g_worktree_init` |
| `ukit_g_worktree_remove` | `a_g_worktree_remove` |
| `ukit_g_worktree_review` | `a_g_worktree_review` |
| `ukit_g_worktree_list` / `_doctor` / `_prune` / `_main` / `_switch` | `a_c_workflow_doctor` plus raw `git worktree`; no 1:1 replacement yet |

Task management gains `a_c_task_start` / `_resume` / `_list` / `_finish`, which UKit had no
equivalent for: it registers tasks across every repo, not just the current one.

## Per-repo migration

A repo adopted by UKit carries `.claude/config_hints.json`, `.claude/skills/ukit-*`, and
`.claude/agents/ukit-*`. Because `config_hints.json` already exists, `/ar-install` will
refuse and tell you to run `/ar-upgrade` instead — that is the correct path for an already-
adopted repo.

**Do not `rm -rf` anything matching `ukit`.** In Unity projects `UKit` is also an unrelated
C# library (~17,000 tracked files: `Assets/Scripts/_UKit/`, `UKit_Core.csproj`,
`_UKit_Assets/`). Scope every deletion to `.claude/` explicitly:

```bash
git rm -r .claude/skills/ukit-* .claude/agents/ukit-*
```

Removing them from a shared repo affects everyone who has not migrated yet. Agree the
timing with the team before it lands on a shared branch.
