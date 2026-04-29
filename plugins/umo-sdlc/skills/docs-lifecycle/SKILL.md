---
name: docs-lifecycle
description: Create, promote, supersede, or archive any managed doc in any docs bucket — including the service PASSPORT.md (the anchor). Service buckets live at services/<svc>/docs/; library buckets at repo root or in a domain repo. Use when the user asks to update PASSPORT, write a proposal/ADR/guide/reference/incident, decide a proposal, supersede an ADR, archive a guide, update spec.md, promote a backlog item, or update the roadmap.
---

# Docs Lifecycle

Single skill for every lifecycle action on managed docs in any docs
bucket, including updates to PASSPORT.md (the service anchor). Templates
are embedded inline so the agent does not need to read external files.

## Pre-flight (always)

1. **Identify the bucket** the action targets:
   - service bucket: `services/<svc>/docs/`
   - library bucket at monorepo root: `docs/`
   - library bucket in a domain repo: `<repo-root>/docs/`
2. **Confirm the bucket exists.** If not, stop and run `docs-setup` first.
3. **Detect the profile**:
   - **Service** profile if the bucket has `PASSPORT.md`.
   - **Library** profile otherwise.
   The profile gates which actions are available — actions L, M, O are
   service-only.
4. **For service work, read PASSPORT.md first.** It is the canonical
   service identity record. Many lifecycle actions need its YAML
   frontmatter (domain, network deps, exposed contracts) for context.
5. **Confirm the action** (see menu below).
6. **Pick a slug**: lowercase, kebab-case, ~5 words max.

## Action menu

Paths below show the service bucket form. For a library bucket replace
`services/<svc>/docs/` with the library bucket path (`docs/` at repo
root, or the domain repo's `docs/`).

| Goal | Action | Section | Profiles |
|------|--------|---------|----------|
| Write a design under consideration | create proposal | A | both |
| Move proposal to decision | decide proposal | B | both |
| Drop a proposal that won't ship | abandon proposal | C | both |
| Record a small or after-the-fact decision | create ADR | D | both |
| Replace an existing ADR | supersede ADR | E | both |
| Write a how-to or runbook | create guide | F | both |
| Retire a guide | archive guide | G | both |
| Add a contract / schema / API spec | create reference | H | both |
| Code moved, doc must follow | update reference | I | both |
| Retire a reference | archive reference | J | both |
| Record a postmortem | log incident | K | both |
| Add or close acceptance criteria | update spec.md | L | **service only** |
| Move a backlog item into in-flight work | promote backlog | M | **service only** |
| Update what's coming next | update roadmap | N | both (if `ROADMAP.md` exists) |
| Service identity / deps / contracts changed | update PASSPORT | O | **service only** |

---

## A. Create proposal

- Path: `<bucket>/proposals/<slug>.md`
- Status: `draft`
- Use the **proposal template** below. Fill summary, problem, options.
  Leave Decision blank until decided.

## B. Decide proposal

- Edit the proposal header: `Status: draft` → `Status: decided`. Add
  `Decided: YYYY-MM-DD` and `ADR: ./adr/NNN-<slug>.md`.
- Write the paired ADR at `<bucket>/adr/NNN-<slug>.md` using the
  **ADR template**. `NNN` is the next free integer in `adr/`,
  zero-padded to 3 digits.
- After this, do not edit the body of either doc. New decisions are new
  ADRs; new context is a new proposal.

## C. Abandon proposal

- Move the file to `<bucket>/archive/proposals/<slug>.md`.
- Header: `Status: archived`, add `Archived: YYYY-MM-DD` and `Reason: ...`.
- Leave a redirect tombstone at the original path:
  ```markdown
  > Moved to `../archive/proposals/<slug>.md` on YYYY-MM-DD.
  ```

## D. Create ADR

- Use only for decisions that did not go through a proposal (small,
  obvious, or after-the-fact). Most ADRs come from decided proposals.
- Path: `<bucket>/adr/<NNN>-<slug>.md`
- Status: `accepted`. ADRs are immutable — body never edited after writing.

## E. Supersede ADR

- Write the new ADR at `<bucket>/adr/<NNN+1>-<slug>.md`,
  Status: `accepted`. Add `Supersedes: ADR-<old-NNN>` to the header.
- In the **old** ADR, edit only the status line:
  `Status: superseded by ADR-<new-NNN>`. Body untouched.

## F. Create guide

- Path: `<bucket>/guides/<slug>.md`
- Status: `active`. Guides are living — edit in place; bump `Updated`.

## G. Archive guide

- Move to `<bucket>/archive/guides/<slug>.md`.
- Header: `Status: archived`, add `Archived: YYYY-MM-DD` and `Reason: ...`.
- Leave a redirect tombstone at the original path.

## H. Create reference

- Path: `<bucket>/reference/<slug>.md`
- Status: `active`. Reference docs **must name their source file in code**
  (proto, schema, OpenAPI, env var definition).

## I. Update reference (drift fix)

- When code moves or contracts change, update the reference the same day.
- Bump `Updated`. If the source file path changed, update the link in the
  reference doc body.

## J. Archive reference

- Move to `<bucket>/archive/reference/<slug>.md`.
- Header: `Status: archived`, add `Archived: YYYY-MM-DD` and `Reason: ...`.
- Leave a redirect tombstone.

## K. Log incident

- Path: `<bucket>/incidents/YYYY-MM-DD-<slug>.md`.
- Status: `active`. Incidents are append-only after creation; never
  rewrite history. New findings are appended with a timestamped section.

## L. Update spec.md (service profile only)

- Only available in service buckets where `spec.md` exists.
- **Add a new acceptance criterion**: append a checkbox line with `⏳`.
- **Close an AC**: flip `⏳` to `✅` and bump `Updated`. Never delete a
  completed item.
- **Refine an AC**: if scope changed during implementation, leave the
  original line and add a new one rather than rewriting history.
- If the change is a non-trivial design choice, write a proposal in
  `proposals/` and link it from the AC.

## M. Promote backlog → spec (service profile only)

- Only available in service buckets where `spec.md` and `backlog.md` exist.
- Pick the item from `backlog.md`.
- Translate it into one or more concrete checkbox AC under the
  appropriate section in `spec.md` with `⏳` markers.
- In `backlog.md`, mark the item as picked up: prefix with `→ in spec.md`
  rather than deleting (deletion loses the audit trail).
- Bump `Updated` on both files.

## N. Update roadmap

- Available wherever `ROADMAP.md` exists.
- Edit `ROADMAP.md` in place. Move items between "In flight", "Up next",
  "After that" as priorities shift.
- Each line should link to a `spec.md` item, a proposal, or a backlog
  entry — roadmap items without an anchor become noise.

## O. Update PASSPORT (service profile only)

PASSPORT.md is the **service anchor**. Update it whenever any of these
change:

- service identity (rename, retire — though retirement removes the
  service, not the PASSPORT alone);
- domain or owning team(s);
- network dependencies (a new internal call, a removed infrastructure
  dep, a new inbound caller);
- exposed contracts (new gRPC method or service, new NATS topic, new
  REST endpoint, deprecation of any of these);
- deployment topology (namespace, cluster, region, replicas, resources);
- environment variables.

### Steps

1. Open `<bucket>/PASSPORT.md`. Confirm the YAML frontmatter parses.
2. Edit only the fields that changed. Keep the schema intact.
3. Mirror any frontmatter change in the markdown body (the YAML is the
   source of truth, but the body must stay readable and consistent).
4. Bump `Updated:` in the doc-meta header.
5. **If a contract changed**, also create or update the matching
   reference doc under `<bucket>/reference/` (action H or I) and link
   it from the PASSPORT body.
6. **If network dependencies changed**, the saas-side
   `network-matrix-gen` tool will regenerate the cross-cutting matrix
   on next run. Note the change in the PR description so reviewers
   know it propagates.

### Forbidden

- Editing PASSPORT.md without bumping `Updated:`.
- Rewriting YAML frontmatter without reflecting the change in the
  markdown body.
- Changing `service:` (the name) — that is a service rename, which
  requires repo-wide coordination, not a single PASSPORT edit.
- Setting `Status:` to anything other than `active`. PASSPORTs do not
  go through draft / superseded / archived — a service either has a
  PASSPORT or doesn't exist.

---

## Templates

### Proposal

```markdown
<!-- doc-meta -->
> **Status:** draft
> **Type:** proposal
> **Owner:** <gitlab handle>
> **Updated:** YYYY-MM-DD

# Proposal: <Title>

## Summary

One paragraph: what problem, what change.

## Problem

What is wrong today. Concrete examples and impact.

## Goals

- ...

## Non-goals

- ...

## Options Considered

### Option A — <name>

Pros / cons.

### Option B — <name>

Pros / cons.

## Decision

Filled in when status moves to `decided`. Link the paired ADR.

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
> **Owner:** <gitlab handle>
> **Updated:** YYYY-MM-DD

# ADR-<NNN>: <Title>

## Context

What forces are at play. Link the source proposal if any.

## Decision

The chosen option, in one short paragraph.

## Consequences

What becomes easier, what becomes harder, what new constraints exist.

## Alternatives Considered

Brief — full trade-offs live in the source proposal.
```

### Guide

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** guide
> **Owner:** <gitlab handle>
> **Updated:** YYYY-MM-DD

# Guide: <Title>

## When to use

Symptom or trigger.

## Prerequisites

Tools, access, env vars.

## Steps

1. ...
2. ...

## Rollback / safety net

How to undo if step N goes wrong.

## Related

- Source ADR or proposal
- Linked dashboards or alerts
```

### Reference

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** reference
> **Owner:** <gitlab handle>
> **Updated:** YYYY-MM-DD

# Reference: <Title>

## Source

`<path/to/source/file.proto>` or `<path/to/openapi.yaml>` — this doc
mirrors that file. If the source moves, fix this doc the same day.

## Contract

<schema, fields, semantics, error codes, etc.>

## Examples

<request / response / event payload examples>

## Related

- ADR(s) that locked this contract
- Consumers (other services)
```

### Incident

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** incident
> **Owner:** <gitlab handle>
> **Updated:** YYYY-MM-DD

# Incident: <Title>

## Timeline

- HH:MM UTC — <event>
- HH:MM UTC — <event>

## Impact

Who was affected, for how long, what data or transactions were involved.

## Root cause

<one paragraph>

## Detection

How was it noticed.

## Mitigation

What action restored service.

## Lessons

- <lesson>

## Follow-ups

- [ ] ⏳ <action item, link to follow-up doc or external tracker>
```

---

## Forbidden

- Editing the body of an `accepted` ADR.
- Creating a doc in any bucket without the doc-meta header.
- Putting an ADR in `proposals/`, a guide in `reference/`, or any other
  cross-type mix.
- Bulk-archiving by deleting files. Always move to `archive/` and leave
  a tombstone.
- Cross-service docs in a single service's `docs/` tree.
- Library-bucket-specific artifacts (`PASSPORT.md`, `spec.md`,
  `backlog.md`) appearing in a library bucket. Those are service-only.
- Service-specific content in a library bucket. If the doc describes a
  single service, it belongs in `services/<svc>/docs/`.
- Deleting completed (`✅`) AC from `spec.md` to "clean up".
- Rewriting an incident's history. Append new findings, never edit
  existing sections.
- Editing `PASSPORT.md` without bumping `Updated:` or without keeping
  YAML frontmatter and markdown body in sync.

## Verify before reporting completion

- list every file created, moved, or modified;
- confirm headers carry `Status`, `Type`, `Owner`, `Updated`;
- for promotions and supersessions, confirm both old and new files are
  in the agreed state (status, links);
- for PASSPORT updates, confirm YAML frontmatter still parses and
  matches what the markdown body describes.
