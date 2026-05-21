---
name: jira-tracker-setup
description: First-run setup wizard for umo-jira-tracker. Verifies bd, glab, Atlassian MCP, and optional GitLab MCP; writes or updates .umo/jira-tracker.json. Use when setting up the plugin in a new repo or reconfiguring an existing installation.
paths:
  - ".umo/jira-tracker.json"
  - ".umo/"
---

# JIRA Tracker Setup

Use this skill when the user runs `/umo-jira-tracker:setup` or when `.umo/jira-tracker.json` is absent and another command needs it.

## Goals

1. Verify all required tools are available and authenticated.
2. Collect per-repo config values interactively.
3. Write `.umo/jira-tracker.json` — non-destructively if the file already exists.
4. Never store credentials.

## Step 1 — Verify tools

Run each check and report a clear pass/fail:

```bash
# bd
command -v bd && bd --version
# glab
command -v glab && glab version
# glab auth
glab auth status
```

For Atlassian MCP: call `getAccessibleAtlassianResources`. If it succeeds, auth is working. If it fails, print:

```
Atlassian MCP is not configured or not authenticated.
Add it to your mcp.json:
  "Atlassian": { "url": "https://mcp.atlassian.com/v1/mcp", "headers": {} }
Then authenticate in the Atlassian MCP browser popup.
```

For GitLab MCP (optional): call any lightweight tool (e.g. list projects). If unavailable, note it and confirm `glab` will be the fallback — this is fine and expected.

If `bd` or `glab` is missing, print install instructions from the plugin README and abort with:

```
Setup cannot continue until the missing tools are installed.
Re-run /umo-jira-tracker:setup after installation.
```

If `glab auth status` shows "not logged in":

```
glab is installed but not authenticated.
Run: glab auth login
Or set GITLAB_TOKEN in your shell (~/.zshenv on macOS).
Re-run /umo-jira-tracker:setup after authentication.
```

## Step 2 — Collect config

If `.umo/jira-tracker.json` already exists, read it and present a diff-style summary of current values before asking about changes:

```
Current config (.umo/jira-tracker.json):
  jira.cloudUrl          = https://umotech.atlassian.net
  jira.defaultProjectKey = CWN
  jira.syncJql           = assignee = currentUser() AND statusCategory != Done
  jira.transitionOnMr    = In Review
  jira.transitionOnClose = Done
  gitlab.remote          = origin
  gitlab.projectId       = 110
  gitlab.targetBranch    = dev
  gitlab.mrTool          = glab

Update any values? (yes/no — defaults to no)
```

If creating fresh, ask each question with a sensible default shown:

| Question | Default |
|----------|---------|
| JIRA cloud URL | `https://umotech.atlassian.net` |
| Default JIRA project key | (detect from Atlassian MCP accessible resources) |
| Sync JQL (scope of /sync) | `assignee = currentUser() AND statusCategory != Done` |
| JIRA transition name when MR created | `In Review` |
| JIRA transition name when bead closed | `Done` |
| Git remote name | `origin` |
| GitLab project ID (leave blank to auto-resolve on first /mr) | (blank) |
| Default target branch for MRs | `dev` |
| Preferred MR tool (`glab` or `mcp`) | `glab` |

Detect the project key from Atlassian MCP accessible resources if possible:

```
CallMcpTool -> Atlassian / getAccessibleAtlassianResources
```

Extract the first resource's `name` and present it as a suggestion.

## Step 3 — Write config

Construct the config object and show a preview before writing:

```
About to write .umo/jira-tracker.json:
<pretty-printed JSON>

Proceed? (yes/no)
```

On approval, create `.umo/` if absent and write the file. Never include API tokens, passwords, or access keys.

## Step 4 — Resolve GitLab project ID (optional)

If `gitlab.projectId` is null and `glab` is authenticated, offer to resolve it now:

```bash
# from the repo root
git remote get-url origin
# extract the path component, then:
glab api "projects?search=<repo-name>&membership=true" | python3 -c "import json,sys; p=json.load(sys.stdin); [print(x['id'], x['path_with_namespace']) for x in p]"
```

Present the matches and ask the developer to confirm. On confirmation, update `gitlab.projectId` in the config. Persist with another approval gate.

## Step 5 — Final report

```
Setup complete!

  Config:  .umo/jira-tracker.json  ✓
  bd:      <version>               ✓
  glab:    <version>, authenticated ✓
  Atlassian MCP: connected         ✓
  GitLab MCP: <connected|not configured — glab fallback active>

Next steps:
  /umo-jira-tracker:sync       Pull your unresolved JIRA tickets into Beads
  /umo-jira-tracker:work       Start working on a ticket
```

## Config schema reference

```json
{
  "jira": {
    "cloudUrl": "https://yourorg.atlassian.net",
    "defaultProjectKey": "CWN",
    "syncJql": "assignee = currentUser() AND statusCategory != Done",
    "transitionOnMr": "In Review",
    "transitionOnClose": "Done"
  },
  "gitlab": {
    "remote": "origin",
    "projectId": null,
    "targetBranch": "dev",
    "mrTool": "glab"
  },
  "beads": {
    "labelPrefix": "jira",
    "titleFormat": "[{key}] {summary}",
    "epicTypes": ["Epic", "Story"],
    "taskTypes": ["Task", "Bug", "Sub-task"]
  }
}
```
