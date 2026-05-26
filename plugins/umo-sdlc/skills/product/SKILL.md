---
name: product
description: Dedicated workflow, templates, and governance for Product Owners authoring BRDs, PRDs, roadmaps, product backlogs, and capability maps in UMO spec-driven environments. Produces high-quality, traceable specification contracts with status lifecycle, requirements traceability, money-flow definitions, audit requirements, and regulatory mapping. Use when a PO is writing, refining, or governing product intent documents. Engineers use the output for research and `task` skill decomposition.
paths:
  - "**/docs/product/**"
  - "**/docs/product/brds/**"
  - "**/docs/product/prds/**"
  - "**/docs/product/ROADMAP.md"
  - "**/AGENTS.md"
  - "plugins/umo-sdlc/**"
---

# UMO Product Owner Workflow (BRD / PRD / Roadmap / Governance)

This skill is the dedicated surface for Product Owners. It provides ready-to-use templates, a mandatory Readiness checklist, and governance structures (status lifecycle, traceability matrix, money-flow, audit, regulatory mapping) so that every specification is **agent-contract ready** and **compliance-ready** before engineering research begins.

## When to Use

- Writing or refining a BRD, PRD, roadmap item, or product backlog entry.
- Managing the spec status lifecycle (draft → review → approved).
- Adding or updating Requirements Traceability Matrix (RTM) entries.
- Defining money/data flows, audit trail requirements, or regulatory mappings for regulated/fintech products.
- Preparing a specification so that engineers can perform research (Architecture, Specs, Proposals, ADRs) and then invoke the `task` skill for rich Beads decomposition.

## Core Output: The Specification Contract

Every document created or updated with this skill must contain:

1. Clear problem framing, success metrics, and scope/non-goals.
2. Explicit **Spec Status Lifecycle** with current status.
3. **Requirements Traceability Matrix (RTM)** linking acceptance criteria to Beads/tasks/tests.
4. **Money / Data Flow & Double-Entry** walkthrough (mandatory for financial products).
5. **Audit Trail & Immutable Logging** requirements.
6. **Regulatory Mapping Table** (specific regulations → acceptance criteria or backlog items).
7. Acceptance criteria written as observable conditions.
8. Traceability to parent BRD, related PRDs, ADRs, Jira, Confluence, Figma.
9. Readiness for Beads Planning checklist (updated with new governance areas).

## Spec Status Lifecycle (Mandatory Governance)

Every managed product document carries a status in its doc-meta and a `## Status Lifecycle` section.

| Status | Meaning | Who Can Transition | Next Possible |
|--------|---------|--------------------|---------------|
| draft | PO is still authoring; visible but not for implementation | PO | review |
| review | PO requests cross-functional feedback (engineering, compliance, legal) | PO + reviewers | approved, draft |
| approved | Ready for engineering research and `task` skill decomposition | PO + Eng Lead | in-development |
| in-development | Engineers own implementation; PO does not change spec without new status | Eng | under-test |
| under-test | Implementation returned to PO for intent verification | PO | released, in-development |
| released | Done; spec becomes permanent record | PO | (archived on major change) |

**Rule**: Only `approved` specs may be handed to the `task` skill. Status is the single source of truth for the handoff gate.

## Requirements Traceability Matrix (Lightweight RTM)

Every PRD/BRD includes a `## Requirements Traceability Matrix` section (or references an external `rtm.md` for large features).

Minimal columns:
- Req ID (e.g. FR-03, NFR-07)
- Acceptance Criterion (short, observable)
- Source Section (link)
- Beads / Tasks (after `task` skill run)
- Tests / Verification
- Implementation Location
- Status

This enables instant impact analysis when requirements change.

## Money / Data Flow & Double-Entry (Regulated / Fintech Domains)

For any product that moves, holds, or reconciles value, add a mandatory `## Money Flow & Double-Entry` section.

Content requirements:
- Happy path diagram (Mermaid or link) showing every debit/credit.
- Failure and reversal paths.
- Explicit account types (user funds, operational, settlement, revenue, cold storage).
- Reconciliation checkpoints.
- Failure to balance = spec is incomplete.

This section is reviewed by Finance/Treasury before `approved` status.

## Audit Trail & Immutable Logging Requirements

Add a dedicated `## Audit & Logging` section that defines:

- Events that must be logged (every money movement, status change, KYC decision, etc.).
- Required fields: timestamp, actor (user/system), action, amount, currency, source, destination, status, unique tx ID.
- Immutability guarantee (append-only, tamper-evident).
- Retention period (minimum 5–7 years).
- Compliance reporting formats.

## Regulatory Mapping Table

Expand the existing regulatory section into a structured table:

| Regulation / Article | Requirement | Acceptance Criterion or Backlog Item | Owner | Status |
|----------------------|-------------|--------------------------------------|-------|--------|
| FATF Rec 16 / IVMS101 | Travel rule address registration | ... | Compliance | ... |
| MiCA Art. 14(1)(d) | System security protocols | ... | Security | ... |

This table is the contract between Product and Compliance/Legal.

## Recommended Document Types and Locations

| Type | Location | Purpose |
|------|----------|---------|
| BRD | `docs/product/brds/NNN-slug.md` | Business requirements, stakeholder alignment, regulatory context |
| PRD | `docs/product/prds/NNN-slug.md` | Product requirements with acceptance criteria, flows, RTM, audit, regulatory mapping |
| Roadmap | `docs/product/ROADMAP.md` | Short priority list with links + status |
| Product backlog | `docs/product/backlog.md` | Deferred product-level ideas not yet turned into BRDs/PRDs (PO-owned). Service/engineering backlogs live in `services/<svc>/docs/backlog.md`. |

## Readiness for Beads Planning Checklist (Mandatory before engineering research)

Before an engineer starts research and invokes the `task` skill, verify:

- [ ] Spec status is `approved`.
- [ ] Every acceptance criterion is observable and testable.
- [ ] Scope and non-goals are explicit.
- [ ] Key sections have stable anchors.
- [ ] Traceability matrix (RTM) exists and links are valid.
- [ ] Money / data flow section balances (debits = credits) and covers reversals.
- [ ] Audit trail requirements are defined (fields, immutability, retention).
- [ ] Regulatory mapping table is complete and reviewed by compliance.
- [ ] Risks, open decisions, and edge cases are listed.
- [ ] Diagrams are embedded or linked with access notes.
- [ ] The document is marked `accepted` (or `active` for roadmap/product-backlog).

## Daily PO Flow

1. Open or create the BRD/PRD/roadmap/product-backlog item using the templates in `assets/`.
2. Set initial status to `draft`.
3. Fill all required governance sections (status, RTM, money flow, audit, regulatory mapping).
4. Move to `review` when ready for feedback.
5. After cross-functional approval, set status to `approved` and hand to engineering.
6. Engineers verify + research → invoke `task` skill.

The `product` skill focuses on producing high-quality, governed specification contracts. The actual Beads decomposition (`task` skill) is performed by engineers after the research and planning phase.

## Integration with `task` Skill

The `product` skill produces the **input contract** (with status, RTM, flows, audit, regulatory mapping). Engineers perform research and invoke the `task` skill, which consumes the `approved` documents and produces the **execution graph** (rich, traceable Beads with spec references, independent unit contracts, and wave grouping).

## Guardrails

- Never move a spec to `approved` without completing the Readiness checklist.
- Never skip the money-flow or audit sections for financial products.
- Do not change an `approved` spec without creating a new version or status transition.
- Keep Confluence/Jira as the collaboration surface when required; the spec repo holds the canonical managed copy for delivery and agent consumption.

## Output

After using this skill, report:
- Documents created or updated.
- Status transitions performed.
- Readiness checklist status.
- Whether the document is now ready for engineering research and the `task` skill.
- Any open human decisions or compliance reviews still required.