---
name: jira-push
description: Reverse-direction sync — promote locally-created beads (no `jira:` label) into JIRA as Tasks or Bugs under a Slice. Never creates Flows, Slices or Requests, and never mirrors an execution plan. Always previews, resolves the parent Slice first, and delegates the actual `createJiraIssue` call to `jira-sync-back` Operation D so the existing approval and orphan-warning logic is reused. Invoked by `/umo-jira-tracker:sync` Phase B.
paths:
  - ".umo/jira-tracker.json"
  - "**/.beads/**"
---

# JIRA Push

Promotes a bead that has become a **unit of assignment or delivery** into the JIRA Task or Bug it should be. A bead created locally with `bd create` and therefore carrying **no `jira:` label** is a candidate.

Load `../../references/work-tracking-model.md` for the org's encoding.
Load `references/bead-type-mapping.md` for the classification rules.
Load `../jira-sync-back/references/creation-policy.md` for the orphan and refusal rules — every push goes through the same chokepoint.

## What this skill is not

It is **not** a mirror. Beads and JIRA are not two views of one tree, and the 01.08 ruling is explicit about the line between them:

> the step-by-step execution plan an agent follows *inside* one task is an engineering artifact and lives in git (beads or otherwise). It is **not** synced to Jira; no bridge is built.

So most beads are correctly never pushed, and a run that promotes nothing is a normal outcome rather than a failure. Push creates **Tasks and Bugs, under a Slice**. Flows, Slices and Requests are authored on the board by the flow PM and the tech leads.

You rarely need to reach for this at all: the merge gate settles the common case, because no MR merges without a Jira Task.

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
  "skipLabel": "jira-skip"
}
```

| Key | Meaning |
|-----|---------|
| `sync.direction` | `both` (default) / `pull` / `push` — controls which phases of `/sync` run |
| `sync.skipLabel` | Bead label that forces exclusion regardless of other rules (default `jira-skip`) |

There is no `pushSubtasks` or `pushLabel`. Sub-tasks do not exist, and the classifier already declines anything that is not a unit of delivery — an opt-in label would just be a way to override that rule.

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
- No `{sync.skipLabel}` label.

Do not pre-filter by bead type — `epic` beads are classified and refused with an explanation, which is more useful than silence.

### Phase 2 — Classify each candidate

For each candidate bead, walk its parent chain via `bd show {id} --json` (read `parent_id`, `dependencies`, and any existing `jira:` / `jira-type:` labels on the parent) and apply the classification rules in `references/bead-type-mapping.md`.

Inputs to the classification:

| Signal | Source |
|--------|--------|
| `bead.type` | `bd show ... --json` field `type` |
| `parent bead exists` | `bd show ... --json` field `parent_id` (preferred) or first `parent-of` dependency |
| `parent.jira-type` | Parent bead label `jira-type:*` — the decisive signal: only `slice` is a valid parent |
| `parent.jira-key` | Parent bead label `jira:*` |
| `parent.jira-flow` | Parent bead label `jira-flow:*` — shown in the dry-run so the developer sees which flow pays |

Output for each candidate:

```
{
  beadId, beadTitle, beadType,
  parentBeadId, parentJiraKey, sliceKey, flowKey,
  proposedJiraType,    // Task | Bug | none
  proposedSummary,     // rewritten to the naming grammar if needed
  action,              // create | refuse-container | refuse-nesting | orphan | skip
  reason               // human-readable
}
```

The three non-create outcomes each carry a specific message in `references/bead-type-mapping.md`; use them verbatim rather than a generic "cannot push":

- **refuse-container** — the bead is an `epic`. Slices and Flows are the flow PM's to author.
- **refuse-nesting** — the parent is a Task, Bug or Request. That would be a Sub-task. Offer to leave it in Beads, or to push it as a **sibling** under the same Slice.
- **orphan** — no parent resolves. Suggest the squad's `[TH-<KEY>-S0]` slice before falling back to `create unlinked`.

### Phase 3 — Order the work

There is no parent-first topological pass to run: this skill never creates the parent, because the only valid parent is a Slice and Slices are not pushed. A candidate either resolves to an existing Slice key or it does not.

Sort candidates by Slice so the dry-run groups them, then by bead ID for stability.

### Phase 4 — Dry-run table

Always show the table, even when `--dry-run` is not passed. This mirrors the pull-side UX.

```
Push candidates:

| Bead  | Type | Title                      | Slice    | Proposed | Action |
|-------|------|----------------------------|----------|----------|--------|
| bd-43 | task | Implement producer wrapper | PAY-1200 | Task     | create |
| bd-44 | task | Write unit tests           | —        | —        | refuse-nesting (parent bd-43 is a Task) |
| bd-42 | epic | Phase-2 rollout            | —        | —        | refuse-container |
| bd-50 | task | Standalone investigation   | —        | Task     | orphan (needs `create unlinked`) |

Summary: 1 create, 1 orphan-pending, 2 refused.

Proceed with push? (yes/no/select)
```

`select` lets the developer cherry-pick rows by ID before continuing.

When a candidate's title does not follow the naming grammar, show the proposed summary next to the original so the rewrite is visible before it is committed.

**Zero candidates is a normal result, not an error.** Report it plainly:

```
Push: 0 candidates. Every open bead is either already in JIRA, a step inside an
existing Task, or a local planning container.
```

If `--dry-run` was passed, stop here and exit.

### Phase 5 — Per-bead push

For each row marked `create`, delegate to `jira-sync-back` Operation D. That skill is already responsible for:

1. Loading `creation-policy.md`, refusing any type other than Task and Bug, and verifying the parent is a Slice.
2. Showing the per-issue preview (summary, type, Slice, Flow, priority, assignee from `user.jiraAccountId`, description excerpt).
3. Calling `createJiraIssue` — with no sprint, story points, estimate, due date, Epic Link or label in the payload.
4. Round-tripping the new key into Beads (labels + JIRA-sourced description zone).

This skill is responsible for **building the description and selecting the Slice key** before handing off:

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
- **Type**: {Task|Bug}
- **Status**: To Do
- **Priority**: {priority}
- **Slice**: {SLICE-KEY} — {slice summary}
- **Flow**: {FLOW-KEY} — {flow summary}

### Acceptance Criteria

{original bead description, verbatim — preserved as the AC zone}

## Notes

{any pre-existing notes from the bead, preserved}
```

#### Selecting the Slice key

The only valid parent is a Slice. Resolve it as:

| Case | Parent key passed to Op D |
|------|---------------------------|
| Parent bead carries `jira-type:slice` | its `jira:{KEY}` |
| Parent bead carries `jira-type:task` / `bug` / `request` | the **Slice above it** — after the developer chose `sibling` at the refuse-nesting prompt |
| Parent bead has no `jira:` label | none — orphan warning (Op D requires `create unlinked` + justification), after suggesting the squad's `[TH-<KEY>-S0]` slice |
| No parent bead at all | none — same orphan path |

A Slice in a different project is legitimate: the flow that caused the work pays for it.

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
| refused (container) | 1 |
| refused (nesting) | 2 |
| failed  | 0 |

Failures (if any):
  bd-99: Atlassian MCP returned 400 — see preview above.

Next: locally-closed beads will be reconciled with JIRA next.
```

Refused rows are not failures — they are beads that correctly stay in git.

## Error handling

- **Op D refuses creation** (developer cancels at the preview, or the orphan phrase is not given): record as `skipped` and continue with the next candidate. Never abort the whole push.
- **`createJiraIssue` returns non-2xx**: surface the error, mark the candidate as `failed`, leave the bead untouched. Subsequent runs will retry.
- **The parent Slice is not found or is not a Slice**: mark the candidate `skipped` with the reason, and name the Slice key that was expected. Do not fall back to creating it.
- **Rate limits** (429): wait 5s, retry once. If still 429, mark `failed` and continue.

## Idempotency

This skill is safe to re-run because:

1. Candidates are derived from "no `jira:` label". Once a bead is pushed, it gains a `jira:` label and is excluded from future runs.
2. The dry-run table always shows what would change before any write.
3. Op D's preview is per-bead; a developer that says "no" simply leaves the bead unsynced for next run.

## Combined `/sync` flow (reference)

```
Phase A — jira-sync (pull)          all five types
  ├─ Pass 0: inventory existing jira: labels
  ├─ Pass 1: upsert open issues + recently-closed window
  ├─ Pass 2: parent reconciliation (cross-project is normal)
  └─ Pass 3: close beads whose JIRA reached Done / Closed / Retired

Phase B — jira-push (this skill)    Tasks and Bugs only
  ├─ Detect beads with no jira: label
  ├─ Classify (refuse containers and nesting), sort by Slice, dry-run
  └─ Per-bead Op D creates under the Slice

Phase C — drift close (jira-sync-back Op B)
  └─ For each bead with a jira: label that is closed locally but whose JIRA
     issue is still open, transition to {jira.transitionOnClose}.
     Check first: if the MR is merged, the org automation has already
     flipped the Task to Done.
```
