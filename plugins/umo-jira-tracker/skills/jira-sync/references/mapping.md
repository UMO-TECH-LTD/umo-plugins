# JIRA → Beads Mapping Reference

This file is the authoritative source for how JIRA issue types translate into Beads entities. Load it whenever performing a sync, upsert, or parent-reconciliation step.

## Issue type → Bead type matrix

| JIRA issue type | Bead type | Parent bead |
|-----------------|-----------|-------------|
| Epic | `epic` | none |
| Story | `epic` | Epic-bead of linked JIRA Epic (if `fields.parent` / Epic Link set), else none |
| Task | `task` | Epic-bead of linked JIRA Epic (if set), else none |
| Bug | `task` | Epic-bead of linked JIRA Epic (if set), else none |
| Sub-task | `task` | Bead of the JIRA parent issue (`fields.parent.key`) |

### Rationale for Story-as-epic

Beads support a two-level tree (epic → task). JIRA has three visible levels (Epic → Story → Sub-task) plus Task/Bug anywhere in the tree. Mapping Story as `epic` lets its Sub-tasks and child Tasks sit cleanly as child beads with `bd dep add` or `--parent`, without flattening the full JIRA hierarchy into a single depth.

## Identity and labelling

Every synced bead carries these identifiers so future sync runs can find it without scanning all beads.

### Bead title

```
[{JIRA-KEY}] {JIRA summary}
```

Example: `[CWN-1234] Add Kafka retry logic`

### Bead labels

| Label | Value | Example |
|-------|-------|---------|
| `jira:{KEY}` | JIRA issue key | `jira:CWN-1234` |
| `jira-type:{type}` | Lowercase JIRA issue type | `jira-type:story` |
| `jira-status:{status}` | Kebab-cased JIRA status name | `jira-status:in-progress` |
| `jira-parent:{KEY}` | Parent JIRA key (if any) | `jira-parent:CWN-9999` |
| `jira-sprint:{id}` | Sprint ID from `fields.sprint.id` | `jira-sprint:42` |

### Bead description structure

The bead description is split into two zones:

1. **JIRA-sourced zone** (auto-overwritten on each sync):

```markdown
## JIRA

- **Key**: CWN-1234
- **URL**: https://yourorg.atlassian.net/browse/CWN-1234
- **Type**: Story
- **Status**: In Progress
- **Priority**: Medium
- **Sprint**: Sprint 12

### Acceptance Criteria

<content from JIRA description / AC field>
```

2. **Notes zone** (human/agent-editable, never overwritten by sync):

```markdown
## Notes

<free-form implementation notes, decisions, AC refinements>
```

**Sync must preserve the `## Notes` section and everything below it.** When upserting, replace only the content above `## Notes`.

## Lookup strategy

1. Primary: `bd list --label "jira:{KEY}" --json` — finds by exact label.
2. If multiple results (shouldn't happen but guard): pick the one with `jira:{KEY}` and warn about duplicates.
3. If zero results: this is a new issue — `bd create`.

## Status reconciliation

| JIRA status category | Action |
|----------------------|--------|
| `Done` | Close bead: `bd close <id> --reason "JIRA: status=Done"` (only if bead is not already closed) |
| `In Progress` / `To Do` | Leave bead open; update `jira-status:` label |

**One-way rule**: The sync never re-opens a bead that was closed by the developer. If JIRA reverts to `In Progress` after a local close, the bead stays closed and a warning is printed.

## Two-pass parent reconciliation

Parent beads must exist before child beads can reference them. Sync runs in two passes:

1. **Pass 1**: Upsert all issues without setting parents.
2. **Pass 2**: For each issue with a JIRA parent key, look up the parent bead via `bd list --label "jira:{PARENT-KEY}" --json` and set `bd update <child-id> --parent <parent-bead-id>`.

If a parent bead is not found in pass 2, print a warning and continue (the developer may have filtered it out of the JQL scope).
