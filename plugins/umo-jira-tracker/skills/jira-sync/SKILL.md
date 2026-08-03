---
name: jira-sync
description: Pull direction of the bidirectional sync. Pulls JIRA issues (assignee=currentUser, unresolved by default, plus a recently-closed window) into the local Beads database — Flows and Slices become epic beads, Tasks, Bugs and Requests become task beads. Idempotent upsert — preserves human Notes blocks, reconciles parents in a second pass, closes issues that reached a terminal state. Used by `/umo-jira-tracker:sync` Phase A. Pair with `jira-push` for the reverse direction.
paths:
  - ".umo/jira-tracker.json"
  - "**/.beads/**"
---

# JIRA Sync (Pull)

Pulls JIRA issues into the local Beads database using an idempotent upsert. Safe to run repeatedly — existing beads are updated, not duplicated.

This skill is **Phase A** of `/umo-jira-tracker:sync`. Phase B (`jira-push`) runs immediately after when `sync.direction` allows it. Phase C (drift close) reconciles status differences. See `jira-push/SKILL.md` for the combined flow diagram.

Load `../../references/work-tracking-model.md` for the org's encoding — the five issue types and the parent chain.
Load `references/mapping.md` for the full issue-type → bead-type matrix and description structure.
Load `references/jql.md` for JQL customization and Atlassian MCP call details.

**Pull handles all five types; push handles two.** That asymmetry is deliberate — see `../jira-push/references/bead-type-mapping.md`.

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

**Recently-closed window.** The point of including terminal issues is to detect status drift (JIRA closed or retired something while we were offline) without bloating the result set. `statusCategory = Done` covers all three terminals — `Done`, `Closed` on a Request, and `Retired` — which the upsert then distinguishes. Build the effective JQL as:

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
beadsByJiraKey  = { "PAY-1234": { beadId, status, labels } }
beadsByBeadId   = { "bd-42":    { jiraKey, status, labels } }
```

Cache both for the duration of the `/sync` session.

### Phase 1 — Fetch issues

```
CallMcpTool -> Atlassian / searchJiraIssuesUsingJql
  cloudId: "{cloudId}"
  jql: "{effectiveJql}"
  fields: ["summary","status","priority","issuetype","parent","assignee","description","resolution","duedate","updated"]
  maxResults: 100
```

`resolution` and `updated` drive the recently-closed window so Pass 3 can decide whether a bead should be closed (and so the dry-run can label rows correctly). `resolution` also carries the mandatory reason on a `Retired` issue. `duedate` is the `needed-by` on a Request; ignore it everywhere else.

Do **not** request `sprint` or `customfield_10014` (Epic Link) — neither is part of the org's encoding.

Paginate if `total > 100`. Collect the full list before proceeding.

Also fetch parent issues that appear in `fields.parent.key` but are not in the result set — typically the Slice or Flow a scoped JQL filtered out. Walk the chain **upward until you reach a Flow**, so the `jira-flow:` label can be derived. For each missing parent key:

```
CallMcpTool -> Atlassian / getJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{PARENT-KEY}"
```

### Phase 2 — Dry-run table

When `--dry-run` is set (or when this is the first sync for this repo), compute and print what would happen before touching any beads:

```
Dry run — no beads will be modified:

| JIRA Key   | Type    | Summary (truncated)              | Action  |
|------------|---------|----------------------------------|---------|
| PAY-900    | Flow    | [IC] Client onboarding           | create  |
| PAY-1200   | Slice   | [IC-S2] Client can see status    | create  |
| PAY-1234   | Task    | [IC-S2] Add Kafka retry          | create  |
| CMP-77     | Request | [IC-S2] Customer status returned | create  |
| PAY-999    | Task    | [IC-S1] Old approach             | close   |

4 to create, 0 to update, 1 to close, 0 to skip.

Proceed with sync? (yes/no)
```

If `--dry-run` is passed, stop here. Otherwise ask for approval if this is the first sync; subsequent syncs may proceed directly if the developer says "yes, always" (store preference in bead notes as a flag — do not persist to config file).

### Phase 3 — Pass 1: Upsert (no parents)

For each issue in the fetched list, processing top-down — Flows first, then Slices, then Tasks, Bugs and Requests:

1. Look up existing bead:

```bash
bd list --label "jira:{KEY}" --json
```

2. Build bead fields using `references/mapping.md`:
   - `title`: `[{KEY}] {summary}` — keep the slice coordinate the summary already carries
   - `type`: `epic` (for Flow/Slice) or `task` (for Task/Bug/Request)
   - `labels`: `jira:{KEY}`, `jira-type:{type}`, `jira-status:{status-kebab}`, `jira-parent:{PARENT-KEY}` (if any), `jira-flow:{FLOW-KEY}` (derived by walking the parent chain; omit if the chain cannot be resolved)
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

5. If JIRA `statusCategory` is `Done` and the bead is open, close it — but preserve *which* terminal it reached, because they do not mean the same thing (see mapping.md → Status reconciliation):

```bash
# Task / Slice / Flow reached Done
bd close {bead-id} --reason "JIRA: status=Done" --json

# a Request reached Closed — consumer proof
bd close {bead-id} --reason "JIRA: Request closed — consumer proof" --json

# anything Retired — withdrawn without being completed, excluded from every count
bd close {bead-id} --reason "JIRA: Retired — {resolution}" --json
```

On a `Retired` issue with an empty `fields.resolution`, close anyway and warn: Resolution is mandatory there, and its absence is a data defect worth surfacing.

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

**A parent in another project is normal.** Requests live in the provider's project but parent to the consumer's Slice, and provider Tasks may be parented cross-project for billing. Never treat a differing project key as an error to correct.

**A Task, Bug or Request with no parent at all is an orphan** — it belongs to no flow and appears in no cost ledger, and the org runs a standing detector for exactly this. Count orphans and name them in the Phase 5 report rather than passing over them silently.

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

Orphans (no parent — not in any flow's rollup):
  PAY-1301  [IC-S2] Add metrics endpoint
```

Omit the orphan block when there are none.

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
