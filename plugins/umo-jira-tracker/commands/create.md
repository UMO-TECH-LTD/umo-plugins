---
description: Create a new JIRA issue (sub-task, task, story, bug, or epic) with mandatory parent linkage. Warns and requires explicit approval for any orphan creation. Sub-tasks can never be created without a parent. Automatically syncs the new issue into Beads.
---

# /umo-jira-tracker:create

## Overview

Creates a single new JIRA issue and syncs it into the local Beads database. Enforces the linkage matrix from the `jira-sync-back` skill's `creation-policy.md` reference — every issue must be linked to a parent unless you explicitly override with the `create unlinked` phrase plus a justification.

Sub-tasks **cannot** be created without a parent under any circumstances.

## Input parsing

Extract from free-form input:

| Input | Meaning |
|-------|---------|
| `sub-task`, `subtask`, `Sub-task` | Issue type: Sub-task |
| `task`, `Task` | Issue type: Task |
| `story`, `Story` | Issue type: Story |
| `bug`, `Bug` | Issue type: Bug |
| `epic`, `Epic` | Issue type: Epic |
| `--parent <KEY>` | Explicit parent JIRA key |
| `--under <bead-id>` | Derive parent from this bead's `jira:` label |
| `--title "..."` or `--summary "..."` | Issue summary |
| `--priority <priority>` | Priority (Medium default) |
| Free-form description after flags | Becomes the issue description |

If the issue type is not specified, ask before proceeding.

## Execution

### Step 1 — Verify config

Check `.umo/jira-tracker.json` exists. If not, prompt `/umo-jira-tracker:setup`.

### Step 2 — Collect issue details

If not already provided from input, ask:

1. Issue type (Sub-task / Task / Story / Bug / Epic)
2. Summary (one-line title)
3. Parent JIRA key (from `--parent` flag, claimed bead, `--under`, or ask)
4. Priority (default: Medium)
5. Description (optional — can be filled in later via `/work`)

### Step 3 — Enforce linkage policy

Load the `jira-sync-back` skill (from your skills list), then read its `references/creation-policy.md` file (same directory as the SKILL.md):

- Resolve parent via the priority chain.
- If Sub-task and no parent: **hard block** — abort with instructions.
- If Epic: require `create epic` phrase.
- If any other type and no parent: show orphan warning, require `create unlinked` phrase + justification.

### Step 4 — Preview and create

Delegate to the `jira-sync-back` skill (from your skills list) Operation D:

- Show preview (type, summary, parent, priority, description excerpt).
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
/umo-jira-tracker:create sub-task --parent CWN-1234 --title "Write unit tests for retry logic"

/umo-jira-tracker:create task --parent CWN-100 --title "Add metrics endpoint"

/umo-jira-tracker:create bug --parent CWN-200 --title "Fix null pointer in payment handler"

/umo-jira-tracker:create story --parent CWN-50 --title "User can reset password via email"

/umo-jira-tracker:create sub-task
  # Agent asks for parent and summary interactively

/umo-jira-tracker:create task --title "Standalone investigation"
  # No parent → orphan warning shown; requires 'create unlinked' + justification
```

## Notes

- This command creates one issue at a time. For bulk backlog creation, use `umo-sdlc` planning instead.
- Epics are created rarely — they're usually managed by product/team lead. The command requires the `create epic` confirmation phrase.
- After creation, the new bead is immediately available in `bd ready` if it's a task type.
