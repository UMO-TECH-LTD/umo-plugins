# umo-jira-tracker

Automates the daily developer JIRA workflow by linking JIRA tickets to a local [Beads](https://beads.umo.dev) (`bd`) database, guiding bead-by-bead implementation, creating GitLab MRs with STD-JIRA naming, and **bidirectionally** syncing between Beads (the local source of truth) and JIRA.

## Slash commands

| Command | Purpose |
|---------|---------|
| `/umo-jira-tracker:setup` | First-run wizard: verify tools, write `.umo/jira-tracker.json` |
| `/umo-jira-tracker:sync [--dry-run] [--jql "..."] [--pull-only\|--push-only]` | Two-way sync: pull JIRA→Beads, then push locally-created beads → JIRA, then reconcile status drift |
| `/umo-jira-tracker:work [KEY\|bead-id\|--ready]` | Claim a bead, discuss AC with AI, push refinements back to JIRA |
| `/umo-jira-tracker:create [type] [--parent KEY]` | Create a new JIRA issue with mandatory parent linkage |
| `/umo-jira-tracker:commit` | Group staged changes into conventional commits, generate MR description |
| `/umo-jira-tracker:mr` | Create a GitLab MR and sync JIRA (comment + transition) |
| `/umo-jira-tracker:close [bead-id]` | Close the bead and transition JIRA to Done |

## Skills

| Skill | Purpose |
|-------|---------|
| `jira-tracker-setup` | Tool verification + config writer |
| `jira-sync` | JIRA → Beads pull (Phase A of `/sync`) |
| `jira-push` | Beads → JIRA reverse-sync (Phase B of `/sync`) |
| `jira-bead-bridge` | Claim, discuss, refine, push AC back to JIRA |
| `gitlab-mr` | glab / GitLab MCP MR creation reference |
| `jira-sync-back` | All JIRA mutations: comments, transitions, issue creation |

## Prerequisites

| Tool | Purpose | How to get |
|------|---------|------------|
| `bd` | Local Beads CLI | Follow your org's Beads install guide |
| `glab` | GitLab CLI for MR creation | `brew install glab` or see [glab docs](https://gitlab.com/gitlab-org/cli) |
| Atlassian MCP | JIRA read/write | Configure in Cursor Settings → MCP |
| GitLab MCP (optional) | Alternative MR creation | Configure `@zereight/mcp-gitlab` in Cursor Settings → MCP |

### glab authentication

```bash
glab auth login
# or set GITLAB_TOKEN / GITLAB_ACCESS_TOKEN with api scope in your shell (~/.zshenv on macOS)
export GITLAB_TOKEN="<your-token>"
```

### Atlassian MCP

Add to your Cursor / Claude `mcp.json`:

```json
{
  "mcpServers": {
    "Atlassian": {
      "url": "https://mcp.atlassian.com/v1/mcp",
      "headers": {}
    }
  }
}
```

No API key is stored in this plugin. Authentication is handled by the MCP host.

### GitLab MCP (optional)

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

## Per-repo configuration

Run `/umo-jira-tracker:setup` to generate `.umo/jira-tracker.json`. The file is safe to commit (no secrets).

During setup you choose the `/sync` scope:

| Scope | JQL |
|-------|-----|
| All open assigned tickets (default) | `assignee = currentUser() AND statusCategory != Done` |
| Active sprint only | `assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done` |

Example config (all open):

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

## JIRA → Beads mapping (pull direction)

| JIRA type | Bead type | Parent bead |
|-----------|-----------|-------------|
| Epic | epic | none |
| Story | epic | parent Epic-bead (if linked) |
| Task / Bug | task | parent Epic-bead (if linked) |
| Sub-task | task | parent Story-epic-bead |

Bead title format: `[CWN-1234] <JIRA summary>`
Bead labels: `jira:CWN-1234`, `jira-type:story`, `jira-status:in-progress`, `jira-origin:bead` (only set for beads that were promoted via push).

Pull also includes a **recently-Done window** (`sync.recentlyDoneWindow`, default `-14d`) so JIRA tickets closed while you were offline still trigger a local bead close.

## Beads → JIRA mapping (push direction)

Source of truth: **Beads.** Any open bead with no `jira:` label is a push candidate when `/sync` runs (unless `sync.direction` is set to `pull`).

| Bead `type` | Parent context | Proposed JIRA type | Default action |
|-------------|----------------|---------------------|----------------|
| `epic` | no parent | Epic | requires `create epic` phrase |
| `epic` | parent is JIRA Epic | Story | create |
| `task` / `chore` / `feature` | no parent | Task | orphan warning (`create unlinked` required) |
| `task` / `chore` / `feature` | parent is JIRA Epic | Task | create |
| `task` / `chore` / `feature` | parent is JIRA Story / Task / Bug | Sub-task | **skipped** unless bead has `jira-push` label or `sync.pushSubtasks=true` |
| `bug` | parent is JIRA Epic / Story | Bug | create |
| `decision` | any | — | always skipped (ADRs stay local) |

Full classification matrix and parent-walking algorithm: `skills/jira-push/references/bead-type-mapping.md`.

### Opt-in / opt-out labels

| Label | Effect |
|-------|--------|
| `jira-push` | Force-include this bead in push (overrides Sub-task skip). Configurable via `sync.pushLabel` |
| `jira-skip` | Force-exclude this bead from push entirely. Configurable via `sync.skipLabel` |

### Status drift (Phase C)

After pull and push complete, `/sync` reconciles any bead that is **closed locally** but whose linked JIRA ticket is still open: it offers to transition JIRA to `jira.transitionOnClose` via the existing `jira-sync-back` Operation B preview. This catches retroactive `bd close` calls so JIRA does not silently lag behind.

## Local bead workflow

```bash
bd create "Investigate failing CI" --type task
bd dep add bd-XX bd-YY        # mark parent (optional)
/umo-jira-tracker:sync         # push detects the orphan and proposes a JIRA Task

bd create "Phase-2 platform work" --type epic
bd create "Backend wiring" --type task --parent bd-100
/umo-jira-tracker:sync         # both beads pushed in topological order
```

Use `bd label add <id> jira-skip` to keep a bead out of JIRA permanently, or `bd label add <id> jira-push` to force-sync a sub-task.

## Naming standard

> Based on the internal Confluence standard **"STD-JIRA and GitLab Branch/MR Naming"**.

### Branch format

```
{type}/{JIRA-KEY}-{short-description}
```

| Component | Required | Notes |
|-----------|----------|-------|
| `type` | Yes | `feat`, `fix`, `hotfix`, `chore`, `refactor`, `test`, `docs`, `ci`, `perf`, `build` |
| `JIRA-KEY` | Yes | e.g. `CWN-1234`, `PAY-567` |
| `short-description` | Yes | 2–5 words, kebab-case |

Multiple JIRA keys: `feat/CWN-1234-CWN-1235-login-refactor`

**Examples:** `feat/CWN-1234-add-kafka-retry`, `fix/PAY-567-null-pointer-on-transfer`, `hotfix/AUTH-890-critical-token-leak`

### MR title format

Preferred: `{JIRA-KEY}: {Description}` e.g. `CWN-1234: Add Kafka retry`

The JIRA key at the start triggers GitLab's automatic JIRA ticket linking. Conventional commit types (`feat:`, `fix:`) are for **commit messages only** — not required in MR titles.

### Commit format

`type(scope): description` — follows [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/). Include the JIRA key in the commit footer (`Closes: CWN-1234`) or branch name.

### Forbidden patterns

| Pattern | Why forbidden |
|---------|---------------|
| Branch without JIRA key | Cannot trace work back to a ticket |
| Names like `tmp`, `wip`, `test`, `my-branch` | No context |
| Multiple unrelated tasks in one branch | Violates atomic MR principle |
| Direct commits to `main`, `dev`, `release` | Bypasses review |
| MR without description or JIRA link | Breaks traceability |

## JIRA issue creation rules

Every new issue **must be linked** to a parent. Sub-tasks can never be created without a parent. For any orphan creation, the agent will warn you, ask for a justification, and require the phrase `create unlinked` to proceed.
