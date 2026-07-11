---
name: ar-init-mcps
description: Initialize issue-tracker integration for Claude Code. For GitHub Issues (the default) this verifies the gh CLI is authenticated, no MCP needed. For Jira (Atlassian) or Linear it sets up the Model Context Protocol (MCP) server. Say "ar-init-mcps" or "setup mcps".
disable-model-invocation: true
---

# Initialize Issue-Tracker Integration

Set up the integration for the project's configured issue tracker.

## When to Use

- First time wiring up the project's issue tracker
- ar-taskflow needs ticket access but the integration isn't configured
- User says "ar-init-mcps", "setup mcps", or "configure mcp"

## Step 0: Resolve the Tracker (do this FIRST)

Read `tracker.type` from `.claude/config_hints.json` (under `project`). Branch on it -
this is the same `tracker` seam as the Tracker Dispatch Table in
`<standards_location>/mcp-integration.md` (resolve `standards_location` from `.claude/config_hints.json`):

```bash
TRACKER=$(jq -r '.project.tracker.type // "github"' .claude/config_hints.json 2>/dev/null)
```

| `tracker.type` | What this skill does |
|----------------|----------------------|
| **`github`** (default) | **No MCP needed**, GitHub Issues uses the `gh` CLI. Just verify `gh auth status` (see below). |
| **`jira`** | Set up the Atlassian MCP server (Jira / Confluence), see the Atlassian section. |
| **`linear`** | Set up the Linear MCP server, then follow the same dispatch rows. |
| **`none`** | Nothing to configure, identifiers are managed manually. |

### GitHub Issues path (`tracker.type: github`)

No MCP server is required. Verify the `gh` CLI is installed and authenticated:

```bash
gh auth status
```

- If authenticated, you're done, ar-taskflow uses `gh issue ...` directly.
- If not, run `gh auth login` and re-check.
- If `gh` is missing, install it (`brew install gh` / your platform's package manager).

The rest of this skill is the **MCP setup path**, used only when `tracker.type` is `jira`
(Atlassian) or `linear`.

## What are MCP Servers?

MCP servers allow Claude Code to:
- Fetch Jira tickets and issues
- Read/write Confluence pages
- Access other external services
- Integrate with your development tools

## Checking Current MCP Status

Before setting up, check if MCP servers are already configured:

```bash
claude mcp list
```

If the command returns servers, MCP is already configured. Ask user if they want to add more.

## Available MCP Servers

### 1. Atlassian (Jira & Confluence)

**What it provides:**
- Read Jira tickets and issues
- Create/update Jira issues and descriptions
- Add comments to Jira tickets
- Read Confluence pages
- Search across Jira and Confluence

**ar-taskflow Integration:**
- Start tasks from Jira tickets (ticket-first approach)
- Automatically update ticket description when task completes
- Archive original description to comments
- Add completion status and branch info

**Setup command:**
```bash
claude mcp add --scope user --transport http atlassian https://mcp.atlassian.com/v1/mcp
```

**After setup:**
1. You'll be prompted to authenticate via browser
2. Grant permissions to Claude Code
3. Server will be available immediately

**Enables in ar-taskflow:**
- Ticket-first approach: Start tasks from Jira URLs
- Auto-fetch ticket descriptions to raw_prompt.md
- Auto-update tickets on completion with:
  - Original description archived to comments
  - Updated description from ticket.md
  - Completion status and branch info

### 2. Linear (`tracker.type: linear`)

Configure the Linear MCP server, then drive it through the same dispatch rows in
`<standards_location>/mcp-integration.md` (fetch / search / create / update / link).

### 3. Future MCP Servers

As more MCP servers become available, add them here:
- Slack MCP (when available)

(GitHub Issues needs no MCP, it uses the `gh` CLI; see Step 0.)

## Setup Flow

### Step 1: Check Existing Configuration

```bash
claude mcp list
```

### Step 2: Add Atlassian MCP

If not already configured:

```
To integrate with Jira and Confluence, run:

  claude mcp add --scope user --transport http atlassian https://mcp.atlassian.com/v1/mcp

This will:
1. Open your browser for authentication
2. Ask for Jira/Confluence permissions
3. Enable Claude to read/write tickets and pages

After setup, you can:
- Fetch Jira tickets by URL or ID
- Create tasks from Jira descriptions
- Search Confluence documentation
- Create/update Jira issues directly
```

### Step 3: Verify Setup

After user runs the command:

```bash
claude mcp list
```

Should show:
```
atlassian (http://...)
```

### Step 4: Test Connection

Try fetching a test resource to verify:

Ask user: "Do you have a Jira ticket URL I can test with?"

If yes, attempt to fetch it using MCP tools.

## Troubleshooting

### "Command not found: claude mcp"

User needs to update Claude Code CLI:
```bash
npm update -g @anthropic-ai/claude-code
```

### "Authentication failed"

1. Check browser didn't block the auth popup
2. Try running the add command again
3. Ensure user has access to Atlassian instance

### "Permission denied"

MCP scope might be wrong. Use `--scope user` for user-level config.

## Integration with Task Flow

When `ar-taskflow` needs tracker access (for the ticket-first approach), it resolves
`tracker.type` first:
1. **github**, verify `gh auth status`; no MCP step.
2. **jira / linear**, check the MCP server is configured; if not, invoke this skill to set it up, then continue.
3. **none**, skip; identifiers are managed manually.

## Quick Reference

| Command | Purpose |
|---------|---------|
| `claude mcp list` | Show configured servers |
| `claude mcp add ...` | Add new server |
| `claude mcp remove <name>` | Remove server |
| `claude mcp test <name>` | Test server connection |

## Notes

- MCP configuration is stored at user level (not project level)
- Once configured, available across all projects
- Credentials are managed securely by Claude Code
- Can add multiple MCP servers simultaneously
