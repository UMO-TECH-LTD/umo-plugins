---
description: First-run setup wizard — verify tools (bd, glab, Atlassian MCP), collect per-repo config, and write .umo/jira-tracker.json. Safe to re-run to update values.
---

# /umo-jira-tracker:setup

## Overview

Configure the `umo-jira-tracker` plugin for the current repository.

Reads the `jira-tracker-setup` skill and follows it to completion.

## When to run

- First time using the plugin in this repo (`.umo/jira-tracker.json` is absent).
- After installing a new tool (`glab`, `bd`).
- When JIRA project, target branch, or MR preferences change.

## Input

No required input. Optional flags parsed from free-form input:

| Flag | Meaning |
|------|---------|
| `--force` | Overwrite existing config without diff-and-ask |
| `--check-only` | Verify tools and show current config; do not prompt for changes |

## Execution

Use the `jira-tracker-setup` skill (available in your skills list — read it in full using its listed path).

Report outcome:

```
/umo-jira-tracker:setup complete
  Config file: .umo/jira-tracker.json
  Tools verified: bd ✓  glab ✓  Atlassian MCP ✓
```

If any required tool is missing, abort with clear install instructions and a non-zero mental exit.
