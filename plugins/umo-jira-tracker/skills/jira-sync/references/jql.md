# JQL Reference for jira-sync

## Setup presets

`/umo-jira-tracker:setup` offers two presets — stored as `jira.syncJql` in `.umo/jira-tracker.json`:

| Preset | JQL |
|--------|-----|
| All open assigned tickets (default) | `assignee = currentUser() AND statusCategory != Done` |
| Active sprint only | `assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done` |

The all-open preset returns every unresolved ticket assigned to you — including backlog and parent epics/stories. The active-sprint preset narrows to issues in the current open sprint(s), which is usually a better fit when you only work from the sprint board.

## Config override

The user can set `jira.syncJql` in `.umo/jira-tracker.json` to any JQL. Re-run `/umo-jira-tracker:setup` to switch presets, or edit the file directly. The `/sync` command's `--jql` flag overrides for a single run without touching the config.

## Recently-Done extension (automatic)

`jira-sync` Phase 0 augments the configured JQL with a recently-Done window so the pull can detect tickets that were closed in JIRA while the developer was offline (status drift). Build the effective query as:

```
({configured-jql}) OR (assignee = currentUser() AND statusCategory = Done AND updated >= {sync.recentlyDoneWindow})
```

`sync.recentlyDoneWindow` defaults to `-14d` and lives under the new `sync` block in `.umo/jira-tracker.json`. Skip the extension when:

- The developer passed `--jql` (treat their query as exact).
- The configured JQL already contains `statusCategory = Done` (would be redundant).

Example expanded query when the user has the default preset:

```
(assignee = currentUser() AND statusCategory != Done)
OR
(assignee = currentUser() AND statusCategory = Done AND updated >= -14d)
```

The recently-Done branch is what powers the existing Pass 3 ("close beads whose JIRA is Done") even when the developer's day-to-day JQL excludes done issues.

## Common customizations

### Active sprint only

Same as the setup preset:

```
assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done
```

### Single project, active sprint

```
project = CWN AND assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done
```

### Include recently done (last 7 days) — useful for close-of-sprint sync

```
assignee = currentUser() AND (statusCategory != Done OR status changed to Done after -7d)
```

### All issues in an epic (useful for feature work spanning multiple sprints)

```
"Epic Link" = CWN-100 AND assignee = currentUser()
```

### Sub-tasks included explicitly (some JIRA configs filter them by default)

```
assignee = currentUser() AND statusCategory != Done AND issueType in standardIssueTypes() OR issueType in subTaskIssueTypes()
```

## Atlassian MCP call

```
CallMcpTool -> Atlassian / searchJiraIssuesUsingJql
  cloudId: "{cloudId}"
  jql: "{effective JQL}"
  fields: ["summary","status","priority","issuetype","parent","assignee","sprint","description","comment","resolution","updated","customfield_10014"]
  maxResults: 100
```

`resolution` and `updated` are required to drive the recently-Done branch and surface drift in the dry-run table.

`customfield_10014` is the Epic Link field in classic JIRA projects. In next-gen projects the parent relationship is in `fields.parent`.

If the result set reaches `maxResults`, paginate with `startAt` until `total` is exhausted.

## Handling missing fields

- `fields.sprint` may be null (backlog items, kanban boards) — omit `jira-sprint:` label.
- `fields.parent` may be null for top-level Tasks/Stories — leave parent bead unset.
- `fields.description` may be null — leave the `Acceptance Criteria` section empty with a `_(none)_` placeholder.
