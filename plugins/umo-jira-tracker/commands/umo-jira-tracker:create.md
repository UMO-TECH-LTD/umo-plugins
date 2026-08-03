---
description: Create a new JIRA Task or Bug under a Slice, with mandatory parent linkage. Refuses Story, Sub-task, Epic, Slice, Flow and Request — those either do not exist in this org or are authored by the flow PM. Warns and requires explicit approval for any orphan creation. Automatically syncs the new issue into Beads.
---

# /umo-jira-tracker:create

## Overview

Creates a single new JIRA **Task** or **Bug** under a **Slice**, and syncs it into the local Beads database. Enforces the policy in the `jira-sync-back` skill's `creation-policy.md` reference — every issue must be parented to a Slice unless you explicitly override with the `create unlinked` phrase plus a justification.

The org runs five issue types: Flow, Slice, Task, Request and Bug. This command creates two of them. See `references/work-tracking-model.md` at the plugin root for why.

## Input parsing

Extract from free-form input:

| Input | Meaning |
|-------|---------|
| `task`, `Task` | Issue type: Task |
| `bug`, `Bug` | Issue type: Bug |
| `story`, `sub-task`, `subtask`, `epic`, `slice`, `flow`, `request` | **Refused** — see below |
| `--parent <KEY>` | Explicit parent Slice key |
| `--under <bead-id>` | Derive the Slice from this bead |
| `--title "..."` or `--summary "..."` | Issue summary |
| `--priority <priority>` | Priority (Medium default) |
| Free-form description after flags | Becomes the issue description |

If the issue type is not specified, ask before proceeding.

## Refused types

| Requested | Why | What to do instead |
|---|---|---|
| `story` | The type does not exist. Dev work is a Task, full stop | `create task --parent <SLICE-KEY>` |
| `sub-task` | The type does not exist. Level-0 issues do not nest | Keep it in Beads, or create a sibling Task under the same Slice |
| `epic` | The word is not used — the epic slot is the Slice | Ask the flow PM |
| `slice` / `flow` | Carries demo statements, AC splits, dependency registers, catalogue entries | Ask the flow PM |
| `request` | Carries a product AC, a technical contract, a needed-by date and a mock owner, and starts a 2-working-day SLA | Ask the requesting PM or TL |

There is no override phrase for any of these. Load `creation-policy.md` for the exact refusal messages.

## Execution

### Step 1 — Verify config

Check `.umo/jira-tracker.json` exists. If not, prompt `/umo-jira-tracker:setup`.

### Step 2 — Collect issue details

If not already provided from input, ask:

1. Issue type (Task / Bug)
2. Summary — will be prefixed with the parent Slice's coordinate; Task is an imperative verb phrase, Bug is the symptom not the diagnosis
3. Parent Slice key (from `--parent`, the claimed bead's Slice, `--under`, or ask)
4. Priority (default: Medium)
5. Description (optional — can be filled in later via `/work`)

Do not ask for a sprint, a story-point estimate or a due date. None of them are used.

### Step 3 — Enforce the creation policy

Load the `jira-sync-back` skill (from your skills list), then read its `references/creation-policy.md` file (same directory as the SKILL.md):

- Refuse any type other than Task and Bug.
- Resolve the parent via the priority chain, then **fetch it and verify it is a Slice**. If it is a Task, Bug or Request, offer its Slice instead. If it is a Flow, ask which Slice.
- If no parent resolves: show the orphan warning, require the `create unlinked` phrase plus a justification.

### Step 4 — Preview and create

Delegate to the `jira-sync-back` skill (from your skills list) Operation D:

- Show preview (type, summary, parent Slice, priority, description excerpt).
- On developer approval: call `createJiraIssue`.
- Round-trip to Beads.

### Step 5 — Offer next action

```
{NEW-KEY} created and synced to Beads.

Start working on it now?
  /umo-jira-tracker:work {NEW-KEY}
```

## Examples

```
/umo-jira-tracker:create task --parent PAY-1200 --title "add metrics endpoint"

/umo-jira-tracker:create bug --parent PAY-1200 --title "transfer returns 500 when the payee is archived"

/umo-jira-tracker:create task
  # Agent asks for the parent Slice and summary interactively

/umo-jira-tracker:create task --parent PAY-1234 --title "write fixtures"
  # PAY-1234 is a Task → agent offers its Slice instead

/umo-jira-tracker:create task --title "look into the cache"
  # No parent → orphan warning; suggests the squad's [TH-<KEY>-S0] slice;
  # requires 'create unlinked' + justification

/umo-jira-tracker:create story --parent PAY-1200 --title "..."
  # Refused — Story does not exist in this org
```

## Notes

- This command creates one issue at a time. For bulk backlog creation, use `umo-sdlc` planning instead.
- New issues land in `To Do`. This command never sets a status.
- Not every bead needs a Jira issue. Steps inside one Task are an engineering artifact and stay in Beads — promote a bead only when it becomes a unit of assignment or delivery. The merge gate promotes the rest automatically: no MR merges without a Jira Task.
- After creation, the new bead is immediately available in `bd ready`.
