---
description: Close the current bead with evidence, post a closing comment to JIRA, and transition the Task or Bug to Done (or the configured transitionOnClose). All JIRA mutations are approval-gated.
---

# /umo-jira-tracker:close

## Overview

Closes a bead and syncs the outcome back to JIRA. Always previews the comment and transition before touching JIRA.

## Input parsing

| Input | Meaning |
|-------|---------|
| `PAY-1234` or `[A-Z]+-\d+` | Close the bead labelled `jira:PAY-1234` |
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

1. Preview the closing comment and the transition.
2. On approval: post the comment, then transition.

**Check the issue's current status first.** `Task Done = PR merged, all existing tests green`, and org automation flips the Task when the MR merges. If it is already Done, say so and skip the transition rather than re-applying it.

**Only Tasks and Bugs are transitioned from here.** If the key resolves to a Slice, Flow or Request, close the bead and stop — Slice gates are validated on the board, Flow status is derived from its children, and a Request is Closed by the consumer on proof.

**Done, not Retired.** If the work was abandoned rather than delivered, that is a Retired transition with a mandatory Resolution, and it is a different conversation — do not reach for `transitionOnClose`.

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
/umo-jira-tracker:close PAY-1234
/umo-jira-tracker:close 42
```
