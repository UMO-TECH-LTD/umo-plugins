---
name: how-to
description: Entry point and router for UMO SDLC. Explains plugin capabilities, routes work to the right skill (`docs`, `product`, `task`), provides repo navigation, adoption guidance, and health diagnostics. Use for orientation, "how do I use this plugin?", or repository health checks.
paths:
  - "**/AGENTS.md"
  - "plugins/umo-sdlc/**"
---

# UMO SDLC How-To

Use this skill as the friendly front door for humans and agents working with
`umo-sdlc`. It explains what the plugin offers, picks the right workflow, shows
where repo knowledge lives, and preserves repository health diagnostics.

**Important:** When using this skill, always load and follow:
- `references/repo-adoption.md` (adoption modes, health diagnostics, rollout order)
- `references/agents-steering.md` (recommended AGENTS.md snippets and anti-patterns)
- `references/current-skill-map.md` (current responsibility matrix)
- `assets/agents-snippet.template.md` (minimal root steering snippet)

These files are part of the skill context and must be consulted.

## When To Use

Use when a user asks:

- "How do I use this plugin in this repo?"
- "Where are docs, issues, dependencies, service facts, or decisions?"
- "How should agents work in this repo?"
- "Help me follow SDLC, SDD, or TDD for this work."
- "Set up/adapt this repo for `umo-sdlc`."
- "Diagnose/heal/check our docs, Beads, or agent steering."
- "Why is the agent not following the SDLC plugin?"

## Route The Work

1. Explain and orient with this skill when the question is broad, procedural, or
   about where to find information.
2. Use `docs` for docs bucket setup, audit, lifecycle, passports, catalog
   sidecars, proposals, ADRs, guides, references, incidents, specs, and backlogs.
3. Use `task` for rich, spec-traceable Beads decomposition with independent
   unit contracts and wave grouping.
4. Use `product` when a Product Owner is authoring or refining BRDs, PRDs,
   roadmaps, or product backlogs.
5. Use repo-local instructions for commands, service names, paths, deployment
   topology, git policy, and exceptions.
6. For future plugin capabilities, route to the most specific skill or rule
   once it exists; keep this skill as the index, not a duplicate manual.
7. Use `rules/sdd.mdc` as the lightweight router when the user asks for
   Spec-Driven Development or needs a disciplined path from unclear intent to
   docs, Beads task decomposition, test-first implementation, and evidence closeout.

## Multi-Service Monorepo Navigation

For a large multi-service monorepo, gather context in this order:

1. Root `AGENTS.md` for service registry, repo conventions, git policy, and
   global commands.
2. `services/<service>/AGENTS.md` for service stack, architecture, commands,
   dependencies, and sharp edges.
3. `services/<service>/PASSPORT.md` or `services/<service>/docs/PASSPORT.md`
   for service ownership, runtime facts, deployment, env vars, and dependencies.
4. `docs/reference/common-config.md` before duplicating shared env vars.
5. `docs/proposals/`, `docs/adr/`, `docs/guides/`, `docs/reference/`, and
   `docs/incidents/` for durable decisions and operational memory.
6. Beads with `bd ready --json`, `bd show <id> --json`, and `bd dep tree <id>`
   when executable work or status is in scope.
7. Source-of-truth dependency files: `go.mod`, `package.json`,
   `docker-compose.yaml`, `deploy/service.yaml`, proto folders, generated
   client config, imports, and service-specific docs.

When searching, prefer exact names with `rg`/file globs first, then semantic
search for broad questions like "where is compliance handled?" or "how does
this service call rates?".

## SDLC / SDD / TDD

- SDLC: keep intent, design, implementation, verification, and closeout
  connected. Durable context lives in docs; executable work lives in Beads.
- Spec-Driven Development (SDD): when behavior or architecture is unclear,
  write or update a spec, proposal, or ADR before implementation. Capture
  options, non-goals, risks, acceptance criteria, and decision points.
- Test-Driven Development (TDD): when implementation is ready and testable,
  start with a focused failing test or explicit test case, implement the
  smallest useful change, then run the relevant quality gate.
- Handoff to Beads: Product Owners produce BRDs, PRDs, roadmaps, and priority.
  Engineers then verify the PO artifacts, perform research (Architecture, Specs,
  Proposals, ADRs, software design), and invoke the `task` skill to decompose the
  accepted work into rich, traceable Beads with spec references, independent
  unit contracts, and wave grouping.
- Closeout: record evidence in Beads and update docs when implementation changes
  durable behavior, service facts, config, dependencies, or operations.

For the concise routing rule, use `plugins/umo-sdlc/rules/sdd.mdc`.

## Repository Health Diagnostics

Run diagnostics in observe mode by default. Check:

- root `AGENTS.md` points to `umo-sdlc` for docs lifecycle, task decomposition
  into Beads, how-to guidance, and repo health diagnostics;
- service `AGENTS.md` files are repo/service bindings, not copies of the full
  SDLC lifecycle;
- managed docs buckets have required structure and doc-meta;
- proposals, ADRs, guides, references, incidents, specs, and backlogs use the
  right document type boundaries;
- Beads task decomposition guidance is not duplicated locally;
- Beads is initialized and usable when the repo claims Beads usage;
- existing bead labels and descriptions do not conflict with UMO conventions;
- repo-local git/sync/push rules are explicit and not overridden by plugin text;
- service facts can be traced from registry to AGENTS, passport, docs,
  config, and dependency files.

## Safe Autofixes

You may apply these without additional approval when the user asked to heal or
adapt the repo:

- add or refresh a short `AGENTS.md` plugin pointer;
- add missing `.gitkeep` files in expected docs folders;
- add obvious doc-meta to five or fewer managed docs;
- add a short Beads onboarding pointer when Beads exists in the repo;
- fix typos in plugin names or skill names.

## Approval Required

Ask before:

- bulk editing `AGENTS.md` across services;
- moving or renaming docs;
- changing proposal/ADR status;
- initializing Beads in a repo;
- changing enforcement mode;
- modifying plugin manifests;
- deleting or replacing local rules.

## Output

For how-to requests, answer with:

- the recommended workflow;
- the files or commands to inspect;
- the skill to use next, if any;
- any human decision point before edits or issue creation.

For health checks, produce a concise report:

- adoption mode;
- active steering files checked;
- plugin pointers found/missing;
- docs readiness;
- task / Beads readiness;
- product document governance (status lifecycle, RTM, money flow, audit, regulatory mapping) when applicable;
- service navigation/dependency traceability, when relevant;
- conflicting or duplicated local guidance;
- safe autofixes applied;
- proposed manual fixes;
- next recommended workflow.
