<!-- doc-meta -->
> **Status:** active
> **Type:** reference
> **Owner:** UMO Platform Team
> **Updated:** 2026-05-26

# Current UMO SDLC Skill Map

This reference shows the current division of responsibilities across the four main skills in `umo-sdlc`.

## Skill Responsibilities

| Skill | Primary Audience | Core Responsibility | Key Outputs |
|-------|------------------|---------------------|-------------|
| `product` | Product Owners | Authoring and governing BRDs, PRDs, roadmaps, and product backlogs with status lifecycle, RTM, money flow, audit, and regulatory mapping | High-quality, traceable specification contracts ready for engineering research |
| `task` | Engineers + Agents | Decomposing accepted specs/PRDs/ADRs into rich, traceable Beads epics and tasks with spec references, independent unit contracts, and wave grouping | Executable bead trees (`bd create`, dependencies, labels) |
| `docs` | All | Managed docs buckets, doc-meta, document type boundaries, PASSPORT.md, service.catalog.json, lifecycle rules (proposal/ADR/guide/reference/incident) | Consistent, machine-readable documentation structure |
| `how-to` | All (entry point) | Orientation, repo navigation, SDLC routing, adoption modes, health diagnostics, safe autofixes | Clear workflow selection and repository health reports |

## Handoff Flow

1. **PO** uses `product` skill → produces `approved` BRD/PRD with governance sections.
2. **Engineer** verifies + performs research (Architecture, Specs, Proposals, ADRs).
3. **Engineer / Agent** invokes `task` skill on the approved documents → produces rich Beads.
4. **All** use `docs` skill for bucket structure and document lifecycle.
5. **All** use `how-to` for orientation and health checks.

## Key Principle

Durable context lives in docs (`product` + `docs` skills). Executable work lives in Beads (`task` skill). The `how-to` skill is the router and diagnostic layer.

Do not duplicate full skill logic in local `AGENTS.md` files. Point to the plugin instead.