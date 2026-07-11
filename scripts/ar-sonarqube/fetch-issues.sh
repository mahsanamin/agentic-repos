#!/bin/bash

# SonarQube Issue Fetcher
# Fetches all issues from SonarQube for the current PR
# Supports both sonar-project.properties and Gradle-based SonarQube configuration
# Outputs structured JSON for processing by Claude

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

log_success() {
    echo -e "${GREEN}$1${NC}"
}

log_info() {
    echo -e "${YELLOW}$1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    for cmd in gh jq curl; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' not found"
            exit 1
        fi
    done

    log_success "Prerequisites check passed"
}

# Get PR information (supports worktrees where local branch != remote branch)
get_pr_info() {
    log_info "Fetching PR information..."

    # Strategy 0: PR_NUMBER env var override (useful when auto-detection fails)
    if [[ -n "${PR_NUMBER:-}" ]]; then
        PR_INFO=$(gh pr view "$PR_NUMBER" --json number,headRefName,baseRefName 2>/dev/null || echo "")
        if [[ -n "$PR_INFO" ]]; then
            PR_NUM=$(echo "$PR_INFO" | jq -r '.number')
            HEAD_REF=$(echo "$PR_INFO" | jq -r '.headRefName')
            BASE_REF=$(echo "$PR_INFO" | jq -r '.baseRefName')
            log_success "PR #$PR_NUM ($HEAD_REF -> $BASE_REF) [from PR_NUMBER env var]"
            return
        fi
    fi

    # Strategy 1: Direct gh pr view (works when local branch == remote branch)
    PR_INFO=$(gh pr view --json number,headRefName,baseRefName 2>/dev/null || echo "")

    # Strategy 2: Worktree, local branch tracks a differently-named remote branch
    if [[ -z "$PR_INFO" ]]; then
        log_info "Direct PR lookup failed, checking for worktree/tracking branch..."

        LOCAL_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
        TRACKING_REF=$(git config "branch.${LOCAL_BRANCH}.merge" 2>/dev/null || echo "")

        if [[ -n "$TRACKING_REF" ]]; then
            # Extract branch name from refs/heads/feature/proj-471-...
            REMOTE_BRANCH="${TRACKING_REF#refs/heads/}"
            log_info "Local branch '$LOCAL_BRANCH' tracks remote '$REMOTE_BRANCH'"

            PR_INFO=$(gh pr list --head "$REMOTE_BRANCH" --json number,headRefName,baseRefName --limit 1 2>/dev/null | jq '.[0] // empty' 2>/dev/null || echo "")
        fi
    fi

    # Strategy 3: If in a worktree, try finding PRs from the main repo's current branches
    if [[ -z "$PR_INFO" ]]; then
        GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null || echo ".git")
        if [[ "$GIT_COMMON_DIR" != ".git" && "$GIT_COMMON_DIR" != "$(pwd)/.git" ]]; then
            log_info "In a worktree, checking remote for PRs matching local branch..."
            LOCAL_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
            PR_INFO=$(gh pr list --head "$LOCAL_BRANCH" --json number,headRefName,baseRefName --limit 1 2>/dev/null | jq '.[0] // empty' 2>/dev/null || echo "")
        fi
    fi

    if [[ -z "$PR_INFO" ]]; then
        log_error "No PR found for this branch."
        log_info "Tried: gh pr view, tracking branch lookup, and worktree detection."
        log_info "Create a PR first: gh pr create"
        log_info "Or pass PR number: Set PR_NUMBER env var before running."
        exit 1
    fi

    PR_NUM=$(echo "$PR_INFO" | jq -r '.number')
    HEAD_REF=$(echo "$PR_INFO" | jq -r '.headRefName')
    BASE_REF=$(echo "$PR_INFO" | jq -r '.baseRefName')

    log_success "PR #$PR_NUM ($HEAD_REF -> $BASE_REF)"
}

# Extract project key from available configuration sources
get_project_key() {
    log_info "Extracting SonarQube project key..."

    # Strategy 1: sonar-project.properties (standard SonarQube)
    if [[ -f "sonar-project.properties" ]]; then
        PROJECT_KEY=$(grep '^sonar.projectKey=' sonar-project.properties | cut -d'=' -f2 | xargs)
        if [[ -n "$PROJECT_KEY" ]]; then
            log_success "Project key (from sonar-project.properties): $PROJECT_KEY"
            return
        fi
    fi

    # Strategy 2: gradle.properties (Gradle SonarQube plugin)
    if [[ -f "gradle.properties" ]]; then
        PROJECT_KEY=$(grep '^sonarqubeProjectKey=' gradle.properties | cut -d'=' -f2 | xargs 2>/dev/null || true)
        if [[ -n "$PROJECT_KEY" ]]; then
            log_success "Project key (from gradle.properties): $PROJECT_KEY"
            return
        fi
        # Also try sonar.projectKey in gradle.properties
        PROJECT_KEY=$(grep '^sonar.projectKey=' gradle.properties | cut -d'=' -f2 | xargs 2>/dev/null || true)
        if [[ -n "$PROJECT_KEY" ]]; then
            log_success "Project key (from gradle.properties): $PROJECT_KEY"
            return
        fi
    fi

    # Strategy 3: build.gradle, extract from sonar block
    if [[ -f "build.gradle" ]]; then
        PROJECT_KEY=$(grep -oP 'sonar\.projectKey.*?"(.+?)"' build.gradle | head -1 | grep -oP '"(.+?)"' | tr -d '"' 2>/dev/null || true)
        if [[ -n "$PROJECT_KEY" ]]; then
            log_success "Project key (from build.gradle): $PROJECT_KEY"
            return
        fi
    fi

    # Strategy 4: build.gradle.kts (Kotlin DSL)
    if [[ -f "build.gradle.kts" ]]; then
        PROJECT_KEY=$(grep -oP 'sonar\.projectKey.*?"(.+?)"' build.gradle.kts | head -1 | grep -oP '"(.+?)"' | tr -d '"' 2>/dev/null || true)
        if [[ -n "$PROJECT_KEY" ]]; then
            log_success "Project key (from build.gradle.kts): $PROJECT_KEY"
            return
        fi
    fi

    # Strategy 5: pom.xml (Maven)
    if [[ -f "pom.xml" ]]; then
        PROJECT_KEY=$(grep -oP '<sonar\.projectKey>(.+?)</sonar\.projectKey>' pom.xml | head -1 | sed 's/<[^>]*>//g' 2>/dev/null || true)
        if [[ -n "$PROJECT_KEY" ]]; then
            log_success "Project key (from pom.xml): $PROJECT_KEY"
            return
        fi
    fi

    log_error "Could not find SonarQube project key in any known location"
    log_info "Searched: sonar-project.properties, gradle.properties, build.gradle, build.gradle.kts, pom.xml"
    exit 1
}

# Fetch issues from SonarQube
fetch_issues() {
    log_info "Fetching new/active issues from SonarQube for PR #$PR_NUM..."

    # Fetch only OPEN/CONFIRMED/REOPENED issues for this PR (excludes CLOSED/FIXED)
    RESPONSE=$(curl -s -u "$SONARQUBE_TOKEN:" \
        "${SONARQUBE_URL}/api/issues/search?componentKeys=${PROJECT_KEY}&pullRequest=${PR_NUM}&statuses=OPEN,CONFIRMED,REOPENED&ps=500")

    # Check if response is empty
    if [[ -z "$RESPONSE" ]]; then
        log_error "No response from SonarQube API. Check network connectivity and SONARQUBE_URL."
        exit 1
    fi

    # Check if response is HTML (auth failure or redirect)
    if [[ "$RESPONSE" == *"<!doctype"* ]] || [[ "$RESPONSE" == *"<html"* ]]; then
        log_error "SonarQube API returned HTML instead of JSON. Authentication may have failed."
        log_error "Check SONARQUBE_TOKEN validity and SonarQube API accessibility."
        exit 1
    fi

    # Try to parse JSON
    TOTAL=$(echo "$RESPONSE" | jq '.total // 0' 2>/dev/null || echo "error")

    if [[ "$TOTAL" == "error" ]]; then
        log_error "Invalid JSON response from SonarQube API"
        log_info "Response preview: ${RESPONSE:0:200}"
        exit 1
    fi

    if [[ $TOTAL -eq 0 ]]; then
        log_success "No issues found!"
        echo '{"total": 0, "issues": []}'
        exit 0
    fi

    log_success "Found $TOTAL issue(s)"

    # Output structured issues, extract file path from component (strip project key prefix)
    echo "$RESPONSE" | jq --arg pk "$PROJECT_KEY" '{
        total: .total,
        issues: [
            .issues[] | {
                key: .key,
                rule: .rule,
                severity: .severity,
                type: .type,
                message: .message,
                component: .component,
                file: (.component | split(":") | if length > 1 then .[1:] | join(":") else .[0] end),
                line: .line,
                startLine: .startLine,
                endLine: .endLine,
                status: .status,
                resolution: .resolution
            }
        ]
    }'
}

# Parse arguments
DEMO_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --demo)
            DEMO_MODE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Main execution
main() {
    check_prerequisites
    get_pr_info
    get_project_key

    if [[ "$DEMO_MODE" == "true" ]]; then
        log_info "Running in DEMO mode with sample issues..."
        echo '{
  "total": 2,
  "issues": [
    {
      "key": "demo-issue-1",
      "rule": "java:S1128",
      "severity": "MINOR",
      "type": "CODE_SMELL",
      "message": "Remove this unused import '\''java.util.HashMap'\''.",
      "component": "project:module-server/src/main/java/com/example/MyService.java",
      "file": "module-server/src/main/java/com/example/MyService.java",
      "line": 5,
      "startLine": 5,
      "endLine": 5,
      "status": "OPEN",
      "resolution": null
    },
    {
      "key": "demo-issue-2",
      "rule": "java:S1172",
      "severity": "MAJOR",
      "type": "CODE_SMELL",
      "message": "Remove this unused method parameter '\''unused'\''.",
      "component": "project:module-server/src/main/java/com/example/MyService.java",
      "file": "module-server/src/main/java/com/example/MyService.java",
      "line": 42,
      "startLine": 42,
      "endLine": 42,
      "status": "OPEN",
      "resolution": null
    }
  ]
}'
    else
        fetch_issues
    fi
}

main
