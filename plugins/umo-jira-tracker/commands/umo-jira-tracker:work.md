---
description: Pick or claim a bead, load JIRA context, discuss implementation with AI, refine acceptance criteria, and optionally push notes back to JIRA. The primary command for starting work on a Task or Bug.
---

# /umo-jira-tracker:work

## Overview

Start working on a JIRA Task or Bug. Guides the "discuss → decide → store" loop, claims the bead, and offers to push refined AC back to JIRA.

## Input parsing

Extract from free-form input:

| Input | Meaning |
|-------|---------|
| `PAY-1234` or any `[A-Z]+-\d+` | Specific JIRA key |
| Numeric string matching a bead ID | Specific bead ID |
| `--ready` or "show ready" | Pick from `bd ready` output |
| (empty) | Show top 5 ready beads |

## Execution

1. Verify `.umo/jira-tracker.json` exists; if not, prompt `/umo-jira-tracker:setup`.
2. Use the `jira-bead-bridge` skill (available in your skills list — read it in full using its listed path).

## Examples

```
/umo-jira-tracker:work PAY-1234
/umo-jira-tracker:work --ready
/umo-jira-tracker:work 42
/umo-jira-tracker:work
```

## Notes

- If the bead for the given JIRA key doesn't exist locally, prompt to run `/umo-jira-tracker:sync` first.
- This command does not implement the feature — it plans and documents it. Start implementation after the bead is claimed.
- **Decompose in Beads.** Steps inside this Task are an engineering artifact and stay in git: `bd create "..." --type task --parent <bead-id>`. They are not synced to Jira.
- Only a separate **unit of assignment or delivery** needs its own Jira Task, and it is a **sibling** under the same Slice: `/umo-jira-tracker:create task --parent <SLICE-KEY>`. A Task cannot own a Task.
- **Resuming:** if the issue is not in a startable state, `/work` resolves the available transitions live and offers the move to In Progress in a single approval gate. Slices, Flows and Requests are never transitioned from here.
