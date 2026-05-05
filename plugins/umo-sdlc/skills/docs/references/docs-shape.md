<!-- doc-meta -->
> **Status:** active
> **Type:** reference
> **Owner:** UMO Platform Team
> **Updated:** 2026-05-04

# UMO SDLC Docs Shape Reference

This reference is the detailed source for UMO managed documentation shapes.
Rules and skills should stay concise and point here when a full template is
needed.

## Source

`plugins/umo-sdlc/rules/docs.mdc` and
`plugins/umo-sdlc/skills/docs/SKILL.md` use this reference.

## Core Model

UMO docs are bounded memory buckets:

- **Service bucket:** `services/<svc>/docs/`
- **Root library bucket:** `docs/`
- **Domain library bucket:** `<repo-root>/docs/`

Service buckets are spec-driven and have a Markdown-first `PASSPORT.md`.
Library buckets are knowledge stores and must not contain `PASSPORT.md`,
`spec.md`, or `backlog.md`.

Buckets may add indexed category folders when a domain has enough docs to
benefit from local grouping, for example `docs/infrastructure/nats/`. Category
folders do not change lifecycle semantics: every managed Markdown file still
uses doc-meta and its `Type` still means the same thing.

## Required Layout

```text
<bucket>/
├── README.md
├── PASSPORT.md               # service only
├── ROADMAP.md                # optional
├── spec.md                   # service only
├── backlog.md                # service only
├── adr/
├── proposals/
├── guides/
├── reference/
│   └── service.catalog.json  # service sidecar when repo requires cataloging
├── incidents/
└── archive/
    ├── proposals/
    ├── guides/
    └── reference/
└── <category>/                # optional, e.g. infrastructure/nats/
    ├── README.md              # required local index
    └── ...
```

## Category Folders

Use category folders when a subject would otherwise spread too many files
across top-level `guides/` and `reference/`.

Rules:

- Category folder must have `README.md` with `Type: overview`.
- Root bucket `README.md` must link to the category.
- Category docs keep normal doc-meta and lifecycle semantics.
- Category docs may be guides, references, ADRs, incidents, etc., but the
  category should explain how it is organized.
- Do not create category folders just to hide unclassified docs.

## Managed Markdown Header

Every managed Markdown document starts with doc-meta:

```markdown
<!-- doc-meta -->
> **Status:** draft | active | accepted | rejected | implemented | superseded | archived
> **Type:** overview | passport | roadmap | spec | backlog | proposal | adr | guide | reference | incident
> **Owner:** <gitlab handle or team>
> **Updated:** YYYY-MM-DD
```

Status semantics:

- `draft`: proposal is under consideration.
- `accepted`: proposal or ADR is approved as direction/decision.
- `rejected`: proposal was reviewed and explicitly not chosen.
- `implemented`: accepted proposal has shipped; historical record remains.
- `active`: living doc such as guide, reference, passport, spec, backlog, incident.
- `superseded`: ADR replaced by a newer ADR.
- `archived`: retired proposal, guide, or reference.

Use **accepted/rejected** for proposal state. Avoid `decided` as a status:
deciding is an event/date, not a lifecycle state.

## Type Decision Table

| Type | Use When | Typical Status | Location |
|------|----------|----------------|----------|
| overview | Bucket index and navigation | active | `README.md` |
| passport | First service entrypoint for humans and agents | active | `PASSPORT.md` |
| proposal | Direction is under review or accepted/rejected | draft, accepted, rejected, implemented, archived | `proposals/` |
| adr | Durable accepted decision | accepted, superseded | `adr/NNN-slug.md` |
| guide | Living runbook/how-to | active, archived | `guides/` |
| reference | Contract/schema/API/env facts tied to source | active, archived | `reference/` |
| incident | Postmortem and follow-ups | active, archived | `incidents/YYYY-MM-DD-slug.md` |
| spec | In-flight acceptance criteria | active | `spec.md` |
| backlog | Future/deferred work | active | `backlog.md` |
| roadmap | Short priority ordering | active | `ROADMAP.md` |

## Promotion Rules

- Proposal accepted? Keep it as `Type: proposal`, set `Status: accepted`,
  add `Decided: YYYY-MM-DD`, and add an ADR only if the decision should
  become a durable architectural/operational record.
- Proposal rejected? Keep it as `Type: proposal`, set `Status: rejected`,
  add `Decided: YYYY-MM-DD` and a short reason.
- Proposal shipped? Set `Status: implemented` and link the implementation
  evidence or spec item.
- Guide contains alternatives, trade-offs, or "we decided"? Extract the
  decision to ADR and keep operational steps in the guide.
- Reference contains opinions or recommendations? Split factual contract into
  reference and move the decision/trade-off to proposal or ADR.
- Backlog item is being worked? Promote to concrete `spec.md` AC and leave a
  trace in `backlog.md`.

## Templates

### README.md

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** overview
> **Owner:** <team or handle>
> **Updated:** YYYY-MM-DD

# <Bucket or Service Name>

One paragraph describing what this bucket holds.

## Quick links

| Topic | Entry |
|-------|-------|
| Service passport | [`PASSPORT.md`](./PASSPORT.md) |
| Machine catalog | [`reference/service.catalog.json`](./reference/service.catalog.json) |
| In-flight work | [`spec.md`](./spec.md) |
| Backlog | [`backlog.md`](./backlog.md) |
| Proposals | [`proposals/`](./proposals/) |
| Decisions | [`adr/`](./adr/) |
| Guides | [`guides/`](./guides/) |
| Reference | [`reference/`](./reference/) |
| Incidents | [`incidents/`](./incidents/) |
| Archive | [`archive/`](./archive/) |
```

### PASSPORT.md

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** passport
> **Owner:** <team or handle>
> **Updated:** YYYY-MM-DD

# <Service Name> Passport

One paragraph: what this service is and why it exists.

## Purpose

This passport is the first service document for humans and AI agents.

## Service Identity

| Field | Value |
|-------|-------|
| Service | `<svc-name>` |
| Domain | `<domain>` |
| Lifecycle | `production` |
| Type | `<gateway | api | worker | frontend | library>` |
| Owner | `<team or handle>` |
| Runtime | `<language / framework>` |
| Namespace | `<namespace>` |

## What It Provides

| Interface | Type | Consumers | Source |
|-----------|------|-----------|--------|

## What It Depends On

| Service | Protocol | Required | Why |
|---------|----------|----------|-----|

## How To Work On It

| Task | Start Here |
|------|------------|

## Agent Read-Next

1. [`../AGENTS.md`](../AGENTS.md)
2. [`reference/service.catalog.json`](./reference/service.catalog.json)

## Sharp Edges

- <thing that breaks easily>

## Operational Notes

- Common env vars live in repo common config docs.

## See Also

- [`README.md`](./README.md)
- [`spec.md`](./spec.md)
- [`backlog.md`](./backlog.md)
- [`guides/`](./guides/)
- [`reference/`](./reference/)
```

### reference/service.catalog.json

```json
{
  "$schema": "https://umo.dev/schemas/service-catalog.v1.json",
  "schema": "umo.service-catalog/v1",
  "kind": "ServiceCatalog",
  "metadata": {
    "name": "<svc-name>",
    "title": "<Service Name>",
    "description": "<one sentence>",
    "domain": "<domain>",
    "lifecycle": "production",
    "type": "<gateway|api|worker|frontend|library>",
    "tags": []
  },
  "ownership": { "team": "<team>", "lead": "<handle>" },
  "runtime": { "language": "<language>", "framework": "<framework>", "entrypoints": [] },
  "deployment": { "namespace": "<namespace>", "clusters": [], "ports": [] },
  "interfaces": { "provides": [], "consumes": [] },
  "operations": { "healthcheck": null, "runbook": null, "dashboards": [], "alerts": [] },
  "agent": { "readNext": [], "sharpEdges": [] }
}
```

### Proposal

```markdown
<!-- doc-meta -->
> **Status:** draft
> **Type:** proposal
> **Owner:** <team or handle>
> **Updated:** YYYY-MM-DD
> **Decided:** <YYYY-MM-DD or blank>
> **ADR:** <../adr/NNN-slug.md or blank>

# Proposal: <Title>

## Summary

One paragraph: problem and proposed direction.

## Problem

What is wrong today, with concrete examples and impact.

## Goals

- ...

## Non-goals

- ...

## Options Considered

### Option A - <name>

Pros / cons.

### Option B - <name>

Pros / cons.

## Decision

Blank while draft. Once reviewed, record accepted/rejected direction and
link ADR only if a durable decision record is needed.

## Risks

- ...

## Success Criteria

- ...
```

### ADR

```markdown
<!-- doc-meta -->
> **Status:** accepted
> **Type:** adr
> **Owner:** <team or handle>
> **Updated:** YYYY-MM-DD
> **Supersedes:** <ADR-NNN or blank>

# ADR-<NNN>: <Title>

## Context

What forces are at play. Link proposal if one existed.

## Decision

The decision in one short paragraph.

## Consequences

What becomes easier, harder, constrained, or newly required.

## Alternatives Considered

Brief summary; full trade-offs can live in a proposal.
```

### Guide

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** guide
> **Owner:** <team or handle>
> **Updated:** YYYY-MM-DD

# Guide: <Title>

## When to use

Symptom or trigger.

## Prerequisites

Tools, access, environment variables.

## Steps

1. ...
2. ...

## Rollback / Safety Net

How to undo or stop safely.

## Related

- ADR, proposal, dashboard, alert, runbook.
```

### Reference

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** reference
> **Owner:** <team or handle>
> **Updated:** YYYY-MM-DD

# Reference: <Title>

## Source

`<path/to/source>` - this doc mirrors that source.

## Contract

Schema, fields, semantics, error codes, compatibility notes.

## Examples

Request/response/event payload examples.

## Related

- Consumers, ADRs, guides.
```

### Incident

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** incident
> **Owner:** <team or handle>
> **Updated:** YYYY-MM-DD

# Incident: <Title>

## Timeline

- HH:MM UTC - <event>

## Impact

Who was affected, for how long, and what data/transactions were involved.

## Root Cause

One paragraph.

## Detection

How it was noticed.

## Mitigation

What restored service.

## Lessons

- ...

## Follow-ups

- [ ] pending: <action item>
```

### spec.md

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** spec
> **Owner:** <team or handle>
> **Updated:** YYYY-MM-DD

# <Service Name> - Spec

## Acceptance criteria

- [ ] pending: <criterion>
- [x] done: <criterion>
```

### backlog.md

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** backlog
> **Owner:** <team or handle>
> **Updated:** YYYY-MM-DD

# <Service Name> - Backlog

## Up next

- <item>

## Later

- <item>

## Considered, not doing

- <item> - <reason>
```

### ROADMAP.md

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** roadmap
> **Owner:** <team or handle>
> **Updated:** YYYY-MM-DD

# <Bucket Name> - Roadmap

## In flight

- <one-liner linking spec/proposal/backlog>

## Up next

- <one-liner>

## After that

- <one-liner>
```

## Validation Checklist

- File location matches `Type`.
- Filename matches location convention.
- Managed Markdown starts with doc-meta.
- `PASSPORT.md` has no YAML frontmatter.
- Proposal status is not `decided`; use `accepted` or `rejected`.
- ADR body is not edited after acceptance.
- Guide focuses on steps; ADR holds decisions.
- Reference names source files.
- JSON sidecars parse.
