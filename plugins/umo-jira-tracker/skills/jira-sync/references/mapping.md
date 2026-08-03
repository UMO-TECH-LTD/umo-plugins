# JIRA → Beads Mapping Reference

This file is the authoritative source for how JIRA issue types translate into Beads entities. Load it whenever performing a sync, upsert, or parent-reconciliation step.

The issue types below are the org's five and only five. Read `../../../references/work-tracking-model.md` before using this file — it explains why Story, Sub-task and the Sprint field do not appear here.

## Issue type → Bead type matrix

| JIRA issue type | Hierarchy level | Bead type | Parent bead |
|-----------------|-----------------|-----------|-------------|
| Flow | 2 | `epic` | none — Flow is the root |
| Slice | 1 (epic slot) | `epic` | Flow-bead of `fields.parent` (if in scope) |
| Task | 0 | `task` | Slice-bead of `fields.parent` |
| Bug | 0 | `task` | Slice-bead of `fields.parent` |
| Request | 0 | `task` | Slice-bead of `fields.parent` — note this is the **consumer's** slice, cross-project |

### Why Flow and Slice are both `epic`

Beads supports a two-level tree (`epic` → `task`). Jira Premium gives three
levels (Flow → Slice → level-0 issues). Mapping both container levels to `epic`
lets Tasks, Bugs and Requests sit as child beads via `--parent`, and lets a
Slice-bead itself hang under a Flow-bead, without flattening the hierarchy.

Nothing below the level-0 issues is ever pulled, because nothing below them
exists in Jira.

### Requests are read-only here

A Request is a promise between two teams, carrying a contract, a mock owner and a
due date. Pull it so the developer can see what is still fake, and so `Blocks`
links resolve. **Never create, transition or retire a Request from this plugin** —
Accept is the provider tech lead's act, Closed is the consumer's proof, and
Retired is consumer-owned. Route those to the board.

## Identity and labelling

Every synced bead carries these identifiers so future sync runs can find it without scanning all beads.

### Bead title

```
[{JIRA-KEY}] {JIRA summary}
```

Example: `[PAY-1234] Add Kafka retry logic`

The Jira summary already carries the slice coordinate prefix (`[IC-S2] …`), so a
fully-formed bead title reads `[PAY-1234] [IC-S2] Retry publishes survive a broker restart`. Do not strip or rewrite the coordinate.

### Bead labels

| Label | Value | Example |
|-------|-------|---------|
| `jira:{KEY}` | JIRA issue key | `jira:PAY-1234` |
| `jira-type:{type}` | Lowercase JIRA issue type — one of `flow`, `slice`, `task`, `bug`, `request` | `jira-type:task` |
| `jira-status:{status}` | Kebab-cased JIRA status name | `jira-status:in-progress` |
| `jira-parent:{KEY}` | Parent JIRA key (if any) | `jira-parent:PAY-1200` |
| `jira-flow:{KEY}` | Flow key resolved by walking the parent chain to level 2 | `jira-flow:PAY-900` |

`jira-flow:` is derived, not read from a field — walk `fields.parent` upward until
you reach an issue whose type is `Flow`. If the chain breaks before then (the
ancestor is outside the JQL scope and could not be fetched), omit the label
rather than guessing.

**There is no sprint label.** The Sprint field is unused org-wide.

### Bead description structure

The bead description is split into two zones:

1. **JIRA-sourced zone** (auto-overwritten on each sync):

```markdown
## JIRA

- **Key**: PAY-1234
- **URL**: https://umotech.atlassian.net/browse/PAY-1234
- **Type**: Task
- **Status**: In Progress
- **Priority**: Medium
- **Slice**: PAY-1200 — [IC-S2] Client can see their status
- **Flow**: PAY-900 — [IC] Client onboarding

### Acceptance Criteria

<content from JIRA description / AC field>
```

For a **Request**, add the two lines that make the promise legible, and nothing
more — the contract itself stays on the Jira issue and is not copied into beads:

```markdown
- **Needed by**: 2026-08-14  (Due date — doubles as mock expiry)
- **Mock owner**: Compliance
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

**Key the decision off `statusCategory`, not the status name.** All terminals sit
in the `Done` category, and the exact name varies by type and configuration —
`Retired` is its own status, and the Request terminal is `Done` in the live
workflow though canon names it `Closed`. Read the name only to build the reason.

| Condition | Action |
|-----------|--------|
| `statusCategory` is `Done` and status is `Retired` | Close bead: `bd close <id> --reason "JIRA: Retired — {resolution}"`. Read `fields.resolution.name`; if empty, close anyway and warn — Resolution is required by policy, and the live transition does not enforce it, so its absence is a real data defect |
| `statusCategory` is `Done`, type is **Request** | Close bead: `bd close <id> --reason "JIRA: Request {statusName} — consumer proof"` |
| `statusCategory` is `Done`, any other type | Close bead: `bd close <id> --reason "JIRA: status={statusName}"` |
| anything else | Leave the bead open; update the `jira-status:` label |

Only close a bead that is not already closed.

**Retired is not Done.** A retired issue was withdrawn from play without being
completed, and it is excluded from every count. Jira files it under the `Done`
*category* regardless, which is exactly why the close reason has to preserve the
distinction — otherwise the local record reads as delivered work.

**One-way rule**: The sync never re-opens a bead that was closed by the developer. If JIRA reverts to `In Progress` after a local close, the bead stays closed and a warning is printed.

## Two-pass parent reconciliation

Parent beads must exist before child beads can reference them. Sync runs in two passes:

1. **Pass 1**: Upsert all issues without setting parents.
2. **Pass 2**: For each issue with a JIRA parent key, look up the parent bead via `bd list --label "jira:{PARENT-KEY}" --json` and set `bd update <child-id> --parent <parent-bead-id>`.

If a parent bead is not found in pass 2, print a warning and continue (the developer may have filtered it out of the JQL scope).

**Cross-project parents are normal, not an anomaly.** A Request lives in the
provider's project but parents to the consumer's Slice; provider Tasks may also
be parented cross-project under a consumer slice for billing. Never "correct" a
parent whose project key differs from the child's.
