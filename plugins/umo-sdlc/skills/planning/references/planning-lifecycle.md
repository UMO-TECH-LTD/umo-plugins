<!-- doc-meta -->
> **Status:** active
> **Type:** reference
> **Owner:** UMO Platform Team
> **Updated:** 2026-05-05

# Planning Lifecycle

UMO Planning turns intent into reviewed, dependency-aware Beads work. Planning
sits between "we think we need something" and "agents can safely build it."

## Inputs

Planning can start from:

- user intent;
- research memo;
- accepted or draft proposal;
- ADR needing implementation;
- service spec/backlog;
- incident or postmortem;
- code-review finding;
- implementation discovery.

## Phase Flow

1. **Intake:** restate outcome, source, constraints, owner, urgency, and known
   unknowns.
2. **Clarify:** ask only for decisions that block useful planning.
3. **Research/proposal:** keep large context in managed docs when uncertainty
   is high.
4. **Readiness:** confirm scope, non-goals, acceptance criteria, dependencies,
   risk, and decision points.
5. **Bead tree:** create or propose epics, tasks, subtasks, spikes, and
   follow-ups.
6. **Human review:** ask the engineer to approve scope, priority, and risky
   dependencies.
7. **Execution handoff:** recommend a fresh implementation session on the epic
   or next ready bead.
8. **In-flight hygiene:** claim work, comment decisions, file discovered work,
   and keep blockers explicit.
9. **Closeout:** close completed beads with evidence-rich reasons.
10. **Postmortem loop:** create durable incident docs and linked corrective
    action beads for incidents or failed plans.

## Transition Prompts

Use these prompts when lifecycle state changes:

- Research complete: "This is ready for Beads planning. I can create a
  reviewed epic and child tasks."
- Proposal accepted: "The proposal is accepted. Next step is to file the
  implementation bead tree and confirm priorities/dependencies."
- Proposal rejected: "I can record the rejection and file only cleanup or
  communication follow-ups."
- Postmortem complete: "I can file follow-up beads for each corrective action
  and link them to the incident."
- Discovered work: "I found related work. I will file it as `discovered-from`
  unless you want it handled now."

## Human Approval Required

Ask before proceeding when planning affects:

- product priority;
- architecture commitments;
- compliance or security scope;
- production operations;
- cross-team ownership;
- large bead trees from research-only requests;
- enforcement mode or repo policy.

## Ready For Build

Planning is ready for build when:

- the first `bd ready` work is intentional;
- all implementation tasks have acceptance criteria and verification;
- all learning work is represented as spikes;
- all human decisions are explicit `decision` beads;
- all follow-ups have source/provenance links;
- repo-local git/sync rules are understood.

