---
description: Pull your unresolved JIRA tickets into the local Beads database. Idempotent — safe to run at any time. Defaults to assignee=currentUser AND statusCategory!=Done unless overridden in config or via --jql.
---

# /umo-jira-tracker:sync

## Overview

Sync JIRA issues into the local Beads database using the Story-as-epic mapping. Always shows a dry-run table and asks for approval before mutating beads.

## Input parsing

Extract flags from free-form input:

| Flag / pattern | Meaning |
|----------------|---------|
| `--dry-run` | Show what would happen; do not mutate anything |
| `--jql "<query>"` | Override the default sync JQL for this run only |
| `--force` | Skip the approval prompt (use only when developer explicitly says "just sync") |

## Execution

1. Verify `.umo/jira-tracker.json` exists; if not, prompt to run `/umo-jira-tracker:setup` and stop.
2. Use the `jira-sync` skill (available in your skills list — read it in full using its listed path).

## Examples

```
/umo-jira-tracker:sync
/umo-jira-tracker:sync --dry-run
/umo-jira-tracker:sync --jql "project = CWN AND sprint in openSprints() AND assignee = currentUser()"
```
