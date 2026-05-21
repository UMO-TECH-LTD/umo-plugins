---
description: Close the current bead with evidence, post a closing comment to JIRA, and transition the ticket to Done (or the configured transitionOnClose). All JIRA mutations are approval-gated.
---

# /umo-jira-tracker:close

## Overview

Closes a bead and syncs the outcome back to JIRA. Always previews the comment and transition before touching JIRA.

## Input parsing

| Input | Meaning |
|-------|---------|
| `CWN-1234` or `[A-Z]+-\d+` | Close the bead labelled `jira:CWN-1234` |
| Numeric bead ID | Close that bead directly |
| (empty) | Detect from currently claimed bead; ask if ambiguous |

## Execution

### Step 1 — Resolve bead

```bash
# By JIRA key
bd list --label "jira:{KEY}" --json

# By bead ID
bd show {id} --json
```

If the bead is already closed, confirm with the developer whether to only post the JIRA comment/transition without touching the bead.

### Step 2 — Collect closing evidence

Ask the developer:

1. "Is there an MR URL to include?" (pre-fill from `glab mr list --source-branch ...` if available)
2. "Any summary of what was done?" (optional; defaults to the bead title)

### Step 3 — Close bead

```bash
bd close {bead-id} --reason "Completed: {summary}. MR: {MR_URL}" --json
```

Report: `Bead {id} closed.`

### Step 4 — Sync back to JIRA

Use the `jira-sync-back` skill (from your skills list) — `/close` combined flow:

1. Preview closing comment and transition.
2. On approval: post comment, then transition.

### Step 5 — Report

```
Done!

  Bead:   {id} [{KEY}] — closed
  JIRA:   {KEY} — comment posted, transitioned to {transition}
  MR:     {MR_URL}
```

## Examples

```
/umo-jira-tracker:close
/umo-jira-tracker:close CWN-1234
/umo-jira-tracker:close 42
```
