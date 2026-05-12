---
description: Route Spec-Driven Development — turn unclear intent into durable docs, Beads planning, test-first implementation, and evidence closeout.
argument-hint: "[task or topic]"
---

# Spec-Driven Development

User intent: $ARGUMENTS

Run the UMO SDD workflow. SDD is the umbrella discipline that connects intent → docs → planning → implementation → closeout.

## Phases

1. **Intent.** Clarify outcome, constraints, risks, non-goals, and unknowns. Ask the user before guessing.
2. **Durable specification.** Use the `docs` skill (or `/umo-sdlc:docs`) to create or update the right artifact:
   - `spec.md` for active service acceptance criteria
   - `proposals/<slug>.md` for options under review
   - `adr/NNN-<slug>.md` for durable accepted decisions
   - `incidents/YYYY-MM-DD-<slug>.md` for postmortems and follow-ups
   - `guides/` or `reference/` for steps or source-tied facts
3. **Planning.** Use the `planning` skill (or `/umo-sdlc:planning`) to turn accepted specs, proposals, ADRs, incidents, or review findings into Beads epics, tasks, spikes, `decision` beads, dependencies, labels, and closeout expectations.
4. **Test-Driven Development.** When implementation is ready and testable, write a focused failing test or explicit test case before the smallest useful implementation change. Use repo-local language/test rules for stack-specific guidance.
5. **Evidence closeout.** Close Beads with evidence, run repo quality gates, and update docs when behavior, service facts, config, dependencies, or operations changed.

## Routing rules

- Need a spec / proposal / ADR / incident / reference? → invoke the `docs` skill.
- Need a Beads tree or execution handoff? → invoke the `planning` skill.
- Need repo navigation, adoption, or health diagnostics? → invoke the `how-to` skill.
- Need stack-specific tests or quality commands? → use repo-local steering (`AGENTS.md`) and language plugin guidance.

## Guardrails

- Do not skip docs when requirements, architecture, or operational behavior are unclear.
- Do not skip Beads when accepted work needs execution across sessions or agents.
- Do not encode long-form specs inside Beads descriptions.
- Do not let this generic SDD routing override repo-local git, test, deploy, or language rules.

## What to do next

Pick the phase the user is in, name it explicitly, and invoke the matching skill or command. If the phase is ambiguous, ask one targeted question rather than guessing.
