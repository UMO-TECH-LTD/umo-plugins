---
name: docs
description: Creates, audits, repairs, and maintains UMO docs buckets. Use whenever working with documentation, docs/, services/*/docs/, PASSPORT.md, service.catalog.json, README.md, spec.md, backlog.md, ROADMAP.md, proposals, ADRs, guides, references, incidents, docs lifecycle, doc-meta, or the umo-sdlc plugin rules/skills.
paths:
  - "**/docs/**"
  - "services/*/AGENTS.md"
  - "plugins/umo-sdlc/**"
  - ".cursor/agents/**"
---

# UMO Docs

Use this skill for all managed docs work. It consolidates setup, audit, and
lifecycle actions for UMO SDLC documentation.

Load `references/docs-shape.md` when you need exact templates, required
sections, status semantics, or validation details. Use files under `assets/`
for machine-readable templates/schemas.

## First Steps

1. Identify the docs bucket:
   - service: `services/<svc>/docs/`
   - root library: `docs/`
   - domain library: `<repo-root>/docs/`
2. Detect the action:
   - **setup**: bucket missing;
   - **audit**: validate/repair existing structure;
   - **lifecycle**: create/promote/archive/update a managed doc.
3. For service work, read in order:
   - `services/<svc>/docs/PASSPORT.md`
   - `services/<svc>/docs/reference/service.catalog.json` if present
   - `services/<svc>/AGENTS.md` if present
4. Before edits, classify docs by type: proposal, ADR, guide, reference,
   incident, spec, backlog, roadmap, passport, overview.

## Core Rules

- `PASSPORT.md` is Markdown-first; never add YAML frontmatter.
- Machine-readable service facts live in `reference/service.catalog.json`.
- Managed Markdown starts with doc-meta.
- Proposal statuses are `draft`, `accepted`, `rejected`, `implemented`,
  `archived`. Do not use `decided` as a status.
- ADRs are durable accepted decisions; body is immutable after acceptance.
- Guides explain how. ADRs explain why. References mirror facts/source files.
- Updating passport facts requires updating `service.catalog.json` when it
  exists.

## Setup

Create exactly one bucket. If the bucket already exists, switch to audit.

Service skeleton:

```text
README.md
PASSPORT.md
spec.md
backlog.md
adr/.gitkeep
proposals/.gitkeep
guides/.gitkeep
reference/.gitkeep
reference/service.catalog.json
incidents/.gitkeep
archive/proposals/.gitkeep
archive/guides/.gitkeep
archive/reference/.gitkeep
```

Library buckets omit `PASSPORT.md`, `spec.md`, `backlog.md`, and
`reference/service.catalog.json` unless explicitly needed.

## Audit

Check:

- required files/folders for the bucket profile;
- doc-meta on managed Markdown;
- status/type/location consistency;
- no YAML frontmatter in `PASSPORT.md`;
- proposal/ADR/guide classification;
- `reference/service.catalog.json` parses and matches service identity;
- stale links after moves/renames.

Safe autofixes: `.gitkeep`, obvious doc-meta for 5 files or fewer, status/type
typos, whitespace. Propose first for moves, renames, ADR extraction, archive
tombstones, catalog creation/restructure, or bulk header insertion.

## Lifecycle

- **Proposal**: use for options under review. Accepted/rejected proposals stay
  proposals. Add an ADR only for durable architectural/operational memory.
- **ADR**: use for accepted durable decisions. May be written before, during,
  or after implementation.
- **Guide**: use for living operational steps/runbooks.
- **Reference**: use for source-tied facts: APIs, schemas, env vars, catalogs.
- **Incident**: append-only postmortem.
- **Spec**: active acceptance criteria.
- **Backlog**: future/deferred work.

When a guide contains trade-offs or "we decided", extract an ADR and leave the
guide focused on steps.

## Output

After changes, report:

- files created/moved/deleted/modified;
- validations run;
- remaining risks or proposed follow-ups.
