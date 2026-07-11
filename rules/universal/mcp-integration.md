---
triggers: ["issue tracker", "ticket", "create issue", "mcp", "Model Context Protocol", "gh issue", "jira", "github issue", "linear"]
---
## Issue Tracker & Knowledge Base Integration

### Overview

This framework is **tracker-agnostic**. A project picks its issue tracker in `config_hints.json`:

```json
{
  "tracker": { "type": "github", "url": "" }
}
```

Supported `tracker.type` values: **`github`** (GitHub Issues, via the `gh` CLI), **`jira`** (Atlassian Jira/Confluence, via MCP), **`linear`** (via MCP), and **`none`** (no tracker, work is described directly in prompts, identifiers are managed manually). `github` is the default for new installs.

**Skills never hardcode a tracker.** When a workflow step says "fetch ticket", "create ticket", "update tracker", or "ticket link", resolve the operation from the **dispatch table** below using the project's `tracker.type`.

### Tracker Dispatch Table

| Moment | github | jira | linear | none |
|--------|--------|------|--------|------|
| **Check configured** | `gh auth status` | `claude mcp list \| grep atlassian` | Check Linear MCP | Skip |
| **Fetch ticket** | `gh issue view {n} --json title,body,labels,state` | `mcp__atlassian__getJiraIssue` | Linear MCP | N/A (ticket-late only) |
| **Search** | `gh issue list --search "{q}"` | `mcp__atlassian__search` / JQL | Linear MCP | N/A |
| **Create ticket** | `gh issue create --title ... --body ...` | `mcp__atlassian__createJiraIssue` (ask for Epic/parent) | Linear MCP | Ask user for a manual identifier |
| **Update / comment** | `gh issue comment {n} --body ...`, optionally `gh issue close {n}` | `mcp__atlassian__editJiraIssue` + `addCommentToJiraIssue` | Update via Linear MCP | Skip |
| **Ticket link format** | `#{number}` (auto-links on GitHub) | `https://{tracker.url}/browse/{namespace}-XXX` | `https://linear.app/issue/{id}` | `{namespace}-XXX` (no URL) |
| **Setup** | none (uses `gh` CLI; `gh auth login`) | `claude mcp add --scope user --transport http atlassian https://mcp.atlassian.com/v1/mcp` | configure Linear MCP | none |

### GitHub Issues Adapter (`tracker.type: github`)

Uses the `gh` CLI (no MCP required). The repo is inferred from the current git remote.

```bash
# Fetch a ticket
gh issue view 247 --json title,body,labels,state,assignees

# Search
gh issue list --search "authentication endpoint" --state open

# Create (returns the new issue URL/number)
gh issue create --title "Add authentication endpoint" \
  --body "Implement JWT authentication for API" --label enhancement

# Comment / close on completion
gh issue comment 247 --body "Shipped in #251."
gh issue close 247
```

- Link format is the bare `#{number}`; GitHub auto-links it in PRs and commits.
- A PR that includes `Closes #247` in its body auto-closes the issue on merge, prefer this over a manual close.
- No `cloudId`/namespace concepts; the GitHub repo *is* the project scope.

The rest of this file documents the **Jira / Confluence adapter** (used only when `tracker.type` is `jira`). For Linear, configure its MCP server and follow the same dispatch rows.

## Jira / Confluence Adapter (Atlassian MCP)

Applies only when `tracker.type` is `jira`. **Setup:** say "init mcps" to configure the Atlassian MCP server.

### Fetching a Jira Ticket

**Tool:** `mcp__atlassian__getJiraIssue`

**Pattern:**

```typescript
mcp__atlassian__getJiraIssue({
  cloudId: "your-org.atlassian.net",  // Can be URL or UUID
  issueIdOrKey: "{namespace}-247"                // Ticket key (e.g., {namespace}-247)
})
```

**Key Points:**
- `cloudId` can be either:
  - Site URL: `"your-org.atlassian.net"`
  - Full Atlassian URL: `"https://your-org.atlassian.net"`
  - UUID: `"a7e53b72-ded0-45e3-8d7c-fd3573f46f1d"` (use `getAccessibleAtlassianResources` to find)
- `issueIdOrKey` accepts:
  - Issue key: `"{namespace}-247"` (preferred)
  - Issue ID: `"125103"` (numerical ID)

**Example - Extract from Jira URL:**

Given URL: `https://your-org.atlassian.net/browse/{namespace}-247`

Extract:
- `cloudId`: `"your-org.atlassian.net"` (domain)
- `issueIdOrKey`: `"{namespace}-247"` (ticket key after `/browse/`)

```typescript
mcp__atlassian__getJiraIssue({
  cloudId: "your-org.atlassian.net",
  issueIdOrKey: "{namespace}-247"
})
```

**Response Structure:**

The response includes:
- `key` - Ticket key (e.g., "{namespace}-247")
- `fields.summary` - Ticket title
- `fields.description` - Ticket description (plain text)
- `fields.status.name` - Current status (To Do, In Progress, Done)
- `fields.priority.name` - Priority level (Normal, High, etc.)
- `fields.assignee` - Assigned user object
- `fields.parent` - Parent epic/story object
- `fields.issuetype.name` - Type (Task, Bug, Story, Epic, etc.)
- `fields.created` - Creation timestamp
- `fields.updated` - Last update timestamp

### Searching Jira (Natural Language)

**Tool:** `mcp__atlassian__search` (recommended for general searches)

**Pattern:**

```typescript
mcp__atlassian__search({
  query: "authentication API endpoints"
})
```

**Use Cases:**
- Find tickets by keyword
- Search across Jira and Confluence simultaneously
- Natural language queries

**When to use JQL instead:** Only when you need advanced filtering (see below).

### Searching Jira with JQL

**Tool:** `mcp__atlassian__searchJiraIssuesUsingJql`

**Pattern:**

```typescript
mcp__atlassian__searchJiraIssuesUsingJql({
  cloudId: "your-org.atlassian.net",
  jql: "project = {namespace} AND status = 'In Progress' AND assignee = currentUser()",
  fields: ["summary", "description", "status", "assignee"],
  maxResults: 50
})
```

**Common JQL Examples:**

```jql
// Find unassigned tickets in current sprint
project = {namespace} AND sprint in openSprints() AND assignee is EMPTY

// Find bugs assigned to me
project = {namespace} AND type = Bug AND assignee = currentUser()

// Find tickets updated in last 7 days
project = {namespace} AND updated >= -7d

// Find tickets by epic
parent = {namespace}-31
```

**Key Points:**
- Use `fields` parameter to limit response size
- Default `maxResults` is 50, max is 100
- Use `nextPageToken` for pagination

### Creating a Jira Issue

**Tool:** `mcp__atlassian__createJiraIssue`

**Pattern:**

```typescript
mcp__atlassian__createJiraIssue({
  cloudId: "your-org.atlassian.net",
  projectKey: "{namespace}",
  issueTypeName: "Task",
  summary: "Add authentication endpoint",
  description: "Implement JWT authentication for API",
  assignee_account_id: "6090fadd7a30960069e9a02f",  // Optional
  parent: "{namespace}-31"  // Optional (for subtasks or stories under epic)
})
```

**Getting Issue Types:**

```typescript
// Get available issue types for a project
mcp__atlassian__getJiraProjectIssueTypesMetadata({
  cloudId: "your-org.atlassian.net",
  projectIdOrKey: "{namespace}"
})
```

**Common Issue Types:**
- Software projects: Epic, Story, Task, Bug, Subtask
- Service Management: Incident, Service Request, Change, Problem

### Updating a Jira Issue

**Tool:** `mcp__atlassian__editJiraIssue`

**Pattern:**

```typescript
mcp__atlassian__editJiraIssue({
  cloudId: "your-org.atlassian.net",
  issueIdOrKey: "{namespace}-247",
  fields: {
    summary: "Updated title",
    description: "Updated description",
    assignee: { accountId: "6090fadd7a30960069e9a02f" }
  }
})
```

### Transitioning a Jira Issue (Change Status)

**Step 1: Get Available Transitions**

```typescript
mcp__atlassian__getTransitionsForJiraIssue({
  cloudId: "your-org.atlassian.net",
  issueIdOrKey: "{namespace}-247"
})
```

**Step 2: Apply Transition**

```typescript
mcp__atlassian__transitionJiraIssue({
  cloudId: "your-org.atlassian.net",
  issueIdOrKey: "{namespace}-247",
  transition: { id: "21" }  // Transition ID from step 1
})
```

### Adding a Comment to Jira

**Tool:** `mcp__atlassian__addCommentToJiraIssue`

**Pattern:**

```typescript
mcp__atlassian__addCommentToJiraIssue({
  cloudId: "your-org.atlassian.net",
  issueIdOrKey: "{namespace}-247",
  commentBody: "This is a comment in **Markdown** format"
})
```

**With Visibility Restriction:**

```typescript
mcp__atlassian__addCommentToJiraIssue({
  cloudId: "your-org.atlassian.net",
  issueIdOrKey: "{namespace}-247",
  commentBody: "Internal comment",
  commentVisibility: {
    type: "role",      // or "group"
    value: "Developers"
  }
})
```

### Getting User Account IDs

**Tool:** `mcp__atlassian__lookupJiraAccountId`

**Pattern:**

```typescript
// Find user by display name or email
mcp__atlassian__lookupJiraAccountId({
  cloudId: "your-org.atlassian.net",
  searchString: "your-username"  // or "you@example.com"
})
```

**Get Current User:**

```typescript
mcp__atlassian__atlassianUserInfo()
```

## Confluence Integration

### Getting a Confluence Page

**Tool:** `mcp__atlassian__getConfluencePage`

**Pattern:**

```typescript
mcp__atlassian__getConfluencePage({
  cloudId: "your-org.atlassian.net",
  pageId: "123456789",           // Extract from URL
  contentFormat: "markdown"      // or "adf" (Atlassian Document Format)
})
```

**Extract Page ID from URL:**

URL: `https://your-org.atlassian.net/wiki/spaces/SPACE/pages/123456789/Page+Title`

Page ID: `"123456789"` (numerical ID in the middle)

### Getting Confluence Spaces

**Tool:** `mcp__atlassian__getConfluenceSpaces`

**Pattern:**

```typescript
mcp__atlassian__getConfluenceSpaces({
  cloudId: "your-org.atlassian.net",
  limit: 25
})
```

**Filter by Space Key:**

```typescript
mcp__atlassian__getConfluenceSpaces({
  cloudId: "your-org.atlassian.net",
  keys: ["ENG", "DOCS"]  // Space keys (use your Confluence space keys)
})
```

### Getting Pages in a Space

**Tool:** `mcp__atlassian__getPagesInConfluenceSpace`

**Pattern:**

```typescript
mcp__atlassian__getPagesInConfluenceSpace({
  cloudId: "your-org.atlassian.net",
  spaceId: "12345",  // Numerical space ID (get from getConfluenceSpaces)
  limit: 25
})
```

**Filter by Title:**

```typescript
mcp__atlassian__getPagesInConfluenceSpace({
  cloudId: "your-org.atlassian.net",
  spaceId: "12345",
  title: "API Documentation"
})
```

### Creating a Confluence Page

**Tool:** `mcp__atlassian__createConfluencePage`

**Pattern:**

```typescript
mcp__atlassian__createConfluencePage({
  cloudId: "your-org.atlassian.net",
  spaceId: "12345",
  title: "API Documentation",
  body: "# Heading\n\nContent in **Markdown**",
  contentFormat: "markdown",
  parentId: "123456789"  // Optional: create as child page
})
```

### Updating a Confluence Page

**Tool:** `mcp__atlassian__updateConfluencePage`

**Pattern:**

```typescript
mcp__atlassian__updateConfluencePage({
  cloudId: "your-org.atlassian.net",
  pageId: "123456789",
  body: "# Updated Content\n\nNew content here",
  contentFormat: "markdown",
  versionMessage: "Updated API documentation"  // Optional
})
```

### Searching Confluence with CQL

**Tool:** `mcp__atlassian__searchConfluenceUsingCql`

**Pattern:**

```typescript
mcp__atlassian__searchConfluenceUsingCql({
  cloudId: "your-org.atlassian.net",
  cql: "type = page AND title ~ 'API' AND space = ENG"
})
```

**Common CQL Examples:**

```cql
// Find pages by title
type = page AND title ~ "documentation"

// Find pages in space
type = page AND space = ENG

// Find pages created by user
type = page AND creator = currentUser()

// Find pages with label
type = page AND label = "api"
```

## Best Practices

### 1. Fetching Tickets

✅ **DO:**
- Use `mcp__atlassian__getJiraIssue` for fetching specific tickets
- Use site URL for `cloudId` (e.g., "your-org.atlassian.net")
- Use ticket key for `issueIdOrKey` (e.g., "{namespace}-247")

❌ **DON'T:**
- Don't try to parse Jira URLs manually
- Don't use web scraping or WebFetch for Jira content
- Don't hardcode UUIDs (use site URL instead)

### 2. Searching

✅ **DO:**
- Use `search()` for natural language queries across Jira and Confluence
- Use JQL only when you need advanced filtering
- Limit fields in responses to reduce data size

❌ **DON'T:**
- Don't use JQL for simple keyword searches
- Don't fetch all fields if you only need summary

### 3. Creating/Updating Content

✅ **DO:**
- Use Markdown format for descriptions and comments
- Provide clear, descriptive summaries
- Add version messages when updating Confluence pages

❌ **DON'T:**
- Don't create duplicate tickets (search first)
- Don't update tickets without checking current state

## Common Issues & Solutions

### Issue: "Failed to fetch ticket"
**Solution:** Verify `cloudId` is correct. Use site URL (e.g., "your-org.atlassian.net") or run `getAccessibleAtlassianResources` to get UUID.

### Issue: "Ticket not found"
**Solution:**
1. Check ticket key is correct (case-sensitive)
2. Verify you have permission to view the ticket
3. Ensure ticket exists in the specified project

### Issue: "Authentication failed" or 401 Unauthorized
**Symptoms:**
- MCP tools return `{"code":401,"message":"Unauthorized"}` error
- Operations that previously worked now fail with authentication errors
- This typically happens when the MCP session expires

**Solution:**
1. Re-authenticate with Atlassian MCP:
   ```bash
   claude mcp add --scope user --transport http atlassian https://mcp.atlassian.com/v1/mcp
   ```
   This will open your browser to re-authenticate.

2. Verify the connection after re-authentication:
   ```bash
   claude mcp list | grep atlassian
   ```
   You should see: `atlassian: https://mcp.atlassian.com/v1/mcp (HTTP) - ✓ Connected`

3. Retry your MCP operation (e.g., `mcp__atlassian__getJiraIssue`)

**Important Notes:**
- MCP sessions can expire and require re-authentication
- If you encounter 401 errors mid-workflow, inform the user and ask them to re-authenticate
- After re-authentication, you can resume the workflow from where it failed
- Always handle 401 errors gracefully - don't let them block the entire workflow

### Issue: "Invalid issue type"
**Solution:** Use `getJiraProjectIssueTypesMetadata` to get valid issue types for the project.

### Issue: "Cannot transition issue"
**Solution:** Use `getTransitionsForJiraIssue` to get valid transitions for the current issue state.

## Error Handling Best Practices

### Graceful Degradation
When MCP operations fail (especially authentication errors), workflows should continue gracefully:

**DO:**
- ✅ Catch authentication errors and inform the user
- ✅ Continue with other workflow steps that don't depend on MCP
- ✅ Provide clear instructions for fixing authentication issues
- ✅ Allow workflows to complete even if Jira/Confluence updates fail

**DON'T:**
- ❌ Let MCP failures block the entire workflow
- ❌ Silently fail without informing the user
- ❌ Assume MCP is always available

**Example Pattern:**
```text
Try to update Jira ticket
  → If 401: Warn user "Jira MCP authentication expired. Run: claude mcp add ..."
  → Continue with rest of workflow
  → User can manually update ticket later
```

## Reference

- MCP Setup: `.claude/skills/ar-init-mcps/`
- Atlassian REST API: https://developer.atlassian.com/cloud/jira/platform/rest/v3/
- JQL Reference: https://support.atlassian.com/jira-service-management-cloud/docs/use-advanced-search-with-jira-query-language-jql/
- CQL Reference: https://developer.atlassian.com/cloud/confluence/confluence-query-language/
