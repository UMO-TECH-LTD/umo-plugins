---
description: Set up, audit, or evolve UMO managed docs buckets (service docs, root/domain docs, PASSPORT.md, service.catalog.json, proposals, ADRs, guides, references, incidents).
argument-hint: "[bucket path or action: setup | audit | lifecycle]"
---

# UMO Docs

Request: $ARGUMENTS

Invoke the `docs` skill (defined in `plugins/umo-sdlc/skills/docs/SKILL.md`) for any non-trivial docs work. That skill carries the full setup, audit, and lifecycle behavior, and loads templates from `references/` and `assets/`. Use this command as the entry point.

## Bucket profiles

- `services/<svc>/docs/` is a **service bucket**.
- `docs/` at repo root (or a domain repo `docs/`) is a **library bucket**.
- Service bucket required files: `README.md`, `PASSPORT.md`, `spec.md`, `backlog.md`.
- Library buckets must not contain `PASSPORT.md`, `spec.md`, or `backlog.md`.
- Both profiles use `adr/`, `proposals/`, `guides/`, `reference/`, `incidents/`, and `archive/{proposals,guides,reference}/`.
- Buckets may add indexed category folders (e.g. `docs/infrastructure/nats/`) when a domain has enough docs to justify a local index.
- Legacy root service passports (`services/<svc>/PASSPORT.md`) may exist before migration. Treat them as sources for the docs bucket; do not strip YAML frontmatter unless an explicit migration task says to.

## Markdown header

Every managed Markdown doc starts with:

```markdown
<!-- doc-meta -->
> **Status:** draft | active | accepted | rejected | implemented | superseded | archived
> **Type:** overview | passport | roadmap | spec | backlog | proposal | adr | guide | reference | incident
> **Owner:** <gitlab handle or team>
> **Updated:** YYYY-MM-DD
```

JSON sidecars, including `reference/service.catalog.json`, do not carry doc-meta.

## Type boundaries

- Managed bucket `PASSPORT.md`: Markdown-first service entrypoint. **No YAML frontmatter.**
- `reference/service.catalog.json`: machine-readable service facts.
- `proposals/`: options under review. Statuses: `accepted`, `rejected`, `implemented`, `archived`. **Do not use `decided` as status.**
- `adr/`: durable accepted decisions, `NNN-slug.md`; body immutable after acceptance.
- `guides/`: living how-to / runbook content. Guides explain *how*; ADRs explain *why*.
- `reference/`: factual contracts / schemas / env / API docs tied to source files.
- `incidents/`: append-only postmortems, `YYYY-MM-DD-slug.md`.
- `spec.md`: in-flight acceptance criteria.
- `backlog.md`: future / deferred work.
- `ROADMAP.md`: short priority ordering with links.

## Forbidden

- Adding YAML frontmatter to managed bucket `PASSPORT.md`.
- Stripping YAML frontmatter from legacy root `services/<svc>/PASSPORT.md` outside an explicit migration.
- Creating managed Markdown without doc-meta.
- Putting ADR content in `guides/`.
- Putting mutable runbook steps in ADRs.
- Editing accepted ADR bodies.
- Deleting completed spec criteria.
- Updating passport facts without updating `reference/service.catalog.json` when the sidecar exists.
- Creating category folders without a `README.md` index and root bucket link.

## What to do next

Classify the action (`setup` / `audit` / `lifecycle`), open the `docs` skill, and run its workflow. Report files created / moved / deleted / modified, validations run, and any remaining risks.
