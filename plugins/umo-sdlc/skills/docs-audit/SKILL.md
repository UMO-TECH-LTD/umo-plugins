---
name: docs-audit
description: Audit a docs bucket against the umo-sdlc structure and autofix safe issues. Use when the user asks to audit, validate, check, lint, or fix the docs structure of a service, the repo root, or a domain repo. Works on existing buckets; if a bucket does not exist, hand off to docs-setup.
---

# Docs Audit

Scan a docs bucket, classify findings by severity, autofix the safe ones,
and propose the risky ones with explicit confirmation. Output is a
report the user can act on or stamp with a verdict.

## When to use

- "Audit the docs in `<service>`."
- "Check that the root `docs/` is structured correctly."
- "Fix the docs structure in `<repo>`."
- "Validate the bucket against umo-sdlc."

## Pre-flight

1. **Identify the target bucket(s):**
   - one service: `services/<svc>/docs/`
   - all services: every directory matching `services/*/docs/`
   - repo root: `docs/`
   - domain repo: a path the user names explicitly
2. **Detect profile per bucket:**
   - service profile if the bucket has `PASSPORT.md`
   - library profile otherwise
   - if the bucket location is `services/<svc>/docs/`, it should be
     service profile; report a finding (Error) if PASSPORT is missing
3. **Confirm scope** with the user before mass changes (more than 5
   files modified, or any file moved or renamed).

## Audit steps

### Step 1 — Required files

For the active profile:

- service profile: `README.md`, **`PASSPORT.md`** (the anchor),
  `spec.md`, `backlog.md` must exist
- library profile: `README.md` must exist; `PASSPORT.md`, `spec.md`,
  `backlog.md` must NOT exist (those are service-only artifacts)
- both: `adr/`, `proposals/`, `guides/`, `reference/`, `incidents/`,
  `archive/{proposals,guides,reference}/` must exist

Missing required files / folders → **Error**.
Forbidden files present (e.g. `PASSPORT.md` in library, `spec.md` in
library) → **Error**.

### Step 2 — Doc-meta header

Every `.md` file under the bucket (excluding `.gitkeep`) must start with
the doc-meta marker and carry the four fields:

```markdown
<!-- doc-meta -->
> **Status:** ...
> **Type:** ...
> **Owner:** ...
> **Updated:** YYYY-MM-DD
```

For PASSPORT.md, the doc-meta block sits **after** the YAML frontmatter,
not before it.

Missing marker or any required field → **Error**.
Status not in the allowed set (`draft`, `active`, `accepted`,
`superseded`, `archived`) → **Error**.
Type not in the allowed set (`overview`, `passport`, `roadmap`, `spec`,
`backlog`, `proposal`, `adr`, `guide`, `reference`, `incident`) →
**Error**.
`Updated` more than 12 months old on a doc with status `active` →
**Warning**.

### Step 2a — PASSPORT YAML frontmatter (service profile only)

`PASSPORT.md` must additionally have YAML frontmatter at the very top of
the file (before the doc-meta block):

```yaml
---
service: <name>
domain: <domain>
teams: [...]
network_dependencies: { outbound: {...}, inbound: [...] }
exposed_contracts: { grpc: [...], nats: {...}, rest: {...} }
---
```

Audit checks (the plugin does **not** validate the deep schema of these
fields — the saas-side passport tooling owns that):

- YAML frontmatter present and parseable → otherwise **Error**.
- `service` field present and matches the directory name
  (`services/<svc>/`) → otherwise **Error**.
- `domain` field present (any non-empty string) → otherwise **Warning**.
- `teams` field present, non-empty array → otherwise **Warning**.
- Status in the doc-meta block must be `active` → otherwise **Error**
  (PASSPORTs do not move through draft/superseded/archived states).
- Type in the doc-meta block must be `passport` → otherwise **Error**.

### Step 3 — Naming

- `adr/*.md` matches `^[0-9]{3}-[a-z0-9-]+\.md$` → otherwise **Warning**
- `incidents/*.md` matches `^\d{4}-\d{2}-\d{2}-[a-z0-9-]+\.md$` →
  otherwise **Warning**
- All other docs use kebab-case → otherwise **Hint**

### Step 4 — Type / location consistency

- `Type: adr` only in `adr/` (or `archive/adr/` if archived).
- `Type: proposal` only in `proposals/` or `archive/proposals/`.
- `Type: guide` only in `guides/` or `archive/guides/`.
- `Type: reference` only in `reference/` or `archive/reference/`.
- `Type: incident` only in `incidents/`.
- `Type: spec` only at `spec.md` (service buckets).
- `Type: backlog` only at `backlog.md` (service buckets).
- `Type: roadmap` only at `ROADMAP.md`.
- `Type: passport` only at `PASSPORT.md` (service buckets).
- `Type: overview` only at `README.md`.

Type / location mismatch → **Error**.

### Step 5 — Archive immutability

Files under `archive/` should not have a status other than `archived`
or `superseded`. Files under `archive/` whose `Updated` is more recent
than the move date noted in the file → **Warning** (potential edit).

### Step 6 — Service-profile spec hygiene

Service buckets only:

- Every `spec.md` AC line is a checkbox with `⏳` (open) or `✅` (done).
  Lines that look like AC but lack a marker → **Warning**.
- AC items with `⏳` whose surrounding context has not been touched in
  the file's git history for 6+ months → **Hint** (stale).
- ADR header `Supersedes:` references an existing ADR → otherwise
  **Error**.

### Step 7 — Reference source linkage

Every `reference/*.md` should have a `## Source` section that names a
file path. Missing → **Warning**.
Path that no longer exists in the repo → **Error**.

## Findings classification

| Severity | Meaning |
|----------|---------|
| **Error** | Violates a hard rule. Must be fixed (autofix or manual). |
| **Warning** | Likely problem. Should be fixed; not blocking. |
| **Hint** | Style / housekeeping. Optional. |

## Autofix policy

### Safe — apply automatically

- Insert a missing doc-meta header. Status defaults to:
  - folder = `archive/**` → `archived`
  - file = `PASSPORT.md` → `active` (PASSPORTs are always active)
  - folder = `adr/` → `accepted`
  - folder = `proposals/` → `draft`
  - everything else → `active`
  Type defaults to the folder's canonical type (`passport` for
  PASSPORT.md). Owner defaults to a placeholder `<unknown>`. Updated
  defaults to today.
- Fix typos in the Status / Type enum values when there is one obvious
  intended value (`draft` for `darft`, `accepted` for `accpted`, etc.).
- Add missing `.gitkeep` to empty required folders.
- Trim trailing whitespace and normalize line endings in managed docs.

### Risky — propose with confirmation, do not auto-apply

- Renaming a file (e.g. ADR not in `NNN-slug` form). Naming changes
  break links; show old → new pairs and ask.
- Moving a file (e.g. `Type: adr` doc found in `proposals/`). Show
  source → destination and ask.
- Adding a redirect tombstone for a file that was moved without one.
- Inferring `Owner` from git blame.
- Bulk header insertion in more than 5 files in one run.
- Inserting a YAML frontmatter scaffold into a missing or malformed
  PASSPORT.md. The frontmatter shape is owned by saas's passport
  tooling; do not autofill domain / network deps / contracts blindly.
  Propose a minimal scaffold with placeholder values and ask before
  writing it.

## Report shape

Print a single report at the end:

```
=== Docs Audit ===
Bucket: <path>
Profile: service | library

Errors (N):
- <path>: <issue> [autofix: applied | proposed | manual]
- ...

Warnings (M):
- <path>: <issue> [autofix: applied | proposed | manual]
- ...

Hints (K):
- <path>: <issue>
- ...

Autofixed (X):
- <path>: <what was done>
- ...

Proposed (Y) — confirm to apply:
- <path>: <what would be done>
- ...

Verdict: PASS | PASS WITH WARNINGS | FAIL
```

`PASS` = no errors. `PASS WITH WARNINGS` = no errors, has warnings.
`FAIL` = at least one unresolved error after autofix.

## Forbidden

- Auto-renaming or auto-moving files without explicit user confirmation.
- Editing files inside `archive/` to "fix" the doc-meta header — leave
  archived content as is and add a finding instead.
- Running the audit on a path that is not a recognized bucket
  (`services/*/docs/`, `docs/` at repo root, or an explicitly named
  domain repo `docs/` path).
- Bulk-applying header insertion in more than 5 files in one run; ask
  first.
- Reporting `PASS` while errors exist.

## Hand-offs

- Bucket missing entirely → recommend `docs-setup`.
- A specific lifecycle action needed (e.g. abandon a proposal that the
  audit found stale) → recommend `docs-lifecycle` with the action.
