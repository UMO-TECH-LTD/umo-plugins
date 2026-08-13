---
name: auditlog-client
description: Integrating the devkit audit-log v3 client into Go microservices using devkit/common/auditlogclient. Use when adding compliance/audit event emission to a Go service, wiring the client with Uber FX over gRPC or NATS JetStream, defining an audit event manifest, or when the user asks about audit logging, audit trails, VARA compliance events, or auditlogclient in Go services.
---

# Audit-Log Client for Go Microservices

## Overview

`devkit/common/auditlogclient` (devkit v0.32.0+) is a Go client for emitting audit events to the saas audit-log v3 service, over either gRPC or NATS JetStream. It provides a runtime typed-event manifest (validated at emit time, no codegen), context auto-fill from `xctx`/`grpcserver`, and an optional server-side gRPC interceptor for RPC-level auto-emit.

Import paths:
- `gitlab.com/umo-tech-ltd-group/platform/devkit/common/auditlogclient`
- `gitlab.com/umo-tech-ltd-group/platform/devkit/common/auditlogclient/fx` (as `auditlogclientfx`)

Key capabilities:
- Manifest-validated `group`/`event` emission with derived `SCREAMING_SNAKE` actions
- gRPC or NATS JetStream transport (config-driven discriminant)
- Context auto-fill: tenant, initiator ID/role, correlation ID, timestamp
- Fire-and-forget (default) or synchronous await delivery modes
- `EmitRaw` escape hatch bypassing manifest validation
- Optional server-side `UnaryServerInterceptor` for auto-emit on RPC success
- Uber FX module (`auditlogclientfx.Module`) with shutdown hook (gRPC transport only)

A reference implementation lives in `saas/services/compliance-chat`: `internal/services/auditlog/` (port + manifest + client adapter) and `internal/di/auditlog/module.go` (conditional Fx wiring).

## Quick Setup Checklist

### 1. Define a domain port (recommended)

Keep call-sites decoupled from the transport by defining your own `Service` interface with typed event structs, and an adapter that implements it via `auditlogclient.Client`. This lets you swap gRPC/NATS or add a logger-stub fallback without touching business logic.

```go
// internal/services/auditlog/service.go
package auditlog

type Service interface {
    ChatCreated(ctx context.Context, e ChatCreatedEvent) error
    // ...
}

type ChatCreatedEvent struct {
    ChatID  string
    ActorID string
    // ...
}
```

### 2. Define the manifest

```go
// internal/services/auditlog/manifest.go
package auditlog

import "gitlab.com/umo-tech-ltd-group/platform/devkit/common/auditlogclient"

var Manifest = auditlogclient.DefineEvents(auditlogclient.Manifest{
    "chat": {
        "created":  {Target: "chat"},              // TargetID required at Emit time
        "assigned": {Target: "chat", Affected: "user"}, // Affected is informational only
    },
    "user": {
        "translationDefaultSet": {}, // no Target => TargetID optional
    },
})
```

`DefineEvents` panics at package init on structural mistakes (empty manifest, empty group/event keys) — this fails fast in CI rather than at runtime. The event key drives the derived action: `camelToScreamingSnake("translationDefaultSet")` → `TRANSLATION_DEFAULT_SET`.

### 3. Implement the client adapter

```go
// internal/services/auditlog/client_adapter.go
package auditlog

import (
    "context"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/auditlogclient"
)

type ClientAuditLog struct {
    client auditlogclient.Client
}

func NewClientAuditLog(client auditlogclient.Client) *ClientAuditLog {
    return &ClientAuditLog{client: client}
}

func (c *ClientAuditLog) ChatCreated(ctx context.Context, e ChatCreatedEvent) error {
    return c.client.Emit(ctx, "chat", "created", auditlogclient.EmitParams{
        TargetID:    e.ChatID,
        InitiatorID: e.ActorID,
        Details:     map[string]any{"origin": e.Origin},
    })
}
```

Context auto-fill (do NOT set these unless overriding): `ID` (CUID2), `InitiatorRole` (from `grpcserver.UserInfoFromContext`), `CorrelationID` (from `xctx.CorrelationID`/`RequestID`), `Source` (from `Config.Source`), `Timestamp`. Tenant is read from `xctx.TenantID(ctx)` and is **required** — with no tenant in context, `ModeAwait` returns `ErrTenantNotSeeded` and the default `ModeFireAndForget` silently drops the event with a warning log.

### 4. Add config

```go
// internal/config/configuration.go
import "gitlab.com/umo-tech-ltd-group/platform/devkit/common/auditlogclient"

type Configuration struct {
    // ... existing fields ...
    AuditLog auditlogclient.Config `mapstructure:"audit_log"`
}
```

```yaml
# config/configuration.yaml
audit_log:
  transport: nats   # or "grpc"
  source: my-service
  # grpc:
  #   url: audit-log:5000
  #   use_tls: false
```

`Config.Validate()` requires `grpc.url` when `transport: grpc`; NATS transport reuses the shared JetStream publisher (no extra connection config here). `auditlogclient.DefaultConfig()` supplies NATS retry backoff (`100ms, 500ms, 1s`) and a `.dlq` suffix.

### 5. Wire the Fx module

**NATS transport** (preferred — fully async, no hard runtime dependency on the audit-log service):

```go
app := fx.New(
    platformfx.Module(platformfx.DefaultConfig()),
    loggerfx.Module(loggerCfg),
    natsfx.Module(cfg.Nats, "my-service"),           // MUST come first — provides *nats.JetStreamPublisher
    auditlogclientfx.Module(cfg.AuditLog, auditlog.Manifest),
)
```

**gRPC transport** (self-dials, no NATS required):

```go
app := fx.New(
    platformfx.Module(platformfx.DefaultConfig()),
    loggerfx.Module(loggerCfg),
    auditlogclientfx.Module(cfg.AuditLog, auditlog.Manifest),
)
```

`auditlogclientfx.Module` provides `auditlogclient.Config`, `auditlogclient.Manifest`, and `auditlogclient.Client`. Register your adapter to satisfy your own `Service` port:

```go
fx.Provide(
    fx.Annotate(auditlog.NewClientAuditLog, fx.As(new(auditlog.Service))),
),
```

### 6. Conditional wiring with a fallback (optional but recommended)

If NATS is conditionally enabled in your service, gate the audit module and fall back to a no-op/logger stub so local/CI runs without NATS still work:

```go
func Module(cfg *config.Configuration) fx.Option {
    if !(cfg.Nats.Enabled && cfg.Nats.JetStream.Enabled) {
        return fx.Module("auditlog",
            fx.Provide(fx.Annotate(NewLoggerAuditLog, fx.As(new(auditlog.Service)))),
        )
    }
    return fx.Module("auditlog",
        auditlogclientfx.Module(cfg.AuditLog, auditlog.Manifest),
        fx.Provide(fx.Annotate(auditlog.NewClientAuditLog, fx.As(new(auditlog.Service)))),
    )
}
```

See `saas/services/compliance-chat/internal/di/auditlog/module.go` for the full reference.

## Usage Patterns

### Emitting from a service/handler

```go
err := auditSvc.ChatCreated(ctx, auditlog.ChatCreatedEvent{
    ChatID:  chat.ID,
    ActorID: actor.ID,
    Origin:  "agent",
})
if err != nil {
    log.Warn(ctx, "audit log failed (best-effort, ignored)", logger.Err(err))
}
```

Audit logging should be **best-effort** — never block or fail the primary operation on an audit emit error.

### Direct manifest emission (no domain port)

```go
err := client.Emit(ctx, "transactions", "confirm", auditlogclient.EmitParams{
    TargetID:   "txn-123",
    AffectedID: "cust-9",
    Details:    map[string]any{"amount": "100.00"},
    Mode:       auditlogclient.ModeAwait, // optional; default is fire-and-forget
})
```

### Escape hatch: EmitRaw

Bypasses manifest validation, tenant checks, and context auto-fill — always synchronous. Use only for special cases (backfills, one-off events not worth manifest entries):

```go
err := client.EmitRaw(ctx, auditlogclient.LogEvent{
    ID: cuid, Source: "my-service", Action: "CUSTOM_ACTION", Group: "custom",
    InitiatorID: userID, Timestamp: time.Now().UTC(),
})
```

### Server-side auto-emit interceptor (reduces manual Emit calls)

For RPC methods where the audit event maps 1:1 to a successful call, register a `MethodRegistry` instead of calling `Emit` manually in every handler:

```go
registry := auditlogclient.NewMethodRegistry().
    Register("/saas.foo.v1.Svc/DoThing", "foo", "doThing",
        auditlogclient.WithTargetIDFunc(func(req, _ any) string {
            return req.(*pb.DoThingRequest).GetId()
        }),
        auditlogclient.WithAffectedType("customer"),
    )

fx.Provide(auditlogclientfx.NewUnaryServerInterceptor(registry))
// then chain the resulting grpc.UnaryServerInterceptor into your interceptor chain
```

Flow: handler runs → on success only, look up the method in the registry → build `EmitParams` via the functional extractors → `client.Emit` fire-and-forget. Handler errors are never audited; emit errors are logged, never returned to the caller. This is orthogonal to the manual domain-port pattern above — use one, the other, or both.

## Error Handling

| Error | When | 
|-------|------|
| `auditlogclient.ErrUnknownEvent` | group/event not declared in the manifest |
| `auditlogclient.ValidationError` | manifest declares `Target` but `EmitParams.TargetID` is empty |
| `auditlogclient.ErrTenantNotSeeded` | `ModeAwait` with no `xctx.TenantID` in context |
| `auditlogclient.PublishError` | gRPC/NATS transport failure (wraps the underlying cause) |

In `ModeFireAndForget` (the default), transport/tenant failures are logged internally and `Emit` still returns `nil` — do not rely on the return value to detect delivery failure in the default mode.

## FX Module Requirements

| Dependency | Type | Required for |
|-----------|------|---------------|
| `logger.Logger` | devkit logger | Both transports |
| `*nats.JetStreamPublisher` | from `natsfx.Module` | NATS transport only |

Provides: `auditlogclient.Config`, `auditlogclient.Manifest`, `auditlogclient.Client`.

Shutdown: gRPC transport registers a `platformfx.MessagingHook`; NATS transport does not close the shared publisher (owned by `natsfx.Module`).

## Common Pitfalls

1. **NATS transport without `natsfx.Module` in the graph**: `auditlogclientfx.Module` with `transport: nats` needs `*nats.JetStreamPublisher`, which only exists if `natsfx.Module` (with JetStream enabled) is wired first. Missing it fails Fx construction.
2. **No tenant in context**: every emit requires `xctx.TenantID(ctx)`. If your gRPC interceptor chain doesn't seed tenant into context before handlers run, all audit emits will fail (or silently drop in fire-and-forget mode).
3. **Manifest/adapter drift**: `Emit(ctx, group, event, ...)` string keys must exactly match `Manifest` entries — a typo returns `ErrUnknownEvent` at runtime, not compile time. Add a small unit test asserting the manifest contains every group/event key referenced in your adapter.
4. **Using `New`/`NewWithLogger` for NATS transport**: those constructors only support `transport: grpc`. For NATS, use `NewWithNATSPublisher` directly, or let `auditlogclientfx.Module` pick the right constructor based on `Config.Transport`.
5. **Blocking on audit failures**: audit logging must never fail the primary business operation — always treat `Emit`/`Service` method errors as best-effort (log and continue).

## File Locations

When adding audit logging to a service, touch these files:

| File | Change |
|------|--------|
| `internal/services/auditlog/service.go` | Define the `Service` port + typed event structs |
| `internal/services/auditlog/manifest.go` | `auditlogclient.DefineEvents(...)` manifest |
| `internal/services/auditlog/client_adapter.go` | Adapter implementing `Service` via `auditlogclient.Client` |
| `internal/config/configuration.go` | Add `AuditLog auditlogclient.Config` field |
| `config/configuration.yaml` | Add `audit_log:` section |
| `internal/di/auditlog/module.go` | Fx wiring (`auditlogclientfx.Module` + adapter provider, optional fallback) |
| `internal/di/services/module.go` / `cmd/serve.go` | Include the audit module, after `natsdi`/`natsfx` for NATS transport |
| Handler/service call-sites | Inject the `Service` port, call typed methods best-effort |
