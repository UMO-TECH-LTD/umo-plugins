<!-- doc-meta -->
> **Status:** active
> **Type:** reference
> **Owner:** UMO Platform Team
> **Updated:** 2026-05-05

# AGENTS.md Steering

Local `AGENTS.md` files bind company plugin behavior to a repo. They should
steer agents to `umo-sdlc`, not fork its docs, planning, or how-to lifecycle.

## Root AGENTS.md

Root `AGENTS.md` should:

- state that the repo uses `umo-sdlc` for docs lifecycle, task decomposition
  into Beads, SDLC, Spec-Driven Development (SDD), Test-Driven Development
  (TDD) how-to guidance, and repository health diagnostics;
- point agents to `how-to` for setup, explanation, repo navigation, repo
  adaptation, and repair;
- list repo-specific commands, service registry, paths, and exceptions;
- keep Beads command reminders short and defer detailed task decomposition
  behavior to the plugin;
- avoid copying the full task decomposition playbook, label taxonomy, or bead
  templates.

## Service AGENTS.md

Service `AGENTS.md` should:

- identify the service, stack, commands, ownership, dependencies, and sharp
  edges;
- point service-specific docs, task decomposition, and how-to work to `umo-sdlc`;
- avoid redefining company-wide Beads labels, priorities, lifecycle phases, or
  closeout rules.

## Anti-patterns

- Copying entire skill files into `AGENTS.md`.
- Maintaining separate Beads label taxonomies per service.
- Redefining proposal/ADR/incident status semantics locally.
- Contradicting repo-local git/push rules in plugin text.
- Hiding service commands inside plugin references.

## Minimal Root Snippet

Use this pattern, adapted to the repo:

```markdown
## UMO SDLC Plugin

This repo uses `umo-sdlc` for:

- docs lifecycle: managed docs buckets, doc-meta, proposals, ADRs, guides,
  references, incidents, service passports, and service catalogs;
- planning lifecycle: moving intent, research, proposals, incidents, and review
  findings into Beads epics/tasks/spikes with dependencies and closeout
  evidence;
- SDLC how-to workflows: explaining SDLC, Spec-Driven Development (SDD), and
  Test-Driven Development (TDD), navigating repo knowledge, adapting repo
  steering, diagnosing health, and safely healing gaps.

Use local `AGENTS.md` for repo paths, service names, commands, and exceptions.
Do not duplicate the full `umo-sdlc` lifecycle or Beads label taxonomy here.
```
