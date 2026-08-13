# umo-go

Cursor / Codex / Claude Code plugin for **Go** work on the UMO platform.

## What it ships

- **`agents/go-coder.md`** — the implementation agent for UMO Go services. Routes
  each kind of task to the matching skill below, follows the service's existing
  layering instead of generic tutorials, and runs the Go quality gates before
  reporting done.
- **`rules/go-awareness.mdc`** — `alwaysApply: true`. Keeps Go orientation in
  context (hand Go work to `go-coder`, load the skill first, never commit a
  local-path `replace` or a pseudo-version for a platform module). Does not push
  Go patterns into unrelated work.
- **`skills/`** — the house Go skill set:

| Skill | Covers |
|---|---|
| `go-hex-service` | Hexagonal layout on `devkit/common` — `cmd/` → `internal/app/` → `internal/repo/`, FX wiring, where code belongs |
| `go-service-architect` | Templates and workflows: new service bootstrap, gRPC, Ent, Redis, Kafka, Temporal, testing, shutdown |
| `go-google-style` | Google Go Style Guide — naming, errors, contexts, interfaces, godoc, tests |
| `go-atlas-migrations` | Declarative Atlas migrations via `devkit/common/postgres/atlas` |
| `go-local-module-dev` | Building against unreleased `proto-api` / `devkit` through `go.work`, the `go.sum` and `ambiguous import` traps, pinning a real tag, and the two-MR ordering |
| `go-dockerfile` | Trivy-enforced Dockerfile security, ECR prefix, private module auth, Go version ↔ `go.mod` sync |
| `go-quality-gates` | `go fmt` → lint → build → test, and the `GOWORK=off` variants that reproduce CI |
| `nats-events` | Publishing domain events and consuming integration events |
| `featurescript-client` | Feature flags via `devkit/common/featurescript` |
| `auditlog-client` | Audit-log v3 client over gRPC / NATS JetStream |
| `remote-config` | Redis-backed schema-driven runtime config (Go and Node) |
| `sentry-integration` | Error tracking via `devkit/common/sentry` |
| `pyroscope-integration` | Continuous profiling via `devkit/common/pyroscope` |

## Install

Same flow as the other `umo-plugins` — add the marketplace, install **`umo-go`**,
reload. In Claude Code the agent then appears as `go-coder`.

## Provenance

Most skills are vendored from `products/saas` (`.cursor/skills/` and
`.cursor/rules/`) at `ea8e83db6` (2026-08-11), so Claude Code and Codex get
skills that previously only Cursor could load in that one repo. Rules converted
to skills (`go-hex-service`, `go-atlas-migrations`, `go-dockerfile`,
`go-quality-gates`) keep their body text; only the frontmatter and in-repo
cross-references were rewritten. `go-local-module-dev` was written for this
plugin from `saas`'s `.cursor/rules/go-local-module-dev.mdc` (FIN-219),
generalised away from `saas`-only paths.

When one of these skills changes in `saas`, re-vendor it here in the same MR —
they are copies, not symlinks, and silent divergence is the failure mode to
watch for.
