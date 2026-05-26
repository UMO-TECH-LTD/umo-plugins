<!-- doc-meta -->
> **Status:** active
> **Type:** overview
> **Owner:** UMO Platform Team
> **Updated:** 2026-05-26

# umo-sdlc — How We Work with Agents at UMO

This plugin defines the **standard way** Product Owners and Engineers collaborate with AI agents across all UMO repositories.

It turns the [Agentic-Agile Manifesto](https://github.com/microsoft/agentic-agile-template/blob/main/MANIFESTO.md) into concrete, enforceable workflows.

## The Way We Work (Two Clear Roles)

### 1. Product Owners (PO)
Use the **`product`** skill when you write or refine:
- BRDs (Business Requirements)
- PRDs (Product Requirements)
- Roadmaps
- Product-level backlog items

**What the `product` skill gives you:**
- Structured templates with **governance built-in**:
  - Spec Status Lifecycle (`draft → review → approved`)
  - Requirements Traceability Matrix (RTM)
  - Money / Data Flow & Double-Entry (for regulated/fintech domains)
  - Audit Trail Requirements
  - Regulatory Mapping Table
- A mandatory **Readiness Checklist** before handing work to engineers.

Only documents with `Status: approved` can move to the next phase.

### 2. Engineers
After a PO document reaches `approved` status:
1. Verify the PO artifact.
2. Perform research (Architecture, Specs, Proposals, ADRs, design).
3. Use the **`task`** skill to turn the accepted work into rich, traceable Beads.

**What the `task` skill enforces:**
- Every task must contain a direct link back to the source PRD/BRD section.
- Every task must declare an **Independent Unit Contract** (files touched + explicit non-overlap with other tasks).
- Work is grouped into **waves** so multiple people + agents can work in parallel safely.

This directly implements the manifesto principles of **parallel independence** and **waves, not waterfalls**.

## Strong Alignment with the Agentic-Agile Manifesto

The plugin was deliberately designed around the manifesto's core values:

| Manifesto Value | How We Implement It |
|-----------------|---------------------|
| Specifications and contracts over open-ended prompts | POs produce governed contracts via `product` skill. Agents only consume `approved` specs. |
| Specs are the primary control surface | Status gates (`approved` only) control when work can be decomposed. |
| Decompose into independently executable units | `task` skill **requires** Independent Unit Contract on every task. |
| Parallel independence | Tasks declare non-overlap and wave grouping. |
| Humans design, agents execute, both review | PO designs contract → Engineer researches → Agent decomposes → Human reviews bead tree. |
| Governance is architecture | Status lifecycle, RTM, money flow, audit, and regulatory mapping are mandatory in `product` templates. |
| Shared vocabulary prevents drift | Every bead contains exact section links + contract. |

## Quick Reference — Which Skill to Use

| Situation | Skill / Command |
|-----------|-----------------|
| PO writing or refining BRD/PRD/roadmap | `product` |
| Turning approved spec into Beads | `task` |
| Setting up or auditing docs buckets | `docs` |
| "How do I use this plugin?" or health check | `how-to` |
| Full SDD flow from unclear idea | `sdd` rule |

## Repository Structure

```
plugins/umo-sdlc/
├── rules/            # Cursor rules (sdd.mdc, etc.)
├── skills/           # product, task, docs, how-to (+ references & assets)
├── commands/         # Claude Code slash commands
├── .cursor-plugin/   # Cursor manifest
├── .claude-plugin/   # Claude Code manifest
└── .codex-plugin/    # Codex manifest
```

## Adoption

Repos adopt this plugin through a **thin** `AGENTS.md` that points to these skills. Do not copy the full content locally.

See `skills/how-to/references/agents-steering.md` for the recommended snippet.

---

This is the single source of truth for how UMO teams work with agents. Everything else (local `AGENTS.md`, service docs, etc.) should only add repo-specific context on top of this foundation.