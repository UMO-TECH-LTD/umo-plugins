# Beads → JIRA Mapping Reference

This file is the authoritative source for how local Beads entities translate into JIRA issue types during a push. Load it whenever performing reverse-sync classification in `jira-push` Phase 2.

## Why this is the inverse of `jira-sync/references/mapping.md`

The pull direction is lossy — both JIRA `Epic` and `Story` collapse into the bead type `epic` because Beads only supports a two-level tree. On the way back up we need to recover that distinction from contextual signals (parent presence, parent's JIRA type, the developer's intent).

## Classification matrix

Process each candidate bead through these rules **in order**. The first matching row wins.

| # | Bead `type` | Parent bead present? | Parent `jira-type` label | Parent originated from JIRA? | Proposed JIRA type | Notes |
|---|-------------|----------------------|--------------------------|------------------------------|---------------------|-------|
| 1 | `epic` | no | — | — | **Epic** | Top-level root. Will require `create epic` phrase per creation-policy |
| 2 | `epic` | yes | `epic` | — | **Story** | Story lives under a JIRA Epic |
| 3 | `epic` | yes | `story` | — | **Story** | Reparent under the Story's parent Epic (see "Parent re-targeting" below) |
| 4 | `epic` | yes | (none — parent local-only) | — | **Story** | Parent will be pushed first as either Epic or Story |
| 5 | `task` / `chore` / `feature` | no | — | — | **Task** | Orphan Task. Requires `create unlinked` |
| 6 | `task` / `chore` / `feature` | yes | `epic` | yes | **Task** | Direct child of an Epic |
| 7 | `task` / `chore` / `feature` | yes | `story` | yes | **Sub-task** | Default sub-task path |
| 8 | `task` / `chore` / `feature` | yes | `task` / `bug` | yes | **Sub-task** | Sub-tasks can sit under Task or Bug |
| 9 | `task` / `chore` / `feature` | yes | (none — parent local-only) | — | inherit from parent classification | Recurse |
| 10 | `bug` | no | — | — | **Bug** | Orphan Bug — orphan warning |
| 11 | `bug` | yes | `epic` / `story` | yes | **Bug** | Linked to an Epic or Story |
| 12 | `bug` | yes | `task` / `bug` | yes | **Sub-task** | Bug-as-subtask is allowed in JIRA |
| 13 | `decision` | any | — | — | **skip** | ADR / decision beads stay local |

If `bead.type` is custom (e.g. an enterprise extension), default to **Task** and let the developer confirm or override in the dry-run table.

## Parent re-targeting (row 3)

When a bead's parent maps to a JIRA Story (`jira-type:story`), the JIRA hierarchy expects:

```
Epic
└── Story (parent bead)
    └── Sub-task (this bead, normally)
```

But we are pushing **another `epic`-typed bead**, not a Sub-task. Sub-tasks cannot have children in JIRA, so a Story under a Story is invalid. The fix is to walk the parent chain one more level up to find the JIRA Epic and use it as `parent`:

```
Bead chain:     epic-A → epic-B → epic-C (this push)
JIRA chain so far: Epic-A → Story-B
Target:              Epic-A → Story-B  (unchanged)
                          └── Story-C   ← attach here
```

Result: Story-C is parented to Epic-A (the JIRA Epic that anchors Story-B). Record this in the dry-run as `Parent re-target: bd-B → CWN-A` so the developer sees the divergence.

## Sub-task default policy

Rows 7, 8, 12 produce **Sub-task**. By policy (`sync.pushSubtasks=false`), Sub-task candidates are **skipped** unless one of the following is true:

- The bead carries `{sync.pushLabel}` (default `jira-push`).
- `sync.pushSubtasks` is set to `true` globally.

When skipped, the bead remains in Beads with no `jira:` label, ready to be picked up next time the policy or label changes.

## Status mapping (used at push time)

When a bead is closed locally and is being pushed for the first time (rare), the resulting JIRA issue is created in the project's default status (`To do` / `Backlog`) and then the drift-close phase will transition it. Push **never** sets `resolution` directly because most CWN-class workflows require a screen.

For open beads, no extra status work is needed — the JIRA issue is born `To do` / `Backlog`.

## Priority mapping

Beads priority (`0`/`P0` highest → `4`/`P4` lowest) maps to JIRA priority names:

| Bead | JIRA priority |
|------|---------------|
| `0` / `P0` | Highest |
| `1` / `P1` | High |
| `2` / `P2` (default) | Medium |
| `3` / `P3` | Low |
| `4` / `P4` | Lowest |

If the project does not configure a priority field, omit it and let JIRA apply its default.

## Description structure passed to Operation D

`jira-push` builds the JIRA description like this before handing off:

```markdown
{verbatim bead description}

---

> **Pushed from Beads** — bead-id: `{beadId}` on `{ISO date}` by `{gitlabUsername}`.
> Source of truth for this issue lives in the local Beads database until the round-trip back-fills the JIRA-sourced zone.
```

`createJiraIssue` accepts this string as `fields.description`. Op D's preview shows the first 200 characters — full text is sent.

## Examples

### Example 1 — Local feature branch

```
bead bd-100 (type=epic, no parent, title="Phase-2 rollout")
└── bead bd-101 (type=task, parent bd-100, title="Backend wiring")
    └── bead bd-102 (type=task, parent bd-101, title="Add metrics")
```

After classification:

| Bead | Proposed | Reason |
|------|----------|--------|
| bd-100 | Epic | row 1 |
| bd-101 | Task | row 6 (after bd-100 becomes an Epic) |
| bd-102 | Sub-task | row 8 (Task parent). **Skipped** unless `jira-push` label is present |

Topological order: bd-100 → bd-101 → bd-102 (if not skipped).

### Example 2 — Sub-task added under an existing JIRA Story

```
bead bd-30 (jira:CWN-1234, jira-type:story)
└── bead bd-31 (type=task, parent bd-30, title="Write fixtures", labels=[jira-push])
```

After classification:

| Bead | Proposed | Reason |
|------|----------|--------|
| bd-31 | Sub-task | row 7 — parent already in JIRA as Story. `jira-push` label overrides the skip policy. Parent key: `CWN-1234` |

### Example 3 — Orphan investigation

```
bead bd-77 (type=task, no parent, title="Why is the cache misbehaving?")
```

| Bead | Proposed | Reason |
|------|----------|--------|
| bd-77 | Task | row 5 — orphan. Triggers `create unlinked` justification flow in Op D |
