# GitLab MCP reference for MR creation

Call shapes for the GitLab MCP tools used in Phase 2 and Phase 6 of `/mr`, as the **fallback** to `glab` (default/preferred — see `SKILL.md` and `references/glab.md`). Exact tool/server names depend on which GitLab MCP server is configured in the host (Cursor/Claude/Codex settings) — this plugin ships no MCP config of its own. Adjust the server identifier used in `CallMcpTool` to whatever is configured locally.

## Resolve a numeric project ID

```
CallMcpTool -> GitLab / search
  scope: "projects"
  search: "<repo-name-or-path>"
```

Prefer the numeric `id` field from the result over URL-encoded paths (e.g. `group%2Fsubgroup%2Frepo`), which can be unreliable across GitLab MCP implementations.

## Check for an existing open MR on a branch

```
CallMcpTool -> GitLab / search
  scope: "merge_requests"
  search: "<branch-name>"
  project_id: "<gitlab-project-id>"
  state: "opened"
```

If a result is returned, surface its title, IID, and web URL to the developer before proceeding — never silently create a duplicate MR.

## Create a merge request

```
CallMcpTool -> GitLab / create_merge_request
  id: "<gitlab-project-id>"
  title: "<MR title>"
  source_branch: "<source-branch>"
  target_branch: "<target-branch>"
  description: "<MR description markdown>"
```

Optional fields commonly supported (check the configured server's schema via `GetMcpTools` before relying on these):

- `assignee_ids`: array of GitLab user IDs
- `labels`: comma-separated string or array of label names
- `remove_source_branch`: boolean
- `squash`: boolean — set `true` to match the UMO squash-merge default when the server supports it directly (otherwise squash is a project/MR setting configured in GitLab, and `--squash-before-merge` via `glab` is the more reliable lever)

## After creation

The `create_merge_request` response typically includes a `web_url` — always report this back to the developer as the MR link.

## When to use this fallback

Use GitLab MCP only when `glab` is not installed, not authenticated, or a `glab` call fails (or when `.umo/mr.json` explicitly sets `gitlab.mrTool: "mcp"`, making MCP the primary path and `glab` the fallback for that repo). Report to the developer which path (glab vs MCP) succeeded.
