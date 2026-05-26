---
description: Bidirectional sync between JIRA and the local Beads database. Phase A pulls JIRA issues into Beads (idempotent upsert). Phase B pushes locally-created beads (no `jira:` label) up to JIRA. Phase C reconciles status drift. All phases preview their changes and ask for approval before mutating anything.
---

# /umo-jira-tracker:sync

## Overview

`/sync` is the single command that keeps Beads and JIRA aligned. It runs three phases in order, each independently approval-gated:

| Phase | Skill | Direction | What it does |
|-------|-------|-----------|--------------|
| A | `jira-sync` | JIRA → Beads | Upsert assigned issues (open + recently-Done window) |
| B | `jira-push` | Beads → JIRA | Push beads with no `jira:` label as Epic / Story / Task / Bug / (opt-in) Sub-task |
| C | `jira-sync-back` Op B | Beads → JIRA | Transition JIRA tickets whose bead was closed locally |

By default, all three phases run. Use the flags below to scope a single run.

## Input parsing

Extract flags from free-form input:

| Flag / pattern | Meaning |
|----------------|---------|
| `--dry-run` | Show what would happen in every phase; do not mutate anything |
| `--jql "<query>"` | Override the default sync JQL for Phase A only |
| `--pull-only` | Run Phase A and stop (skip B and C) |
| `--push-only` | Skip Phase A; run B and C only. Requires a Phase A run from the same session within the last hour, otherwise warns and offers to run pull first |
| `--force` | Skip the approval prompts (use only when developer explicitly says "just sync") |

`--pull-only` and `--push-only` are mutually exclusive.

Honor `.umo/jira-tracker.json` → `sync.direction`:

| Value | Effective phases |
|-------|------------------|
| `both` (default) | A + B + C |
| `pull` | A only |
| `push` | B + C only (auto-runs A first if no recent inventory exists) |

CLI flags always override the config value for that single run.

## Execution

1. Verify `.umo/jira-tracker.json` exists; if not, prompt to run `/umo-jira-tracker:setup` and stop.
2. **Phase A — Pull.** Use the `jira-sync` skill (available in your skills list — read it in full using its listed path). Phase A also performs the Pass 0 inventory used by Phase B.
3. **Phase B — Push.** Use the `jira-push` skill (available in your skills list). It consumes the Pass 0 inventory, detects orphan beads, builds the dry-run table, and delegates each create to `jira-sync-back` Operation D.
4. **Phase C — Drift close.** For each bead carrying a `jira:` label that is `closed` locally but whose JIRA status category is not `Done`, delegate to `jira-sync-back` Operation B with `jira.transitionOnClose`. Single approval gate per project run.
5. Print the combined report:

```
Sync complete:

  Phase A — pull:    5 created, 3 updated, 1 closed, 12 skipped
  Phase B — push:    3 created, 1 sub-task-skipped, 0 failed
  Phase C — drift:   2 JIRA tickets transitioned to Done

Run `bd ready --json` to see what's next.
```

## Examples

```
/umo-jira-tracker:sync
/umo-jira-tracker:sync --dry-run
/umo-jira-tracker:sync --pull-only
/umo-jira-tracker:sync --push-only
/umo-jira-tracker:sync --jql "project = CWN AND sprint in openSprints() AND assignee = currentUser()"
```

## Notes

- Phase B is **skipped silently** when no orphan beads exist — the developer sees `Phase B — push: 0 candidates`.
- Push always asks once per bead. `--force` skips the per-bead preview but **never** skips the orphan / `create epic` phrase requirement enforced by `creation-policy.md`.
- A bead can opt out of push entirely by carrying the `{sync.skipLabel}` label (default `jira-skip`).
- A bead can force-include itself (even when it maps to a Sub-task) by carrying the `{sync.pushLabel}` label (default `jira-push`).
