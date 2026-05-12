---
description: UMO SDLC how-to entry point — repo navigation, SDD/TDD orientation, plugin adoption, and repository health diagnostics. Use when the user asks how to use umo-sdlc, where to find repo facts, how to plan or execute work, how to apply SDD/TDD, or how to diagnose and repair repo steering.
argument-hint: "[question or repo path]"
---

# UMO SDLC How-To

Request: $ARGUMENTS

Invoke the `how-to` skill (`plugins/umo-sdlc/skills/how-to/SKILL.md`) for adoption checks, SaaS navigation, repository health diagnostics, safe autofixes, and report shape. Use this command as the friendly front door for humans and agents working with umo-sdlc.

## When to use

Use this when a user asks:

- "How do I use this plugin in this repo?"
- "Where are docs, issues, dependencies, service facts, or decisions?"
- "How should agents work in the SaaS repo?"
- "Help me follow SDLC, SDD, or TDD for this work."
- "Set up / adapt this repo for umo-sdlc."
- "Diagnose / heal / check our docs, planning, Beads, or agent steering."
- "Why is the agent not following the SDLC plugin?"

## Route the work

1. Explain and orient with this command when the question is broad, procedural, or about where to find information.
2. Use `/umo-sdlc:docs` for docs bucket setup, audit, lifecycle, passports, catalog sidecars, proposals, ADRs, guides, references, incidents, specs, and backlogs.
3. Use `/umo-sdlc:planning` for Beads epics / tasks / spikes, dependencies, labels, comments, readiness, execution handoff, and closeout.
4. Use repo-local instructions (`AGENTS.md`, `CLAUDE.md`) for commands, service names, paths, deployment topology, git policy, and exceptions.
5. Use `/umo-sdlc:sdd` when the user asks for Spec-Driven Development or needs a disciplined path from unclear intent to docs, planning, test-first implementation, and evidence closeout.

## SaaS repo navigation

For the SaaS monorepo, gather context in this order:

1. Root `AGENTS.md` for service registry, repo conventions, git policy, and global commands.
2. `services/<service>/AGENTS.md` for service stack, architecture, commands, dependencies, and sharp edges.
3. `services/<service>/PASSPORT.md` or `services/<service>/docs/PASSPORT.md` for service ownership, runtime facts, deployment, env vars, and dependencies.
4. `docs/reference/common-config.md` before duplicating shared env vars.
5. `docs/proposals/`, `docs/adr/`, `docs/guides/`, `docs/reference/`, `docs/incidents/` for durable decisions and operational memory.
6. Beads with `bd ready --json`, `bd show <id> --json`, `bd dep tree <id>` when executable work or status is in scope.
7. Source-of-truth dependency files: `go.mod`, `package.json`, `docker-compose.yaml`, `deploy/service.yaml`, proto folders, generated client config, imports, and service-specific docs.

When searching, prefer exact names with ripgrep / file globs first, then semantic search for broad questions.

## Safe autofixes

May apply without additional approval when the user asked to heal or adapt the repo:

- add or refresh a short `AGENTS.md` plugin pointer;
- add missing `.gitkeep` files in expected docs folders;
- add obvious doc-meta to five or fewer managed docs;
- add a short Beads onboarding pointer when Beads exists in the repo;
- fix typos in plugin names or skill names.

## Approval required

Ask before:

- bulk editing `AGENTS.md` across services;
- moving or renaming docs;
- changing proposal / ADR status;
- initializing Beads in a repo;
- changing enforcement mode;
- modifying plugin manifests;
- deleting or replacing local rules.

## What to do next

Identify what the user is actually asking (orientation / setup / audit / planning / diagnosis), name the recommended workflow, list the files or commands to inspect, and point at the next skill or command. For health checks, produce a concise report covering adoption mode, active steering files, plugin pointers, docs readiness, planning / Beads readiness, SaaS navigation traceability, conflicting or duplicated local guidance, safe autofixes applied, proposed manual fixes, and the next recommended workflow.
