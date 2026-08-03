# Beads → JIRA Mapping Reference

This file is the authoritative source for how local Beads entities translate into JIRA issue types during a push. Load it whenever performing reverse-sync classification in `jira-push` Phase 2.

Read `../../../references/work-tracking-model.md` first. The short version: this
plugin pushes **Tasks and Bugs, under an existing Slice, and nothing else.**

## Why push is narrower than pull

Pull handles all five types. Push handles two. That asymmetry is deliberate and
comes straight from the 01.08 ruling on agent execution plans:

> the step-by-step execution plan an agent follows *inside* one task is an
> engineering artifact and lives in git (beads or otherwise). It is **not** synced
> to Jira; no bridge is built. Anything that is a **unit of assignment or
> delivery** exists in Jira as a **Task under the slice**.

So the push path exists for exactly one purpose: **promoting a bead that has
turned out to be a unit of delivery** into the Jira Task it should always have
been. It is not a mechanism for mirroring a bead tree into Jira. A bead that is
one step of your own plan stays in git — and if it ends in a merge, the merge
gate promotes it anyway, because no MR merges without a Jira Task.

Flows, Slices and Requests are never pushed. They carry demo statements, inherited
acceptance criteria, dependency registers, contracts, mock owners and due dates.
They are authored by the flow PM and the tech leads, on the board.

## Classification matrix

Process each candidate bead through these rules **in order**. The first matching row wins.

| # | Bead `type` | Parent resolves to a Jira **Slice**? | Proposed JIRA type | Action |
|---|-------------|--------------------------------------|--------------------|--------|
| 1 | `bug` | yes | **Bug** | create |
| 2 | `task` / `chore` / `feature` | yes | **Task** | create |
| 3 | `task` / `chore` / `feature` / `bug` | parent is a Task, Bug or Request | — | **refuse** — see "No nesting below level 0" |
| 4 | `task` / `chore` / `feature` / `bug` | no parent at all | **Task** | **orphan** — requires the `create unlinked` phrase plus a justification |
| 5 | `epic` | any | — | **refuse** — see "Containers are not pushed" |
| 6 | `decision` | any | — | skip silently (ADR / decision beads stay local) |

If `bead.type` is custom, treat it as row 2 or 4 depending on its parent, and let
the developer confirm or override in the dry-run table.

## Containers are not pushed (row 5)

An `epic` bead means one of two things, and neither is pushable:

- It is a **local planning container** — a phase, a wave, a feature pack. It stays
  in git. Its children are pushed individually if and when they become units of
  delivery.
- It **corresponds to a Slice or Flow that should exist in Jira**. Then a human
  creates it, because a Slice needs a demo statement, an inherited/new AC split, a
  dependency register and scope declarations, and a Flow needs a catalogue entry.

Message to show:

```
Cannot push bd-{id} ("{title}") — it is an `epic` bead.

This plugin does not create Flows or Slices. A Slice carries a demo statement,
an inherited/new AC split, a dependency register and scope declarations; a Flow
carries a catalogue entry. Both are authored by the flow PM.

If this bead is a local planning container, leave it in Beads — its children can
still be pushed as Tasks once you know which Slice they belong to.

If a Slice really is missing, ask the flow PM to create it, then re-run /sync.
```

## No nesting below level 0 (row 3)

A Task cannot own a Task. The Sub-task type does not exist in this org, and
level-0 issues are standard issues precisely so they stay rankable and countable.

A bead whose parent is already a Jira Task, Bug or Request is therefore either:

- **part of that Task's execution plan** — the normal case. Leave it in Beads.
- **a unit of delivery in its own right** — then it is a **sibling**, not a child:
  push it as a Task under the same Slice.

Message to show:

```
Cannot push bd-{id} ("{title}") as a child of {PARENT-KEY} — that would be a
Sub-task, and Sub-tasks do not exist in this org.

Two options:
  1. Leave it in Beads. Decomposition inside one Task is a git artifact.
  2. Push it as a sibling Task under the same Slice ({SLICE-KEY}), if it is
     genuinely a separate unit of assignment or delivery.

Choose (leave / sibling):
```

On `sibling`, re-classify the bead with `parentKey = {SLICE-KEY}` and continue.

## Orphans (row 4)

A level-0 issue with no parent is an orphan, and the org runs a standing orphan
detector that alarms the creator and the TL. Do not create one casually. The
`create unlinked` phrase plus a justification is required — see
`../jira-sync-back/references/creation-policy.md`.

The right fix is almost always to find the Slice. If the work is genuine tech
debt with no home, its home is the squad's standing tech-health slice
`[TH-<KEY>-S0]` — suggest that before falling back to an orphan.

## Status mapping (used at push time)

New issues are born in the project's default status (`To Do`). Push **never** sets
a status or a resolution directly.

If a bead is already closed locally and is being pushed for the first time (rare),
create it and let the drift-close phase transition it. Note that a Task reaching
`Done` normally happens through the merged-MR automation, not through this plugin.

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

## Fields push must never set

| Field | Why |
|---|---|
| Sprint (`customfield_10020`) | unused org-wide |
| Story points | unused org-wide |
| Original estimate / time tracking | cost is time-in-status, measured not estimated |
| Due date | meaningless on a Task; it belongs on Requests only |
| Epic Link (`customfield_10014`) | superseded by native `fields.parent` |

## Summary grammar

The Jira summary is not the bead title verbatim. Build it as:

```
[{SLICE-COORDINATE}] {imperative verb phrase}
```

Take the coordinate from the parent Slice's own summary prefix (e.g. `IC-S2`). A
**Task** summary is an imperative verb phrase; a **Bug** summary is the symptom,
not the diagnosis. Banned in either: layer names, person names, status words,
"part 2 / misc / fixes".

If the bead title does not fit the grammar, propose a rewritten summary in the
dry-run table and show the original alongside it.

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

### Example 1 — Execution plan under a synced Task

```
bead bd-30 (jira:PAY-1234, jira-type:task)
├── bead bd-31 (type=task, parent bd-30, title="Write fixtures")
└── bead bd-32 (type=task, parent bd-30, title="Wire the retry policy")
```

| Bead | Proposed | Reason |
|------|----------|--------|
| bd-31 | — | row 3 — parent is a Task. This is bd-30's execution plan; it stays in Beads |
| bd-32 | — | row 3 — same |

Nothing is pushed, and that is the correct outcome. Both beads are steps inside
one unit of delivery.

### Example 2 — A step turns out to be its own unit of delivery

Same tree, but the retry policy turns into two days of work that QA needs to see:

| Bead | Proposed | Reason |
|------|----------|--------|
| bd-32 | Task under PAY-1200 | row 3 → developer chose `sibling`. Parent re-targeted from the Task to its Slice |

### Example 3 — Local planning container

```
bead bd-100 (type=epic, no parent, title="Phase-2 rollout")
└── bead bd-101 (type=task, parent bd-100, title="Add metrics endpoint")
```

| Bead | Proposed | Reason |
|------|----------|--------|
| bd-100 | — | row 5 — refused. Containers are not pushed |
| bd-101 | Task | row 4 — its parent has no Jira key, so it is an orphan. The developer is asked which Slice it belongs to before `create unlinked` is offered |
