#!/usr/bin/env bash
# Agentic Repos, framework freshness check.
#
# Both sourcable (auto-runs when shell-rc sources it) and directly executable
# (other tools can run it via `bash check.sh` or `bash check.sh --force`).
#
# Throttled to once per 24h via ~/.claude/.ar-last-freshness-check so it never
# spams. Detects:
#   - Framework repo is behind origin/main (user needs to git pull)
#   - Pulled but install.sh wasn't re-run (HEAD != installed SHA)
#   - New global skills available since last install (discovery hint)
#
# Silent when AR_FRAMEWORK_DIR is unset, the repo is missing, the user is
# already current, or the throttle is still active.
#
# Always returns 0, informational only, never blocks the caller.

ar_check_freshness() {
    [ -z "${AR_FRAMEWORK_DIR:-}" ] && return 0
    [ ! -d "$AR_FRAMEWORK_DIR" ] && return 0
    # Use git's own "am I inside a worktree" check rather than [ -d .git ] -
    # the framework can live as a subdirectory of a larger monorepo, in which
    # case .git is several levels up, not at $AR_FRAMEWORK_DIR/.git.
    git -C "$AR_FRAMEWORK_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    [ -n "${ZSH_VERSION:-}" ] && setopt LOCAL_OPTIONS TYPESET_SILENT

    local force=0
    [ "${1:-}" = "--force" ] && force=1

    local throttle="$HOME/.claude/.ar-last-freshness-check"
    local now last
    now=$(date +%s)
    # Ensure the throttle's parent dir exists. On fresh machines a teammate
    # may add the rc source line manually before running install.sh
    # (which is what creates ~/.claude/). Without this mkdir the `echo > "$throttle"`
    # silently fails, the throttle never persists, and the nudge fires on
    # every shell open.
    mkdir -p "$(dirname "$throttle")" 2>/dev/null

    if [ "$force" -eq 0 ] && [ -f "$throttle" ]; then
        last=$(cat "$throttle" 2>/dev/null || echo 0)
        if [ -n "$last" ] && [ "$((now - last))" -lt 86400 ] 2>/dev/null; then
            return 0
        fi
    fi

    # --- Detection ----------------------------------------------------------
    # Scope everything to AR_FRAMEWORK_DIR, when the framework lives inside a
    # monorepo, commits to OTHER directories (e.g., sibling tools) shouldn't
    # trip the freshness check. The `-- .` path filter restricts to commits
    # touching the framework dir.
    local pull_count=0
    local behind default_remote_head
    # Discover the remote's default branch from origin/HEAD instead of
    # hardcoding "main". Repos with a "master" default would silently no-op
    # here (origin/main doesn't exist → rev-list errors → behind="" →
    # pull_count stays 0). Same lookup pattern is used in a_sk_pr/SKILL.md,
    # ar-taskflow-review/SKILL.md, ar-upgrade/SKILL.md, ar-install/SKILL.md.
    default_remote_head=$(git -C "$AR_FRAMEWORK_DIR" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's@^refs/remotes/origin/@@')
    default_remote_head="${default_remote_head:-main}"
    behind=$(git -C "$AR_FRAMEWORK_DIR" rev-list --count "HEAD..origin/$default_remote_head" -- . 2>/dev/null) || behind=""
    if [ -n "$behind" ] && [ "$behind" -gt 0 ] 2>/dev/null; then
        pull_count="$behind"
    fi

    local state="$HOME/.claude/.agentic-repos-state.json"
    local installed_sha="" head_sha="" install_stale=0
    # Last commit that actually touched the framework subtree, not the
    # whole-monorepo HEAD, which would flip-flop on unrelated commits.
    head_sha=$(git -C "$AR_FRAMEWORK_DIR" log -1 --format=%H -- . 2>/dev/null) || head_sha=""
    if [ -f "$state" ] && command -v jq >/dev/null 2>&1; then
        installed_sha=$(jq -r '.framework_sha // empty' "$state" 2>/dev/null)
    fi
    # "unknown" is written when the install-time SHA lookup returned nothing
    # (e.g. a plugin cache or shallow checkout). Do not treat that as stale, or
    # a later real SHA would fire a permanent false "re-run install" nudge.
    if [ -n "$installed_sha" ] && [ "$installed_sha" != "unknown" ] && [ -n "$head_sha" ] && [ "$installed_sha" != "$head_sha" ]; then
        install_stale=1
    fi

    # Nothing to say, record the check and bail silently.
    if [ "$pull_count" -eq 0 ] && [ "$install_stale" -eq 0 ]; then
        echo "$now" > "$throttle" 2>/dev/null
        return 0
    fi

    # --- New-global-skill discovery -----------------------------------------
    local new_skills=""
    if [ -f "$state" ] && [ -d "$AR_FRAMEWORK_DIR/skills" ] && command -v jq >/dev/null 2>&1; then
        local current_set installed_set
        current_set=$(for d in "$AR_FRAMEWORK_DIR"/skills/*/; do [ -f "$d/SKILL.md" ] && basename "$d"; done | sort -u)
        installed_set=$(jq -r '.global_skills[]?' "$state" 2>/dev/null | sort -u)
        new_skills=$(comm -23 <(echo "$current_set") <(echo "$installed_set") 2>/dev/null | paste -sd ',' - | sed 's/,/, /g')
    fi

    echo "$now" > "$throttle" 2>/dev/null

    # --- One-shot nudge -----------------------------------------------------
    printf '\n[agentic-repos] Framework updates available:\n'
    [ "$pull_count" -gt 0 ] && printf '  • %s commit(s) on origin/%s not pulled\n' "$pull_count" "$default_remote_head"
    [ "$install_stale" -eq 1 ] && printf '  • Pulled but install.sh not re-run (HEAD %s)\n' "${head_sha:0:7}"
    [ -n "$new_skills" ] && printf '  • New global skill(s): %s\n' "$new_skills"
    printf '  Refresh: (cd %s && git pull && ./install.sh)\n\n' "$AR_FRAMEWORK_DIR"

    return 0
}

# Run on source AND on direct execution. Throttled either way.
ar_check_freshness "$@"
