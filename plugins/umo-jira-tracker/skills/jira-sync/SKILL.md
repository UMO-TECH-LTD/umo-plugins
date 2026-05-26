---
name: jira-sync
description: Pull direction of the bidirectional sync. Pulls JIRA issues (assignee=currentUser, unresolved by default, plus a recently-Done window) into the local Beads database using the Story-as-epic mapping. Idempotent upsert — preserves human Notes blocks, reconciles parents in a second pass, closes Done issues. Used by `/umo-jira-tracker:sync` Phase A. Pair with `jira-push` for the reverse direction.
paths:
  - ".umo/jira-tracker.json"
  - "**/.beads/**"
---

# JIRA Sync (Pull)

Pulls JIRA issues into the local Beads database using an idempotent upsert. Safe to run repeatedly — existing beads are updated, not duplicated.

This skill is **Phase A** of `/umo-jira-tracker:sync`. Phase B (`jira-push`) runs immediately after when `sync.direction` allows it. Phase C (drift close) reconciles status differences. See `jira-push/SKILL.md` for the combined flow diagram.

Load `references/mapping.md` for the full issue-type → bead-type matrix and description structure.
Load `references/jql.md` for JQL customization and Atlassian MCP call details.

## Prerequisites

- `.umo/jira-tracker.json` must exist. If absent, instruct the developer to run `/umo-jira-tracker:setup` first.
- Atlassian MCP must be available (`getAccessibleAtlassianResources` reachable).
- `bd` must be on PATH.

## Algorithm

### Phase 0 — Prepare

1. Read `.umo/jira-tracker.json`.
2. Resolve `cloudId`:

```
CallMcpTool -> Atlassian / getAccessibleAtlassianResources
```

Pick the resource whose `url` matches `jira.cloudUrl` (or the first if only one exists). Store `cloudId` for subsequent calls.

3. Determine effective JQL:
   - `--jql` flag → use verbatim. Skip the recently-Done extension (the developer is in control).
   - else → start from `jira.syncJql` and extend it with the recently-Done window (see below).
   - fallback (no `jira.syncJql`) → `assignee = currentUser() AND statusCategory != Done`, then extend with the recently-Done window.

**Recently-Done window.** The point of including done issues is to detect status drift (JIRA closed something while we were offline) without bloating the result set. Build the effective JQL as:

```
({configured-jql}) OR (assignee = currentUser() AND statusCategory = Done AND updated >= {sync.recentlyDoneWindow})
```

`sync.recentlyDoneWindow` defaults to `-14d`. Omit the extension if the developer passed `--jql` (assume they meant exactly what they typed) or if the configured JQL already references `statusCategory = Done`.

4. **Pass 0 — Inventory existing beads.** Before fetching anything from JIRA, take a snapshot of what is already linked locally. This snapshot is reused by Phase B (`jira-push`) to detect orphan beads without re-scanning the database:

```bash
bd list --label-pattern "jira:*" --json --all
```

Build two maps from the result:

```
beadsByJiraKey  = { "CWN-1234": { beadId, status, labels } }
beadsByBeadId   = { "bd-42":    { jiraKey, status, labels } }
```

Cache both for the duration of the `/sync` session.

### Phase 1 — Fetch issues

```
CallMcpTool -> Atlassian / searchJiraIssuesUsingJql
  cloudId: "{cloudId}"
  jql: "{effectiveJql}"
  fields: ["summary","status","priority","issuetype","parent","assignee","sprint","description","resolution","updated","customfield_10014"]
  maxResults: 100
```

`resolution` and `updated` are needed for the recently-Done window so Pass 3 can decide whether a bead should be closed (and so the dry-run can label rows correctly).

Paginate if `total > 100`. Collect the full list before proceeding.

Also fetch parent issues that appear in `fields.parent.key` but are not in the result set (they may be Epics filtered out by the JQL). For each missing parent key:

```
CallMcpTool -> Atlassian / getJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{PARENT-KEY}"
```

### Phase 2 — Dry-run table

When `--dry-run` is set (or when this is the first sync for this repo), compute and print what would happen before touching any beads:

```
Dry run — no beads will be modified:

| JIRA Key   | Type    | Summary (truncated)       | Action  |
|------------|---------|---------------------------|---------|
| CWN-100    | Epic    | Q3 Platform work          | create  |
| CWN-1234   | Story   | Add Kafka retry           | create  |
| CWN-1235   | Task    | Write unit tests          | create  |
| CWN-999    | Story   | Old feature               | close   |

3 to create, 0 to update, 1 to close, 0 to skip.

Proceed with sync? (yes/no)
```

If `--dry-run` is passed, stop here. Otherwise ask for approval if this is the first sync; subsequent syncs may proceed directly if the developer says "yes, always" (store preference in bead notes as a flag — do not persist to config file).

### Phase 3 — Pass 1: Upsert (no parents)

For each issue in the fetched list (process Epics first, then Stories, then Tasks/Bugs, then Sub-tasks):

1. Look up existing bead:

```bash
bd list --label "jira:{KEY}" --json
```

2. Build bead fields using `references/mapping.md`:
   - `title`: `[{KEY}] {summary}`
   - `type`: `epic` (for Epic/Story) or `task` (for Task/Bug/Sub-task)
   - `labels`: `jira:{KEY}`, `jira-type:{type}`, `jira-status:{status-kebab}`, `jira-parent:{PARENT-KEY}` (if any), `jira-sprint:{id}` (if any)
   - `description`: JIRA-sourced zone + preserved Notes zone (see mapping.md)

3. If bead does not exist:

```bash
bd create \
  --title "[{KEY}] {summary}" \
  --type {epic|task} \
  --description "{description}" \
  --label "jira:{KEY}" \
  --label "jira-type:{type}" \
  --label "jira-status:{status}" \
  --json
```

4. If bead exists, check whether the JIRA-sourced zone has changed:
   - Extract everything above `## Notes` from the existing bead description.
   - Compare with the freshly-built JIRA zone.
   - If unchanged: skip (action = `skip`).
   - If changed: update only the JIRA zone, preserving the `## Notes` block:

```bash
bd update {bead-id} \
  --description "{jira-zone}\n\n{existing-notes-zone}" \
  --label "jira-status:{new-status}" \
  --json
```

5. If JIRA `statusCategory` is `Done` and bead is open:

```bash
bd close {bead-id} --reason "JIRA: status={statusName}" --json
```

Track all actions for the final report.

### Phase 4 — Pass 2: Parent reconciliation

For each issue that has a JIRA parent key:

```bash
# Find parent bead
bd list --label "jira:{PARENT-KEY}" --json
```

If found, set parent:

```bash
bd update {child-bead-id} --parent {parent-bead-id} --json
```

If not found: print `WARN: parent bead for {PARENT-KEY} not found — skipping parent link for {CHILD-KEY}` and continue.

### Phase 5 — Report

Print a final pull-summary table:

```
Pull complete (Phase A):

| Action  | Count |
|---------|-------|
| created |     5 |
| updated |     3 |
| closed  |     1 |
| skipped |    12 |
```

If `sync.direction` is `pull`, finalize:

```
Bead database is now up to date.
Run `bd ready --json` to see what's next.
```

Otherwise, hand control to **`jira-push`** (Phase B) using the inventory built in Pass 0.

## Error handling

- Atlassian MCP unavailable: abort with clear message directing to `/umo-jira-tracker:setup`.
- `bd` returns non-zero: print the full error and the failing command; stop that issue's upsert and continue with the next.
- Rate limits: if the Atlassian MCP returns a 429, wait 5 seconds and retry once.
