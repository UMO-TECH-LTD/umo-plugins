---
name: go-hex-service
description: Hexagonal architecture standards for Go microservices built on devkit/common — cmd/ to internal/app/ to internal/repo/ layering, Uber FX wiring, port and adapter boundaries, and the file layout a new or refactored service must follow. Use when creating a Go service, adding a module or adapter, or reviewing whether code sits in the right layer.
---

# Go Hexagonal Service Standards

Concise rules for Go microservices following Hexagonal Architecture with devkit/common.

For **detailed templates, implementation guides, and step-by-step workflows**, use the the `go-service-architect` skill in this plugin.

Applies to all Go services in this repository.

---

## 1. Architecture

### Layers and Direction

```
Handlers (Transport) -> Services (Business) -> Domain (Core)
                              |
                      Repositories -> External Clients
```

**FORBIDDEN:**
- Domain importing anything except stdlib
- Service knowing concrete repo implementation
- Handler containing business logic
- Repo knowing about transport layer
- Cross-layer imports violating direction

### Three-File Pattern (Services, Repos, Clients)

| File | Purpose |
|------|---------|
| service.go / client.go | Interface definition (port) |
| default.go / default_client.go | Business logic / implementation |
| instrumented.go | Observability wrapper using devkit/common |

---

## 2. Bootstrap Ordering (Critical)

Fx modules MUST be ordered:

1. `platformfx.Module` -- Always first (provides shutdown manager)
2. `loggerfx.ModuleWithOptions` -- Logger with OTel integration
3. `tracefx.Module` -- Distributed tracing
4. Infrastructure modules (database, cache, message queue)
5. Transport modules (HTTP, gRPC) -- Always last

### Shutdown Hook Priorities

| Priority | Constant | Component |
|----------|----------|-----------|
| 10 | PriorityServer | HTTP/gRPC servers |
| 20 | PriorityWorker | Background workers |
| 40 | PriorityCache | Redis, caches |
| 60 | PriorityDatabase | Database, Temporal clients |
| 90 | PriorityTracer | Tracing exporters |
| 100 | PriorityLogger | Logger (last) |

Always separate startup (`fx.Invoke`) from shutdown (`platformfx.ProvideShutdownHook`).

---

## 3. Instrumentation (MANDATORY)

All instrumented wrappers MUST use `trace.Instrument(ctx, method)`:

```go
ctx, span := trace.Instrument(ctx, s.inner.Create)
defer span.End()
```

Do NOT use `trace.Start(ctx, "manual.name")` -- it lacks code location attributes and is deprecated for service/repo/client instrumentation.

---

## 4. Error Handling

### Rules

- Domain: Define sentinel errors (`ErrNotFound`, `ErrInvalid...`)
- Service: Wrap errors with context: `fmt.Errorf("operation: %w", err)`
- Repository: Convert DB errors to domain errors, wrap with context
- Handler: Map domain errors to gRPC/HTTP status codes
- Use `errors.Is()` for wrapped errors, never direct comparison
- NEVER expose internal errors to clients: `status.Error(codes.Internal, "internal error")`

---

## 5. Code Conventions

### Naming

| What | Rule | Example |
|------|------|---------|
| Packages | lowercase, short | entity, repo, grpc |
| Interfaces | No I-prefix | Service, Repo |
| Errors | Err prefix | ErrNotFound |
| Constructors | New prefix | NewService() |

### Import Grouping (4 groups)

```go
import (
    // 1. Standard library
    "context"

    // 2. External packages
    "github.com/google/uuid"

    // 3. DevKit common
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"

    // 4. Local packages
    "gitlab.com/myproject/myservice/internal/core/entity"
)
```

### Style

- **Early return**: Validate and return early, avoid deep nesting
- **Context first**: `ctx context.Context` is always the first parameter
- **Godoc**: Exported types, functions, and methods MUST have godoc comments ending with a period
- **Pointer receivers**: For structs with state
- **Value receivers**: For small value objects (enums, IDs)

---

## 6. Database

- Source of truth: `atlas/schema.sql`. Migrations generated with Atlas.
- Always use parameterized queries (`$1`, `$2`, ...) -- never string interpolation
- Always filter by `tenant_id` in repository queries (multi-tenancy)
- Handle `pgx.ErrNoRows` explicitly

---

## 7. Linting and Testing

### Required Before Every Task Completion

```bash
make fmt    # Format code
make lint   # Run golangci-lint
make test   # Run tests
```

### Test Pyramid

| Layer | Location | What |
|-------|----------|------|
| Domain | internal/core/{entity}/*_test.go | Validation, business logic |
| Service | internal/services/{entity}/default_test.go | Use cases with mock repo |
| Handlers | internal/handlers/grpc/*_test.go | Request handling, error mapping |
| Integration | test/integration/ | Real DB (//go:build integration) |

Use table-driven tests. Prefer functional mocks over generated mocks.

---

## 8. DevKit Common Packages Quick Reference

| Package | Import | Purpose |
|---------|--------|---------|
| `platformfx` | `devkit/common/platformfx` | Bootstrap Fx app, shutdown hooks |
| `config` | `devkit/common/config` | Typed config with `config.Load[T]()` |
| `config/remoteconfig` | `devkit/common/config/remoteconfig` | Runtime-configurable settings backed by Redis |
| `logger` | `devkit/common/logger` | Structured logging interface (zap backend) |
| `observability` | `devkit/common/observability` | OTel provider, tracing, log context |
| `trace` | `devkit/common/observability/trace` | `trace.Instrument()`, `trace.InstrumentNamed()` |
| `grpcserver` | `devkit/common/grpcserver` | gRPC server builder + interceptors |
| `grpcerr` | `devkit/common/grpcerr` | Domain-to-gRPC error mapping |
| `grpcclient` | `devkit/common/grpcclient` | gRPC client builder |
| `http` | `devkit/common/http` | HTTP server builder (Gin) |
| `postgres` | `devkit/common/postgres` | PostgreSQL pool (pgx) + Atlas migrations |
| `redis` | `devkit/common/redis` | Redis client (standalone/cluster/sentinel) |
| `nats` | `devkit/common/nats` | NATS client + JetStream |
| `auditlogclient` | `devkit/common/auditlogclient` | Audit-log v3 client (typed manifest, gRPC/NATS transports, ctx auto-fill, server auto-emit interceptor) |
| `temporal` | `devkit/common/temporal` | Temporal client/worker + Fx |
| `shutdown` | `devkit/common/shutdown` | Signal handling, LIFO cleanup |
| `sentry` | `devkit/common/sentry` | Sentry error tracking + gRPC interceptors |
| `pyroscope` | `devkit/common/pyroscope` | Grafana Pyroscope profiling + gRPC interceptors |
| `featurescript` | `devkit/common/featurescript` | Feature flag client |
| `sharedmemory` | `devkit/common/sharedmemory` | Redis-backed shared state (KV, List, Map, Set) |
| `xctx` | `devkit/common/xctx` | Context values (TenantID, UserID, RequestID, Fields) |
| `cuid` | `devkit/common/cuid` | CUID2 ID generation |
| `money` | `devkit/common/money` | Decimal amount and precision types |
| `pagination` | `devkit/common/pagination` | Offset/Limit/Span primitives |
| `ptr` | `devkit/common/ptr` | Generic pointer helpers (`MapNil`, `MapNilErr`) |

Import prefix: `gitlab.com/umo-tech-ltd-group/platform/devkit/common/`

> **Note:** `kafka` (`devkit/common/kafka`) is **deprecated**. New services should use NATS via `devkit/common/nats`.
