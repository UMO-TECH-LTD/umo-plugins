---
description: Pick or claim a bead, load JIRA context, discuss implementation with AI, refine acceptance criteria, and optionally push notes back to JIRA. The primary command for starting work on a sprint ticket.
---

# /umo-jira-tracker:work

## Overview

Start working on a JIRA ticket / bead. Guides the "discuss → decide → store" loop, claims the bead, and offers to push refined AC back to JIRA.

## Input parsing

Extract from free-form input:

| Input | Meaning |
|-------|---------|
| `CWN-1234` or any `[A-Z]+-\d+` | Specific JIRA key |
| Numeric string matching a bead ID | Specific bead ID |
| `--ready` or "show ready" | Pick from `bd ready` output |
| (empty) | Show top 5 ready beads |

## Execution

1. Verify `.umo/jira-tracker.json` exists; if not, prompt `/umo-jira-tracker:setup`.
2. Use the `jira-bead-bridge` skill (available in your skills list — read it in full using its listed path).

## Examples

```
/umo-jira-tracker:work CWN-1234
/umo-jira-tracker:work --ready
/umo-jira-tracker:work 42
/umo-jira-tracker:work
```

## Notes

- If the bead for the given JIRA key doesn't exist locally, prompt to run `/umo-jira-tracker:sync` first.
- This command does not implement the feature — it plans and documents it. Start implementation after the bead is claimed.
- Use `/umo-jira-tracker:create sub-task --parent <KEY>` during the discussion for any discovered sub-tasks.
- **CWN Code Review:** If the ticket is in Code Review, `/work` offers a two-step JIRA transition (Move To Do → Start progress) so you can resume implementation without manual board moves.
