# umo-mr

The org-default plugin for creating GitLab merge requests. It is always active: use `/mr` (or just ask to create/open/push an MR) and the agent will parse your intent, autodetect the repo's default branch, choose the source branch via the protected-branch + open-MR heuristic (or an explicit override), organize uncommitted work into logical conventional commits, push and create the MR immediately (`glab` preferred, GitLab MCP as fallback), and optionally sync a linked JIRA ticket.

Conventions are ported from the UMO `saas` repo's `/mr` workflow — trunk-based development, squash merge, and Conventional-Commit MR titles with the JIRA key in parentheses at the end — and shipped as **defaults**, not hardcoded requirements. Every UMO repo can override them via an optional `.umo/mr.json`.

## Key behaviors

- **Always-on:** an always-on rule (`rules/umo-mr.mdc`) reminds the agent to use `/mr` whenever the developer asks to create, open, or push a merge request — or whenever the agent itself decides finished work is ready to ship — in any repo, with or without `.umo/mr.json`.
- **Autodetects the default branch:** never hardcodes `main`. Resolves the target branch from explicit developer input, then `.umo/mr.json`, then `git remote show origin` / `git symbolic-ref refs/remotes/origin/HEAD`.
- **Auto branch heuristic:** on target/protected branches always create a short-lived feature branch; otherwise reuse the current feature branch (no open MR = developer-created; open MR = update that MR). Explicit reuse/rename/new overrides win when clear.
- **Immediate execute:** when the developer asks for commits or an MR, commit/push/create without a preview approval gate. JIRA mutations still require explicit approval.
- **`glab`-first MR creation:** creates the MR via the `glab` CLI by default, falling back to GitLab MCP only when `glab` is missing, unauthenticated, or fails (configurable via `gitlab.mrTool`).

## Slash command

| Command | Purpose |
|---------|---------|
| `/mr` | Parse intent, manage branches, commit, push, create the MR immediately, optionally sync JIRA |

## Skill

| Skill | Purpose |
|-------|---------|
| `gitlab-mr` | glab CLI / GitLab MCP reference for MR creation, invoked only from `/mr` Phase 6 |

## Prerequisites

| Tool | Purpose | How to get |
|------|---------|------------|
| `glab` ≥ v1.103.0 (preferred/default) | Primary path for MR creation and existing-MR checks | `brew install glab` (or `brew upgrade glab`) — see [glab docs](https://gitlab.com/gitlab-org/cli) |
| GitLab MCP (optional, fallback) | Used only when `glab` is missing, unauthenticated, or fails | Configure a GitLab MCP server (e.g. `@zereight/mcp-gitlab`) in your host's MCP settings |
| Atlassian MCP (optional) | JIRA context fetch + optional comment/transition | Configure in Cursor/Claude Settings → MCP |

### glab authentication

```bash
glab auth login
# or set GITLAB_TOKEN / GITLAB_ACCESS_TOKEN with api scope in your shell (~/.zshenv on macOS)
export GITLAB_TOKEN="<your-token>"
```

No credentials are stored in this plugin — authentication is handled by `glab` or by the MCP host.

## Config: `.umo/mr.json` (optional)

Not required. If absent, `/mr` uses the UMO defaults documented in `commands/mr.md`. Create this file only when a repo needs to diverge from those defaults (different target branch, no squash, JIRA disabled, a fixed GitLab project ID, etc). Safe to commit — no secrets.

```json
{
  "gitlab": {
    "remote": "origin",
    "projectId": null,
    "targetBranch": null,
    "mrTool": "glab",
    "squash": true
  },
  "jira": {
    "enabled": true,
    "baseUrl": "https://umotech.atlassian.net",
    "defaultProjectKey": null
  },
  "commit": {
    "allowedTypes": ["feat", "fix", "refactor", "chore", "test", "docs", "ci", "perf", "build", "revert"],
    "maxSubjectLength": 120
  },
  "mrTemplatePath": ".gitlab/merge_request_templates/Default.md",
  "user": {
    "gitlabUsername": null
  }
}
```

| Field | Meaning | Default |
|-------|---------|---------|
| `gitlab.remote` | Git remote name to resolve the GitLab project from | `origin` |
| `gitlab.projectId` | Numeric GitLab project ID, if you want to skip auto-resolution | `null` (auto-resolve via `glab` or MCP `search`) |
| `gitlab.targetBranch` | Default MR target / trunk branch | `null` (autodetected from the repo's actual default branch — never hardcoded to `main`) |
| `gitlab.mrTool` | Preferred tool for MR creation — `"glab"` (default) or `"mcp"` to flip the fallback order | `glab` |
| `gitlab.squash` | Whether to pass `--squash-before-merge` / request squash merge | `true` |
| `jira.enabled` | Whether to fetch JIRA context and offer the optional Phase 7 update | `true` |
| `jira.baseUrl` | Atlassian Cloud base URL used in MR description links | `https://umotech.atlassian.net` |
| `jira.defaultProjectKey` | Default JIRA project key to assume when the developer omits one | `null` |
| `commit.allowedTypes` | Conventional Commit types accepted for commit/MR-title planning | UMO default list (see above) |
| `commit.maxSubjectLength` | Max MR title length (commitlint-aligned) | `120` |
| `mrTemplatePath` | Path to the repo's own MR description template, if any | `.gitlab/merge_request_templates/Default.md` |
| `user.gitlabUsername` | Used for `--assignee` when creating MRs via `glab` | `null` |

## Coexistence with `umo-jira-tracker`

`umo-jira-tracker` ships its own `/umo-jira-tracker:mr`, which is coupled to a local Beads database and JIRA sync-back. Use that command for beads-tracked work when `umo-jira-tracker` is installed and configured (`.umo/jira-tracker.json` present). Use plain `/mr` from this plugin for ad hoc, non-ticketed, or non-beads-tracked MRs, or in any repo where `umo-jira-tracker` isn't installed. The two commands share the same underlying GitLab conventions and do not conflict.

## Design note

This plugin ships no runtime code — it is entirely agent instructions (a Markdown command plus a Markdown skill and an optional rule). The agent executes `git`, `glab`, and MCP calls as directed by these documents.
