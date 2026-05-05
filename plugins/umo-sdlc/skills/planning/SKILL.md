---
name: planning
description: Turns UMO Agentic SDLC intent, research, proposals, incidents, postmortems, and review findings into reviewed Beads issue graphs. Use when planning work, creating epics/tasks/spikes, defining dependencies/labels/comments, checking planning readiness, or handing execution to agents.
paths:
  - "**/AGENTS.md"
  - "**/docs/proposals/**"
  - "**/docs/incidents/**"
  - "**/docs/spec.md"
  - "**/docs/backlog.md"
  - "plugins/umo-sdlc/**"
---

# UMO Planning

Use this skill when moving from intent or durable docs into executable Beads
work. It owns Planning SDLC behavior inside `umo-sdlc`.

Load these references when needed:

- `references/planning-lifecycle.md` for phase transitions and readiness.
- `references/beads-issue-shape.md` for epic/task/spike/follow-up shapes.
- `references/beads-label-taxonomy.md` for labels and filtering conventions.

Use files under `assets/` as issue-description templates.

## First Steps

1. Identify the source:
   - user intent;
   - research memo;
   - proposal;
   - ADR;
   - spec/backlog;
   - incident or postmortem;
   - review finding;
   - discovered implementation work.
2. Classify the action:
   - **plan**: create/propose a bead tree;
   - **refine**: improve existing beads, labels, dependencies, or comments;
   - **handoff**: prepare execution instructions from an epic or ready task;
   - **closeout**: close or defer work with evidence;
   - **postmortem follow-up**: file corrective actions from an incident.
3. Check repo-local policy in `AGENTS.md` before running Beads commands. Repo
   policy controls git, sync, commit, and push behavior.
4. Prefer Beads JSON output for agent-readable workflows.

## Core Rules

- Planning belongs in `umo-sdlc`; do not create or invoke a separate planning
  plugin.
- Docs hold durable context. Beads hold executable work.
- Do not silently create a large bead tree when the user asked only for
  research. Offer the transition and ask for approval unless issue creation was
  requested.
- Ask the engineer to approve priority, scope, risky dependencies, compliance
  sensitivity, and cross-team commitments.
- Keep tasks small enough for focused agent sessions.
- Use spikes for learning, not implementation.
- Use `discovered-from` for work found during other work.
- Use comments for decisions, evidence, scope changes, and blockers. Do not
  paste chat transcripts into comments.
- Close beads with evidence-rich reasons.

## Lifecycle

When research, a proposal, a design review, or a postmortem is finalized, say:

> This is ready to plan. I can turn it into a reviewed Beads epic with child
> tasks, dependencies, labels, acceptance criteria, and open decision points.

After the user approves, create or propose the bead tree:

1. Epic for the outcome.
2. Child tasks for executable units.
3. Spikes for unresolved learning.
4. Decision beads for human approval.
5. Dependencies so `bd ready` exposes the intended first work.
6. Labels for phase/source/service/component/quality gates.
7. Comments for decisions and evidence.

## Commands

Typical agent-readable commands:

```bash
bd ready --json
bd show <id> --json
bd create --title="..." --description="..." --type=task --priority=2 --json
bd update <id> --claim --json
bd close <id> --reason="Completed: ..." --json
```

For a proposal/spec handoff:

```bash
bd create --title="<proposal outcome>" --description="<summary, source link, acceptance criteria>" --type=epic --priority=2 --json
bd create --title="<child task>" --description="<specific outcome and verification>" --type=task --priority=2 --parent <epic-id> --json
bd dep add <blocked-task> <blocking-task>
bd dep tree <epic-id>
```

## Readiness

A bead tree is ready for execution when:

- every epic has a clear outcome and source;
- every child task has acceptance criteria and verification;
- dependencies are explicit and `bd ready` shows the intended first work;
- spikes are separate from implementation tasks;
- human decisions are explicit;
- labels support filtering by phase, source, service/domain, component, size,
  and quality gates;
- risks and non-goals from the source doc are represented;
- postmortem follow-ups link to the incident or root cause;
- the engineer approved priority and scope for cross-team or
  compliance-sensitive work.

## Output

After planning work, report:

- source artifact or intent used;
- beads created/updated, grouped by epic/task/spike/follow-up;
- dependencies and first ready work;
- labels applied;
- decisions still needed;
- validation run, such as `bd dep tree`, `bd ready`, or `bd show`;
- whether execution should start in a fresh agent session.

