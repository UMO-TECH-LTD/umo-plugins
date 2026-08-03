---
description: First-run setup wizard — verify tools (bd, glab, Atlassian MCP), collect per-repo config, auto-resolve your JIRA account ID and GitLab user ID, and write .umo/jira-tracker.json. Safe to re-run to update values.
---

# /umo-jira-tracker:setup

## Overview

Configure the `umo-jira-tracker` plugin for the current repository.

Reads the `jira-tracker-setup` skill and follows it to completion. During config collection the wizard asks for your squad project key and whether `/sync` should pull **all open assigned issues**, **one flow** (everything serving it, across projects), or **one slice** — with an optional issue-count preview via Atlassian MCP.

There is no sprint scope: the Sprint field is unused org-wide.

## When to run

- First time using the plugin in this repo (`.umo/jira-tracker.json` is absent).
- After installing a new tool (`glab`, `bd`).
- When the squad project, target branch, or MR preferences change.
- To drop legacy config keys (`jira.defaultSprintId`, `jira.transitionOnMr`, `sync.pushSubtasks`, `sync.pushLabel`) from an older install.

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
