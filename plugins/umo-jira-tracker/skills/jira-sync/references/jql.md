# JQL Reference for jira-sync

## Default sync query

```
assignee = currentUser() AND statusCategory != Done
```

This returns all tickets assigned to the current user that are not yet done — regardless of sprint or project. It is the widest useful scope for a developer's personal Beads database.

## Config override

The user can set `jira.syncJql` in `.umo/jira-tracker.json` to narrow or widen scope. The `/sync` command's `--jql` flag overrides for a single run without touching the config.

## Common customizations

### Active sprint only

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
  fields: ["summary","status","priority","issuetype","parent","assignee","sprint","description","comment","customfield_10014"]
  maxResults: 100
```

`customfield_10014` is the Epic Link field in classic JIRA projects. In next-gen projects the parent relationship is in `fields.parent`.

If the result set reaches `maxResults`, paginate with `startAt` until `total` is exhausted.

## Handling missing fields

- `fields.sprint` may be null (backlog items, kanban boards) — omit `jira-sprint:` label.
- `fields.parent` may be null for top-level Tasks/Stories — leave parent bead unset.
- `fields.description` may be null — leave the `Acceptance Criteria` section empty with a `_(none)_` placeholder.
