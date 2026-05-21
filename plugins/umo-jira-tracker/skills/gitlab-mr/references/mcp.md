# GitLab MCP Reference

Use the GitLab MCP as the **preferred** path for MR creation when it is configured and working. Fall back to `glab` if the MCP is unavailable or returns an error.

## Configure GitLab MCP

Add to your Cursor / Claude `mcp.json`:

```json
{
  "mcpServers": {
    "gitlab": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@zereight/mcp-gitlab"],
      "env": {
        "GITLAB_PERSONAL_ACCESS_TOKEN": "${env:GITLAB_PERSONAL_ACCESS_TOKEN}",
        "GITLAB_API_URL": "https://gitlab.com/api/v4"
      }
    }
  }
}
```

## Resolve project ID

Prefer numeric IDs. URL-encoded paths (e.g. `group%2Frepo`) may not work with all tool versions.

If the project ID is not already stored in `.umo/jira-tracker.json`, use the search tool:

```
CallMcpTool -> gitlab / search
  scope: "projects"
  search: "<repo-name>"
```

Pick the matching numeric `id` and persist it to config.

## Check for an existing open MR

```
CallMcpTool -> gitlab / search
  scope: "merge_requests"
  search: "<branch-name>"
  project_id: "<numeric-id>"
  state: "opened"
```

## Create MR

```
CallMcpTool -> gitlab / create_merge_request
  id: "<numeric-project-id>"
  title: "<MR title>"
  source_branch: "<source-branch>"
  target_branch: "<target-branch>"
  description: "<MR description markdown>"
```

Report the returned `web_url` to the developer on success.

## Fallback order

1. GitLab MCP `create_merge_request` (when configured and working).
2. **`glab mr create`** (see `references/glab.md`) when MCP is missing or errors.
3. Manual: output the MR title and description as a copyable block for the GitLab UI.
