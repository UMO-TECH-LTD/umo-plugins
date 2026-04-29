---
name: docs-setup
description: Bootstrap a docs bucket. Use when the user asks to set up docs for a service, initialize a docs folder at the repo root or in a domain repo, or add the canonical structure to a bucket that doesn't have it yet.
---

# Docs Setup

Bootstrap a single docs bucket. Idempotent — never overwrite an existing
file. If the user wants to repair an existing bucket, use `docs-audit`
instead.

## Pick the bucket and profile

| Where the user is working | Bucket path | Profile |
|---------------------------|-------------|---------|
| Inside `services/<svc>/` of a monorepo | `services/<svc>/docs/` | **service** |
| Monorepo root | `docs/` | **library** |
| A separate (domain) repo | `<repo-root>/docs/` | **library** |

If unclear, ask the user. Never set up a bucket in a path that does not
match one of the three patterns.

## Steps

1. **Identify the bucket path** and confirm with the user.

2. **Determine the profile.**
   - Service buckets are spec-driven and have **PASSPORT.md as the
     anchor** plus `spec.md` and `backlog.md`.
   - Library buckets are knowledge stores with no PASSPORT, no spec.md,
     no backlog.md.
   For service buckets, check that the parent `services/<svc>/` exists.
   If not, stop and ask.

3. **Check the current state.** List the bucket if it exists. If a
   `docs/` folder is already there, do not overwrite anything; print
   the current state and recommend running `docs-audit` instead.

4. **Create the folder skeleton.**

   **Service profile:**
   ```
   <bucket>/
   ├── README.md
   ├── PASSPORT.md      ← service anchor
   ├── spec.md
   ├── backlog.md
   ├── adr/.gitkeep
   ├── proposals/.gitkeep
   ├── guides/.gitkeep
   ├── reference/.gitkeep
   ├── incidents/.gitkeep
   └── archive/
       ├── proposals/.gitkeep
       ├── guides/.gitkeep
       └── reference/.gitkeep
   ```
   `ROADMAP.md` is optional — only create when the user asks.

   **Library profile:**
   ```
   <bucket>/
   ├── README.md
   ├── adr/.gitkeep
   ├── proposals/.gitkeep
   ├── guides/.gitkeep
   ├── reference/.gitkeep
   ├── incidents/.gitkeep
   └── archive/
       ├── proposals/.gitkeep
       ├── guides/.gitkeep
       └── reference/.gitkeep
   ```
   Never create `PASSPORT.md`, `spec.md`, or `backlog.md` in a library
   bucket.

5. **Write the seed files** using the templates below. Fill bucket
   name, owner / team, and today's date.

6. **Verify.** Confirm folders + files exist, headers and YAML
   frontmatter are present, and print the resulting tree.

---

## Templates

### `PASSPORT.md` — service profile only (the anchor)

```markdown
---
service: <svc-name>
domain: <one-of: payment-hub | backoffice | portal | bff | dwh | crm | compliance | wallet | infra>
teams: [<team-handle>]
namespace: <k8s-namespace>
cluster: <cluster-name>
region: <region>
network_dependencies:
  outbound:
    internal: []         # other services this one calls
    infrastructure: []   # databases, caches, queues
    external: []         # external APIs
  inbound: []            # services / clients that call this one
exposed_contracts:
  grpc: []               # [{ service, methods, proto }]
  nats:
    publishes: []
    subscribes: []
  rest:
    base: ""
    endpoints: []
---
<!-- doc-meta -->
> **Status:** active
> **Type:** passport
> **Owner:** <team or handle>
> **Updated:** YYYY-MM-DD

# <Service Name> Service Passport

> The canonical service identity record. Read this first.

## Overview

One-paragraph description of what this service does and why it exists.

## Deployment Specifications

| Property | Value |
|----------|-------|
| Service Name | `<svc-name>` |
| Tier | <backend | frontend | worker> |
| Namespace | `<k8s-namespace>` |
| Cluster | `<cluster>` |
| CPU / Memory | <request / limit, or "Not documented in repo"> |
| Replicas | <min / max, or "Not documented in repo"> |

## Environment Variables

> Common variables: `../../docs/common_config.md`

### Service-Specific Configuration

| Variable | Description | Required | Default | Type | Source |
|----------|-------------|----------|---------|------|--------|
| `<NAME>` | <description> | <Yes / No> | <default> | <type> | <Config / Secret> |

## Infrastructure Dependencies

| Service | Type | Usage | Configuration |
|---------|------|-------|---------------|
| <name> | <Database / Cache / Queue / ...> | <usage> | <Shared / Dedicated> |

## Exposed Contracts

### gRPC

| Service | Methods | Proto |
|---------|---------|-------|
| `<svc.v1.Service>` | <list> | `<path or repo>` |

### NATS

| Direction | Topic / Subject | Schema |
|-----------|-----------------|--------|
| publishes | `<topic>` | `<reference>` |
| subscribes | `<topic>` | `<reference>` |

### REST

| Method | Path | Purpose |
|--------|------|---------|

## Service Connections

```mermaid
graph LR
  SVC[<svc-name>]
  SVC -->|<protocol:port>| Dep[<dep-name>]
```

## See also

- Spec (in-flight AC): [`spec.md`](./spec.md)
- Backlog: [`backlog.md`](./backlog.md)
- Decisions: [`adr/`](./adr/)
- Proposals: [`proposals/`](./proposals/)
- Operational guides: [`guides/`](./guides/)
- Contracts and schemas: [`reference/`](./reference/)
```

### `README.md` — service profile

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** overview
> **Owner:** <gitlab handle>
> **Updated:** YYYY-MM-DD

# <Service Name>

One-paragraph description of what this service does.

> **Anchor**: read [`PASSPORT.md`](./PASSPORT.md) first — it carries the
> canonical identity, network dependencies, and exposed contracts.

## Quick links

| Topic | Entry |
|-------|-------|
| **Service identity (anchor)** | [`PASSPORT.md`](./PASSPORT.md) |
| What's coming next | [`ROADMAP.md`](./ROADMAP.md) |
| In-flight acceptance criteria | [`spec.md`](./spec.md) |
| Future / deferred work | [`backlog.md`](./backlog.md) |
| Design proposals | [`proposals/`](./proposals/) |
| Decisions (immutable) | [`adr/`](./adr/) |
| Operational guides | [`guides/`](./guides/) |
| Contracts and references | [`reference/`](./reference/) |
| Postmortems | [`incidents/`](./incidents/) |
| Read-only history | [`archive/`](./archive/) |

## Owners

- Code: <handle>
- Docs: <handle>
```

### `README.md` — library profile

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** overview
> **Owner:** <team handle>
> **Updated:** YYYY-MM-DD

# <Bucket Name>

One-paragraph description of what this bucket holds and who owns it.

## Quick links

| Topic | Entry |
|-------|-------|
| What's coming next (optional) | [`ROADMAP.md`](./ROADMAP.md) |
| Design proposals | [`proposals/`](./proposals/) |
| Decisions (immutable) | [`adr/`](./adr/) |
| Operational guides | [`guides/`](./guides/) |
| Contracts and references | [`reference/`](./reference/) |
| Postmortems | [`incidents/`](./incidents/) |
| Read-only history | [`archive/`](./archive/) |

## Owners

- Bucket: <team or handle>
```

### `spec.md` — service profile only

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** spec
> **Owner:** <gitlab handle>
> **Updated:** YYYY-MM-DD

# <Service Name> — Spec

Testable acceptance criteria for in-flight work in this service.

Each item is a checkbox with `⏳` (pending) or `✅` (done). Move items
here from `backlog.md` when work begins. Flip `⏳` → `✅` when verified.
Do not delete completed items.

## Acceptance criteria

- [ ] ⏳ <criterion 1, e.g. "POST /foo returns 201 on valid payload">
- [ ] ⏳ <criterion 2>
```

### `backlog.md` — service profile only

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** backlog
> **Owner:** <gitlab handle>
> **Updated:** YYYY-MM-DD

# <Service Name> — Backlog

Future work, ideas, deferred items. Promote into `spec.md` when work begins.

## Up next

- <item, optional link to proposal>

## Later

- <item>

## Considered, not doing

- <item — reason>
```

### `ROADMAP.md` — optional, both profiles

```markdown
<!-- doc-meta -->
> **Status:** active
> **Type:** roadmap
> **Owner:** <gitlab handle>
> **Updated:** YYYY-MM-DD

# <Bucket Name> — Roadmap

What's being added next, in rough order. Keep this short — details live
in `spec.md`, `backlog.md`, and `proposals/`.

## In flight

- <one-liner, link to spec.md item or proposal>

## Up next

- <one-liner>

## After that

- <one-liner>
```

## Forbidden

- Overwriting an existing `README.md`, `PASSPORT.md`, `spec.md`, or
  `backlog.md`.
- Creating `PASSPORT.md`, `spec.md`, or `backlog.md` in a library bucket.
- Bootstrapping multiple buckets in a single run — confirm and run the
  skill again per bucket.
- Setting up a docs folder at a path that doesn't match one of the
  three bucket types.
