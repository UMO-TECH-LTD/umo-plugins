---
name: jira-tracker-setup
description: First-run setup wizard for umo-jira-tracker. Verifies bd, glab, Atlassian MCP, and optional GitLab MCP; collects the squad project key and sync scope (all open, one flow, or one slice); writes or updates .umo/jira-tracker.json. Use when setting up the plugin in a new repo or reconfiguring an existing installation.
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

`/sync` reads `jira.syncJql` from config. Offer these presets during setup — do not ask the developer to type raw JQL unless they explicitly want a custom query:

| Preset | Label | `syncJql` value |
|--------|-------|-----------------|
| `all-open` | All open assigned issues | `assignee = currentUser() AND statusCategory != Done` |
| `flow` | One flow, everything serving it | `issuekey in portfolioChildIssuesOf("{FLOW-KEY}")` |
| `slice` | One slice | `parent = {SLICE-KEY} OR issuekey = {SLICE-KEY}` |

There is no active-sprint preset — the Sprint field is unused org-wide. If a
developer asks for one, say so and offer the flow preset instead: the flow view
is the org's equivalent, and it crosses projects.

Helper — map an existing `syncJql` back to a label for display:

- exact match on a preset → show the preset label
- anything else → show `Custom` and print the stored JQL verbatim

When Atlassian MCP is connected, optionally dry-run the presets before the developer chooses:

```
CallMcpTool -> Atlassian / searchJiraIssuesUsingJql
  cloudId: "{cloudId}"
  jql: "{preset JQL}"
  maxResults: 0
```

Show the `total` from each preset so the developer can compare. Skip the dry-run if MCP is unavailable — fall back to the choice prompt only.

### Existing config

If `.umo/jira-tracker.json` already exists, read it and present a diff-style summary of current values before asking about changes:

```
Current config (.umo/jira-tracker.json):
  jira.cloudUrl          = https://umotech.atlassian.net
  jira.defaultProjectKey = PAY
  jira.syncScope         = All open assigned issues
  jira.syncJql           = assignee = currentUser() AND statusCategory != Done
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
| Squad project key | (detect from Atlassian MCP accessible resources; must be one of the ten squad keys below) |
| Sync scope (`/sync`) | Present the presets above; default `all-open` |
| Sync direction | `both` (pull + push). Alternatives: `pull` only, `push` only |
| JIRA transition name when bead closed | `Done` |
| Git remote name | `origin` |
| GitLab project ID (leave blank to auto-resolve on first /mr) | (blank) |
| Default target branch for MRs | `dev` |
| Preferred MR tool (`glab` or `mcp`) | `glab` |

Do **not** ask about sprints, story points, estimates or sub-task pushing. None of
them exist in the org's encoding.

There is no `transitionOnMr`. MR creation never transitions Jira — a developer may
open several MRs for one ticket, and Task Done belongs to the merged-PR automation.

**Squad project keys.** Projects match squads, one team backlog each:

| Key | Project |
|---|---|
| PLAT | Platform |
| DATA | Data |
| AI | AI |
| EXP | Experience *(squad: Customer Experience)* |
| CRY | Crypto |
| PAY | Payments |
| CARD | Cards |
| FIN | Financial Core *(squad: Transactions & Accounting)* |
| CMP | Compliance/Support |
| BO | Backoffice Portal |

If the detected or entered key is not in this list, ask the developer to confirm
it. A key outside the squad map is usually a legacy project, and the five-type
model will not hold there.

**Sync direction prompt:**

```
What should /sync do?

  1) Both (default) — pull JIRA into Beads, then push unsynced beads back to JIRA
  2) Pull only      — keep Beads aligned with JIRA; never create JIRA issues from beads
  3) Push only      — only promote local beads; useful when JIRA is read-only for you

Choice [1]:
```

Store the choice as `sync.direction` (`both` / `pull` / `push`).

Mention what push actually does, so the choice is informed:

```
Push promotes a bead into a JIRA Task or Bug under a Slice. It never creates
Flows, Slices or Requests, and it never mirrors your execution plan — steps
inside one Task stay in Beads.
```

**Sync scope prompt** — present as a numbered choice, not a free-text JQL field:

```
What should /sync pull from JIRA?

  1) All open assigned issues (default)
     assignee = currentUser() AND statusCategory != Done
     → {totalAllOpen} issues  (omit counts if dry-run skipped)

  2) One flow — everything serving it, across all projects
     issuekey in portfolioChildIssuesOf("{FLOW-KEY}")

  3) One slice
     parent = {SLICE-KEY} OR issuekey = {SLICE-KEY}

  4) Custom JQL (advanced — only if the developer asks)

Choice [1]:
```

For options 2 and 3, ask for the flow or slice key and substitute it. For option 4, accept custom JQL and store it verbatim. Write the result into `jira.syncJql`.

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
    "cloudUrl": "https://umotech.atlassian.net",
    "defaultProjectKey": "PAY",
    "syncJql": "assignee = currentUser() AND statusCategory != Done",
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
    "containerTypes": ["Flow", "Slice"],
    "workTypes": ["Task", "Bug", "Request"],
    "creatableTypes": ["Task", "Bug"]
  },
  "sync": {
    "direction": "both",
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

### `beads` block reference

| Key | Default | Meaning |
|-----|---------|---------|
| `beads.containerTypes` | `["Flow", "Slice"]` | JIRA types that pull down as `epic` beads |
| `beads.workTypes` | `["Task", "Bug", "Request"]` | JIRA types that pull down as `task` beads |
| `beads.creatableTypes` | `["Task", "Bug"]` | The only types this plugin may create. Widening this list does **not** make Story or Sub-task work — they do not exist in the org's Jira |

### `sync` block reference

| Key | Default | Meaning |
|-----|---------|---------|
| `sync.direction` | `both` | `both` / `pull` / `push`. Controls which phases of `/sync` run by default |
| `sync.skipLabel` | `jira-skip` | Bead label that forces exclusion from push regardless of any other rule |
| `sync.recentlyDoneWindow` | `-14d` | JQL relative time window for the recently-closed pull extension (Phase A drift detection) |

There is no `pushSubtasks` or `pushLabel` key. Sub-tasks do not exist, and push is
opt-**out** by design: the classifier already declines anything that is not a unit
of delivery, so an opt-in label would only be a way to override a rule that exists
for a reason.

### Keys deliberately absent

| Key | Why |
|---|---|
| `jira.defaultSprintId` | the Sprint field is unused org-wide |
| `jira.transitionOnMr` | MR creation never transitions Jira; Task Done belongs to the merged-PR automation |
| `sync.pushSubtasks`, `sync.pushLabel` | see above |

If you find these in an existing config, drop them during the update pass and tell
the developer why.
