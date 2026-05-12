---
description: UMO Agentic SDLC planning with Beads — turn intent, research, proposals, incidents, review findings, or postmortems into executable Beads work (epics, tasks, spikes, dependencies, labels, evidence closeout).
argument-hint: "[source artifact or planning request]"
---

# UMO Planning (Beads)

Source: $ARGUMENTS

Invoke the `planning` skill (`plugins/umo-sdlc/skills/planning/SKILL.md`) for full lifecycle, issue shapes, labels, comments, close reasons, and command examples. Use this command as the entry point.

## Core boundary

- **Docs** preserve durable context: research, proposals, ADRs, specs, guides, references, incidents.
- **Beads** represent executable work: epics, tasks, spikes, dependencies, provenance, quality gates, comments, closeout evidence.
- Do not replace proposals, ADRs, specs, or postmortems with Beads descriptions.
- Do not silently create a large bead tree when the user asked only for research. Propose the planning transition and ask for approval unless issue creation was requested.

## Planning triggers

Suggest Beads planning when:

- research or a proposal is finalized;
- a proposal is accepted and ready for implementation;
- an incident / postmortem has corrective actions;
- code review finds follow-up work;
- implementation discovers work that should not be done immediately;
- the user asks "what next?", "plan this", "break this down", or mentions Beads / `bd`.

## Minimum bead tree shape

- Epic has source, outcome, scope, non-goals, acceptance criteria, risks, and linked `decision` beads for human decision points.
- Child tasks are small enough for focused agent sessions and include verification.
- Spikes capture learning questions and stop conditions.
- Dependencies make `bd ready` show the intended first work.
- Discovered work uses `discovered-from` provenance.
- Follow-ups from incidents use `source/incident` labels and close with evidence.

## Typical commands

```bash
bd ready --json
bd show <id> --json
bd create --title="..." --description="..." --type=task --priority=2 --json
bd update <id> --claim --json
bd close <id> --reason="Completed: ..." --json
```

For a proposal / spec handoff:

```bash
bd create --title="<proposal outcome>" --description="<summary, source link, acceptance criteria>" --type=epic --priority=2 --json
bd create --title="<child task>" --description="<specific outcome and verification>" --type=task --priority=2 --parent <epic-id> --json
bd dep add <blocked-task> <blocking-task>
bd dep tree <epic-id>
```

## Readiness criteria

A bead tree is ready for execution when:

- every epic has a clear outcome and source;
- every child task has acceptance criteria and verification;
- dependencies are explicit and `bd ready` shows the intended first work;
- spikes are separate from implementation tasks;
- human decisions are explicit;
- labels support filtering by phase, source, service / domain, component, size, and quality gates;
- risks and non-goals from the source doc are represented;
- postmortem follow-ups link to the incident or root cause;
- the engineer approved priority and scope for cross-team or compliance-sensitive work.

## What to do next

Identify the source (intent / proposal / ADR / incident / review finding), classify the action (plan / refine / handoff / closeout / postmortem follow-up), check repo-local `AGENTS.md` for git and Beads policy, then run the `planning` skill workflow. Report source artifact, beads created or updated (grouped by epic / task / spike / follow-up), dependencies, first ready work, labels applied, remaining decisions, validation runs, and whether execution should start in a fresh agent session.
