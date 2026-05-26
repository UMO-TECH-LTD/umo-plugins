---
name: jira-tracker-setup
description: First-run setup wizard for umo-jira-tracker. Verifies bd, glab, Atlassian MCP, and optional GitLab MCP; collects sync scope (all open vs active sprint); writes or updates .umo/jira-tracker.json. Use when setting up the plugin in a new repo or reconfiguring an existing installation.
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

### Sync scope presets

`/sync` reads `jira.syncJql` from config. Offer two presets during setup — do not ask the developer to type raw JQL unless they explicitly want a custom query:

| Preset | Label | `syncJql` value |
|--------|-------|-----------------|
| `all-open` | All open assigned tickets | `assignee = currentUser() AND statusCategory != Done` |
| `active-sprint` | Active sprint only | `assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done` |

Helper — map an existing `syncJql` back to a label for display:

- exact match on either preset → show the preset label
- anything else → show `Custom` and print the stored JQL verbatim

When Atlassian MCP is connected, optionally dry-run both presets before the developer chooses:

```
CallMcpTool -> Atlassian / searchJiraIssuesUsingJql
  cloudId: "{cloudId}"
  jql: "{preset JQL}"
  maxResults: 0
```

Show the `total` from each preset so the developer can compare (e.g. 42 all-open vs 4 active-sprint). Skip the dry-run if MCP is unavailable — fall back to the choice prompt only.

### Existing config

If `.umo/jira-tracker.json` already exists, read it and present a diff-style summary of current values before asking about changes:

```
Current config (.umo/jira-tracker.json):
  jira.cloudUrl          = https://umotech.atlassian.net
  jira.defaultProjectKey = CWN
  jira.syncScope         = All open assigned tickets
  jira.syncJql           = assignee = currentUser() AND statusCategory != Done
  jira.transitionOnMr    = In Review
  jira.transitionOnClose = Done
  gitlab.remote          = origin
  gitlab.projectId       = 110
  gitlab.targetBranch    = dev
  gitlab.mrTool          = glab
  user.jiraDisplayName   = Jane Doe (712020:abc123...)
  user.gitlabUsername    = @jane.doe (id: 4567)

Update any values? (yes/no — defaults to no)
```

When re-running setup with `--force` or when the user explicitly asks to refresh identity, re-run Step 5 to fetch fresh JIRA and GitLab user data.

When the developer chooses to update an existing config, re-prompt for sync scope (with optional MCP dry-run counts) along with the other fields below.

### Fresh config questions

Ask each question with a sensible default shown (fresh install or update):

| Question | Default |
|----------|---------|
| JIRA cloud URL | `https://umotech.atlassian.net` |
| Default JIRA project key | (detect from Atlassian MCP accessible resources) |
| Sync scope (`/sync`) | Present the two presets above; default `all-open` |
| Sync direction | `both` (pull + push). Alternatives: `pull` only, `push` only |
| Push Sub-tasks by default? | `no` — Sub-task beads are skipped unless opted-in per bead. Alternative: `yes` to push everything |
| JIRA transition name when MR created | `In Review` |
| JIRA transition name when bead closed | `Done` |
| Git remote name | `origin` |
| GitLab project ID (leave blank to auto-resolve on first /mr) | (blank) |
| Default target branch for MRs | `dev` |
| Preferred MR tool (`glab` or `mcp`) | `glab` |

**Sync direction prompt:**

```
What should /sync do?

  1) Both (default) — pull JIRA into Beads, then push unsynced beads back to JIRA
  2) Pull only      — keep Beads aligned with JIRA; never create JIRA issues from beads
  3) Push only      — only promote local beads; useful when JIRA is read-only for you

Choice [1]:
```

Store the choice as `sync.direction` (`both` / `pull` / `push`).

**Sub-task policy prompt:**

```
Push sub-tasks by default?

  Sub-tasks are usually small implementation items that the team prefers to keep
  in Beads. The default answer is NO. A bead can still be force-pushed by adding
  the `jira-push` label to it.

  yes / no [no]:
```

Store the answer as `sync.pushSubtasks` (`true` / `false`).

**Sync scope prompt** — present as a numbered choice, not a free-text JQL field:

```
What should /sync pull from JIRA?

  1) All open assigned tickets (default)
     assignee = currentUser() AND statusCategory != Done
     → {totalAllOpen} issues  (omit counts if dry-run skipped)

  2) Active sprint only
     assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done
     → {totalActiveSprint} issues

  3) Custom JQL (advanced — only if the developer asks)

Choice [1]:
```

Write the selected preset's JQL into `jira.syncJql`. For option 3, accept custom JQL and store it verbatim.

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

## Step 5 — Resolve user identity (automatic)

Fetch the developer's JIRA account ID and GitLab user information automatically. This enables auto-assignment of tickets and MRs without prompting.

### JIRA account ID

```
CallMcpTool -> Atlassian / getAccessibleAtlassianResources
```

Then fetch the current user's profile:

```
CallMcpTool -> Atlassian / getJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "myself"
```

If the Atlassian MCP exposes a `myself` or `currentUser` endpoint, use it. Otherwise search for the current user via a JQL query:

```
CallMcpTool -> Atlassian / searchJiraIssuesUsingJql
  cloudId: "{cloudId}"
  jql: "assignee = currentUser() ORDER BY created DESC"
  maxResults: 1
  fields: ["assignee"]
```

Extract `assignee.accountId` and `assignee.displayName` from the result.

### GitLab user info

```bash
glab api user
```

Extract `id` (numeric GitLab user ID) and `username` from the JSON response.

### Store identity

Add to the config object (do not prompt — this is automatic):

```json
"user": {
  "jiraAccountId": "{accountId}",
  "jiraDisplayName": "{displayName}",
  "gitlabUserId": {numericId},
  "gitlabUsername": "{username}"
}
```

If either lookup fails (MCP unavailable, `glab` not authed), set the corresponding fields to `null` and note it in the final report. The plugin works without these values — auto-assignment is skipped when the fields are null.

## Step 6 — Final report

```
Setup complete!

  Config:  .umo/jira-tracker.json  ✓
  bd:      <version>               ✓
  glab:    <version>, authenticated ✓
  Atlassian MCP: connected         ✓
  GitLab MCP: <connected|not configured — glab fallback active>

  User identity:
    JIRA:   {jiraDisplayName} ({jiraAccountId})
    GitLab: @{gitlabUsername} (id: {gitlabUserId})

Sync scope: {syncScopeLabel}
  JQL: {syncJql}

Next steps:
  /umo-jira-tracker:sync       Pull your unresolved JIRA tickets into Beads
  /umo-jira-tracker:work       Start working on a ticket
```

## Config schema reference

`jira.syncJql` holds the effective query — setup writes one of the presets above (or custom JQL). There is no separate `syncScope` field; derive the label from the stored JQL when displaying config.

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
  },
  "sync": {
    "direction": "both",
    "pushSubtasks": false,
    "pushLabel": "jira-push",
    "skipLabel": "jira-skip",
    "recentlyDoneWindow": "-14d"
  },
  "user": {
    "jiraAccountId": null,
    "jiraDisplayName": null,
    "gitlabUserId": null,
    "gitlabUsername": null
  }
}
```

### `sync` block reference

| Key | Default | Meaning |
|-----|---------|---------|
| `sync.direction` | `both` | `both` / `pull` / `push`. Controls which phases of `/sync` run by default |
| `sync.pushSubtasks` | `false` | When `false`, sub-task candidates are skipped during push unless they carry `{sync.pushLabel}` |
| `sync.pushLabel` | `jira-push` | Bead label that forces inclusion in push (overrides Sub-task skip and per-run dry-run cherry-pick defaults) |
| `sync.skipLabel` | `jira-skip` | Bead label that forces exclusion from push regardless of any other rule |
| `sync.recentlyDoneWindow` | `-14d` | JQL relative time window for the recently-Done pull extension (Phase A drift detection) |
