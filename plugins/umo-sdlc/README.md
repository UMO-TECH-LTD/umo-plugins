# umo-sdlc

UMO SDLC plugin. **v1 standardizes documentation buckets across UMO repos
and provides an audit skill that validates and autofixes structure.**

The structure is adapted from the DAVID project's docs convention
(`docs/foundation/docs-lifecycle.md`, `docs/AGENTS.md`), generalized
into two profiles: **service** (spec-driven, anchored on PASSPORT.md)
and **library** (knowledge store).

Everything else (planning, beads, memory, review, KPIs, adoption modes,
plugin composition contracts) is explicitly out of scope for v1. Those
either live in other plugins (`umo-brain`, `umo-engineering-standards`),
in CI, or in the dev's own workflow.

## Doc buckets

| Where | Bucket path | Profile | Purpose |
|-------|-------------|---------|---------|
| Per service | `services/<svc>/docs/` | service | spec-driven artifacts; **PASSPORT.md is the anchor** |
| Monorepo root | `docs/` | library | technical cross-cutting, root-level ADRs |
| Domain repo | a separate repo's `docs/` | library | business / domain knowledge |

Each bucket is a self-contained memory store owned by a single dev or
team. There is no cross-bucket source-of-truth coupling.

## PASSPORT.md is the service anchor

For any service work, **PASSPORT.md is the first file an agent reads**.
It carries:

- **YAML frontmatter** (machine-readable): `service`, `domain`,
  `teams`, `network_dependencies` (outbound + inbound),
  `exposed_contracts` (gRPC, NATS, REST), plus deployment fields.
- **Doc-meta header** (status, type=passport, owner, updated).
- **Markdown body**: overview, deployment specs, env vars, infra
  dependencies, mermaid connection diagram.

PASSPORT lives at `services/<svc>/docs/PASSPORT.md`. Other docs in the
bucket reference back to it. Cross-service awareness (which services
exist in a domain, what each one exposes) is built by aggregating
PASSPORT frontmatter — that aggregation is owned by saas-side tooling,
not the plugin.

## Profiles at a glance

```
SERVICE PROFILE                      LIBRARY PROFILE
services/<svc>/docs/                 docs/  (root or domain repo)
├── README.md                        ├── README.md
├── PASSPORT.md   ← anchor           │   (NO PASSPORT.md)
├── ROADMAP.md (optional)            ├── ROADMAP.md (optional)
├── spec.md       ← spec-driven      │   (NO spec.md / backlog.md)
├── backlog.md    ← spec-driven      │
├── adr/                             ├── adr/
├── proposals/                       ├── proposals/
├── guides/                          ├── guides/
├── reference/                       ├── reference/
├── incidents/                       ├── incidents/
└── archive/                         └── archive/
    ├── proposals/                       ├── proposals/
    ├── guides/                          ├── guides/
    └── reference/                       └── reference/
```

## Mandatory header on every managed doc

```markdown
<!-- doc-meta -->
> **Status:** draft | active | accepted | superseded | archived
> **Type:** overview | passport | roadmap | spec | backlog | proposal | adr | guide | reference | incident
> **Owner:** <gitlab handle>
> **Updated:** YYYY-MM-DD
```

For PASSPORT.md the doc-meta header sits **after** the YAML frontmatter
at the top of the file.

## Lifecycle transitions

| Type | Transitions |
|------|-------------|
| **PASSPORT** *(service only)* | always `active`; rewritten on identity / deps / contracts change |
| Spec items *(service only)* | `⏳` → `✅`. Never delete completed items. |
| Backlog items *(service only)* | bullet → `spec.md` when work begins |
| Proposal | `draft` → `decided` (paired ADR), or `draft` → `archived` |
| ADR | `accepted` → `superseded by ADR-NNN`. Body never edited. |
| Guide | `active` → `archived` |
| Reference | drift → fix same day; names source file in code |
| Incident | append-only after creation |
| Archive | read-only |

## Spec-driven workflow (service profile only)

`spec.md` is the testable contract for what this service is delivering
right now. Each AC is a checkbox with `⏳` (pending) or `✅` (done).
Backlog items become spec items when work begins. Spec items flip to
`✅` when verified. Completed items are not deleted — they are the
historical record.

```markdown
- [ ] ⏳ POST /transactions returns 201 on valid payload
- [x] ✅ POST /transactions returns 400 on missing currency
```

## What's in the package

```
plugins/umo-sdlc/
├── .cursor-plugin/plugin.json
├── .codex-plugin/plugin.json
├── README.md
├── assets/
├── rules/
│   ├── docs-buckets.mdc           alwaysApply (~50 lines, the umbrella)
│   └── docs-shape.mdc             globs: services/*/docs/** AND docs/**
└── skills/
    ├── docs-setup/SKILL.md        # bootstrap any bucket (creates PASSPORT for service)
    ├── docs-lifecycle/SKILL.md    # every create / promote / archive action, including PASSPORT updates
    └── docs-audit/SKILL.md        # validate existing bucket, autofix safe
```

Two rules, three skills, no slash commands. The shape rule fires only
when the agent edits files inside any `docs/` bucket. Eager prompt
cost is just the ~50-line umbrella rule.

## How to use it

You don't run anything manually. In a Cursor conversation:

- *"Set up the docs for `accounting`"* — `docs-setup` runs, picks the
  service profile, creates the folder skeleton, writes PASSPORT.md
  (with placeholder YAML frontmatter), README.md, spec.md, backlog.md.
- *"Audit the docs in `wallet-core`"* — `docs-audit` scans the bucket,
  flags missing PASSPORT or invalid YAML as Errors, autofixes safe
  issues (missing headers, status enum typos), proposes risky ones
  (file moves, renames). Prints a PASS / PASS WITH WARNINGS / FAIL
  verdict.
- *"Update the PASSPORT — payment-engine now calls us via gRPC"* —
  `docs-lifecycle` runs the **Update PASSPORT** action, edits YAML
  frontmatter (`network_dependencies.inbound`), bumps `Updated`, and
  reminds you to regenerate the saas network matrix.
- *"Write a proposal for moving `wallet-core` to gRPC"* —
  `docs-lifecycle` writes
  `services/wallet-core/docs/proposals/grpc-migration.md`.
- *"Decide that proposal"* — updates the proposal status and writes
  the paired ADR at `services/wallet-core/docs/adr/001-grpc.md`.
- *"Log the incident from this morning in `crypto-processor`"* —
  creates `incidents/YYYY-MM-DD-<slug>.md`.

If the agent ever drifts (puts an ADR in `proposals/`, edits an
accepted ADR's body, deletes a completed AC, creates a doc without a
header, breaks PASSPORT YAML), the `docs-shape` rule fires the next
time the file is touched and `docs-audit` will surface and (where
safe) autofix it.

## What `docs-audit` does

`docs-audit` scans a bucket and classifies findings:

| Severity | Meaning |
|----------|---------|
| **Error** | Hard rule violated. Must be fixed. (E.g. missing PASSPORT in service bucket, malformed YAML, type/location mismatch.) |
| **Warning** | Likely problem. Should be fixed; not blocking. |
| **Hint** | Style / housekeeping. Optional. |

Autofixes are split:

- **Safe** (applied automatically): missing doc-meta header, status
  enum typos, missing `.gitkeep` in empty required folders, whitespace.
- **Risky** (proposed with confirmation): file renames, file moves,
  redirect tombstones, owner inference from git blame, header
  insertions in more than 5 files in a run, **PASSPORT YAML scaffold
  insertion**.

Output is a report with `PASS`, `PASS WITH WARNINGS`, or `FAIL`.

## Out of scope (do not ask this plugin to do these)

- Beads, planning, claim semantics, monorepo-wide acceptance criteria
- Memory recall / remember (use `umo-brain`)
- Quality evidence, lint, typecheck, test (use CI + language plugins)
- MR review, closeout, KPIs (use `umo-brain` MR personas + GitLab)
- AGENTS.md at service root (auto-generated by saas's existing skill;
  it should reference the new PASSPORT location)
- Cross-service or repo-root docs containing service-specific content
- Deep PASSPORT YAML schema validation (saas's passport tooling owns
  the schema; the plugin only checks YAML parses and core fields exist)

## Migration note (important)

This is a v0.3.0 breaking change from earlier drafts. PASSPORT.md
previously lived at `services/<svc>/PASSPORT.md` (service root). It
now lives at `services/<svc>/docs/PASSPORT.md` (inside the docs bucket,
as the anchor). Saas-side tooling (`service-passport-agent-context`
skill, `passport-gen` command) needs to be updated to write to the
new location and to read the doc-meta header alongside the YAML
frontmatter.

## Manifests

- Cursor: `.cursor-plugin/plugin.json`
- Codex: `.codex-plugin/plugin.json`

## License

UNLICENSED. UMO internal.
