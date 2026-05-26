---
name: jira-push
description: Reverse-direction sync — push locally-created beads (no `jira:` label) up to JIRA as Epics / Stories / Tasks / Bugs (and optionally Sub-tasks). Always previews, walks parents first, delegates the actual `createJiraIssue` call to `jira-sync-back` Operation D so the existing approval, orphan-warning, and sprint create-then-edit logic is reused. Invoked by `/umo-jira-tracker:sync` Phase B.
paths:
  - ".umo/jira-tracker.json"
  - "**/.beads/**"
---

# JIRA Push

This skill turns Beads into the source of truth. Any bead that was created locally with `bd create` (or imported from somewhere other than JIRA) and therefore has **no `jira:` label** is a candidate for promotion into JIRA.

Load `references/bead-type-mapping.md` for the bead → JIRA issue-type matrix.
Load `../jira-sync-back/references/creation-policy.md` for the orphan / Sub-task rules — every push goes through the same chokepoint.

## Prerequisites

- `.umo/jira-tracker.json` exists with `sync.direction` either `both` or `push` (default `both`).
- Atlassian MCP available.
- `bd` on PATH.
- `jira-sync` Phase A has just completed in the same run, OR the developer ran `/umo-jira-tracker:sync --push-only` deliberately. Push should never run without an up-to-date view of what's already in JIRA, otherwise we risk pushing duplicates.

## Trigger

Invoked by `/umo-jira-tracker:sync` (when `sync.direction` allows push) and by an explicit `/umo-jira-tracker:sync --push-only`.

## Configuration keys consumed

From `.umo/jira-tracker.json`:

```json
"sync": {
  "direction": "both",
  "pushSubtasks": false,
  "pushLabel": "jira-push",
  "skipLabel": "jira-skip"
}
```

| Key | Meaning |
|-----|---------|
| `sync.direction` | `both` (default) / `pull` / `push` — controls which phases of `/sync` run |
| `sync.pushSubtasks` | When `false` (default), beads that map to JIRA Sub-tasks are skipped unless they carry the `pushLabel`. When `true`, sub-tasks are pushed unconditionally |
| `sync.pushLabel` | Bead label that forces inclusion even if normally skipped (default `jira-push`) |
| `sync.skipLabel` | Bead label that forces exclusion regardless of other rules (default `jira-skip`) |

## Algorithm

### Phase 0 — Inventory

Re-use the inventory produced by `jira-sync` Pass 0 (the set of beads already carrying `jira:` labels) if available in this session. Otherwise rebuild it:

```bash
bd list --label-pattern "jira:*" --json --all
```

Store as a map `{ beadId: jiraKey }` and the inverse `{ jiraKey: beadId }`. This is needed both to skip already-synced beads and to resolve parent-bead → JIRA-key lookups during the push.

### Phase 1 — Detect push candidates

Goal: every open bead with no `jira:` label that is not explicitly skipped.

```bash
# Beads that lack any jira: label. Run twice (no-labels covers the empty case;
# the second call covers beads that have other labels but none with the jira: prefix).
bd list --no-labels --json
bd list --json | jq '[.[] | select((.labels // []) | any(startswith("jira:")) | not)]'
```

Filter the union to:

- `status != closed` (closed beads are handled by Phase C drift, not push).
- `type in ("epic", "task")` — Beads ships with these types only for our mapping. Other custom types (`chore`, `bug`, `feature`, `decision`) map to JIRA Bug / Task / Story per the mapping table.
- No `{sync.skipLabel}` label.
- Either no `{sync.pushLabel}` label and not classified as Sub-task, **or** carries `{sync.pushLabel}` (Sub-task opt-in).

### Phase 2 — Classify each candidate

For each candidate bead, walk its parent chain via `bd show {id} --json` (read `parent_id`, `dependencies`, and any existing `jira:` / `jira-type:` labels on the parent) and resolve the proposed JIRA issue type from `references/bead-type-mapping.md`.

Inputs to the mapping:

| Signal | Source |
|--------|--------|
| `bead.type` | `bd show ... --json` field `type` |
| `parent bead exists` | `bd show ... --json` field `parent_id` (preferred) or first `parent-of` dependency |
| `parent.jira-type` | Parent bead label `jira-type:*` (when parent is already in JIRA) |
| `parent.jira-key` | Parent bead label `jira:*` |
| `parent.bead.type` | Parent's `type` field (when parent is not yet in JIRA) |

Output for each candidate:

```
{
  beadId, beadTitle, beadType,
  parentBeadId, parentJiraKey,
  proposedJiraType,    // Epic | Story | Task | Bug | Sub-task
  action,              // create | create-parent-first | skip-subtask | skip-orphan
  reason               // human-readable
}
```

### Phase 3 — Topological sort

A bead cannot push until its parent exists in JIRA. Build a DAG over the candidates and sort topologically (Kahn). If a parent bead has no `jira:` label and is itself a candidate, mark it as a dependency and ensure it is processed first.

If a parent bead is **not** a candidate (e.g. skipped, closed, or marked `jira-skip`) and has no `jira:` label, the child must be flagged `skip-orphan` — there is no key to point to. Surface this in the dry-run so the developer can decide.

### Phase 4 — Dry-run table

Always show the table, even when `--dry-run` is not passed. This mirrors the pull-side UX.

```
Push candidates:

| Bead | Type | Title | Parent | Proposed JIRA | Action |
|------|------|-------|--------|---------------|--------|
| bd-42 | epic | Add Kafka retry | none | Epic | create |
| bd-43 | task | Implement producer wrapper | bd-42 | Task | create (after bd-42) |
| bd-44 | task | Write unit tests | bd-43 | Sub-task | skip (sub-task — add `jira-push` label to push) |
| bd-50 | task | Standalone investigation | none | Task | create (orphan — extra approval) |

Summary: 2 create, 1 orphan-pending, 1 sub-task-skipped.

Proceed with push? (yes/no/select)
```

`select` lets the developer cherry-pick rows by ID before continuing.

If `--dry-run` was passed, stop here and exit.

### Phase 5 — Per-bead push

For each row marked `create` (in topological order), delegate to `jira-sync-back` Operation D. The skill is already responsible for:

1. Loading `creation-policy.md` and enforcing the linkage matrix.
2. Showing the per-issue preview (summary, type, parent, priority, assignee from `user.jiraAccountId`, description excerpt).
3. Calling `createJiraIssue`.
4. Sprint create-then-edit pattern via `customfield_10020`.
5. Round-tripping the new key into Beads (labels + JIRA-sourced description zone).

This skill is responsible for **building the description and selecting the parent key** before handing off:

#### Building the description

The bead has no `## JIRA` zone yet — its description was written by the developer. Wrap it for JIRA without losing the local content:

```markdown
{bead description, verbatim}

> Pushed from Beads (bead-id: {beadId}) on {ISO date} by {user.gitlabUsername}.
```

After Op D's round-trip step, the bead's local description is regenerated by `jira-sync` mapping rules:

```markdown
## JIRA

- **Key**: {NEW-KEY}
- **URL**: {cloudUrl}/browse/{NEW-KEY}
- **Type**: {jiraType}
- **Status**: {newly-created status}
- **Priority**: {priority}

### Acceptance Criteria

{original bead description, verbatim — preserved as the AC zone}

## Notes

{any pre-existing notes from the bead, preserved}
```

#### Selecting the parent key

| Case | Parent key passed to Op D |
|------|---------------------------|
| Bead has parent bead with `jira:{KEY}` label | `{KEY}` |
| Bead has parent bead that was just pushed in this run | the freshly minted key from Op D's return value |
| Bead has parent bead but parent is skipped/orphan | none — trigger orphan warning (Op D handles this) |
| Bead has no parent and is an Epic | none — Epic creation prompt (Op D requires `create epic`) |
| Bead has no parent and is Story / Task / Bug | none — orphan warning (Op D requires `create unlinked` + justification) |

#### After Op D returns

Op D already labels the bead with `jira:{NEW-KEY}`, `jira-type:{type}`, `jira-status:{status}`. Add one extra label so future pushes can audit provenance:

```bash
bd label add {beadId} "jira-origin:bead"
```

This distinguishes beads that originated locally from beads that were pulled from JIRA — useful for the drift-close phase and for analytics.

### Phase 6 — Report

```
Push complete:

| Action | Count |
|--------|-------|
| created | 3 |
| orphan-skipped | 1 |
| subtask-skipped | 1 |
| failed  | 0 |

Failures (if any):
  bd-99: Atlassian MCP returned 400 — see preview above.

Next: locally-closed beads will be reconciled with JIRA next.
```

## Error handling

- **Op D refuses creation** (developer cancels at preview, or orphan/`create epic` not approved): record as `skipped` and continue with the next candidate. Never abort the whole push.
- **`createJiraIssue` returns non-2xx**: surface the error, mark the candidate as `failed`, leave the bead untouched. Subsequent runs will retry.
- **Parent key disappears between Phase 3 and Phase 5** (parent push failed): treat child as `skipped` with reason "parent push failed".
- **Rate limits** (429): wait 5s, retry once. If still 429, mark `failed` and continue.

## Idempotency

This skill is safe to re-run because:

1. Candidates are derived from "no `jira:` label". Once a bead is pushed, it gains a `jira:` label and is excluded from future runs.
2. The dry-run table always shows what would change before any write.
3. Op D's preview is per-bead; a developer that says "no" simply leaves the bead unsynced for next run.

## Combined `/sync` flow (reference)

```
Phase A — jira-sync (pull)
  ├─ Pass 0: inventory existing jira: labels
  ├─ Pass 1: upsert open issues + recently-done window
  ├─ Pass 2: parent reconciliation
  └─ Pass 3: close beads whose JIRA is Done

Phase B — jira-push (this skill)
  ├─ Detect orphan beads (no jira: label)
  ├─ Classify, sort, dry-run
  └─ Per-bead Op D creates

Phase C — drift close (jira-sync-back Op B)
  └─ For each bead with jira: label that is closed locally but JIRA is open
     transition JIRA to {jira.transitionOnClose}
```
