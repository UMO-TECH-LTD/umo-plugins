---
name: nats-events
description: Working with NATS events in Go microservices (publishing outbound domain events and subscribing to inbound integration events)
---

# NATS Events Skill

## Infrastructure Status

Deployed NATS uses JWT/Operator auth and TLS; services authenticate with `.creds` files injected by Vault (topology and cluster layout are owned by ops — see the service passport / current env, not this skill). Local development uses `nats://localhost:4222` with no auth.

## When to Use

- Publishing domain events (entity created/updated/deleted)
- Subscribing to integration events from other services
- Adding new event subjects or payloads
- Implementing event handlers

## Metadata Transport

**Metadata belongs in NATS message headers, not the body.** The `devkit/common/nats` package handles this automatically via `Publisher` and `Subscriber`. Business payload goes in the body only.

### Header Keys (from `devkit/common/nats`)

| Header | Source |
|--------|--------|
| `x-tenant-id` | `xctx.TenantID(ctx)` |
| `x-request-id` | `xctx.RequestID(ctx)` |
| `x-correlation-id` | `xctx.CorrelationID(ctx)` |
| `x-user-id` | `xctx.UserID(ctx)` |
| `x-trace-id` | OTel TraceID |
| `x-span-id` | OTel SpanID |
| `x-source` | `serviceName` arg |
| `x-timestamp` | `time.Now().UTC()` RFC3339Nano |

## Connection & Authentication

All Go services use the `devkit/common/nats` package for NATS connectivity.

### FX Module Usage

```go
import (
    devkitnats "gitlab.com/umo-tech-ltd-group/platform/devkit/common/nats"
    natsfx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/nats/fx"
)

// In your service DI module — provides *nats.Publisher and *nats.Subscriber.
func NewModule(cfg devkitnats.Config) fx.Option {
    if !cfg.Enabled {
        return fx.Options()
    }
    return fx.Options(
        natsfx.Module(cfg, "my-service"), // second arg = x-source header value
        fx.Invoke(RegisterSubscriptions),
    )
}
```

### Logger Bridging (services with raw *zap.Logger)

If your service uses a raw `*zap.Logger` (not yet migrated to `loggerfx.Module`), wrap it with
`zaplogger.NewFromZap` before passing to devkit NATS constructors.
Do NOT hand-roll a custom adapter — devkit's `Adapter` already implements this.

```go
import zaplogger "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger/zap"

log := zaplogger.NewFromZap(zapLog) // satisfies logger.Logger
conn, err := devkitnats.NewConn(natsCfg, log)
pub := devkitnats.NewPublisher(conn, log, "my-service")
```

Options such as `WithOTelTracing()` and `WithContextValues()` can be passed as additional arguments
if you want richer context in the wrapped logger.

### Environment Variables

All variables come from `services/.env` (shared) and `services/<svc>/deploy/env/.env` (service-specific). See `docs/reference/common-config.md` for the full canonical reference — do **not** duplicate shared vars in passports.

| Variable | Local | Deployed | Notes |
|----------|-------|----------|-------|
| `NATS_ENABLED` | `false` | `true` | Disables NATS when set to `false`; skip module when disabled |
| `NATS_URL` | `nats://15.0.0.74:4222,nats://15.0.0.75:4222,nats://15.0.0.76:4222` | `tls://nats.nats-system.svc.cluster.local:4222` | Multi-URL list supported; scheme switches to `tls://` in deployed env |
| `NATS_CREDS` | _(empty)_ | `/etc/nats/creds/service.creds` | Path to `.creds` file for JWT/Operator auth (Vault-injected) |
| `NATS_CA` | _(empty)_ | `/etc/nats/certs/ca.crt` | Path to CA cert for TLS verification (Vault-injected) |
| `NATS_CA_CERT` | _(empty)_ | _(PEM content)_ | **Inline** CA cert PEM — takes priority over `NATS_CA` when set |
| `NATS_CREDS_CONTENT` | _(empty)_ | _(.creds content)_ | **Inline** `.creds` file content — takes priority over `NATS_CREDS` when set |
| `NATS_MAX_RECONNECTS` | `-1` | `-1` | Reconnection attempts; `-1` = infinite (recommended) |
| `NATS_RECONNECT_WAIT` | `2s` | `2s` | Wait between reconnection attempts |
| `NATS_CONNECT_TIMEOUT` | `5s` | `5s` | Initial connection timeout |
| `NATS_DRAIN_TIMEOUT` | `30s` | `30s` | Graceful drain timeout on shutdown |
| `NATS_JETSTREAM_ENABLED` | `true` | `true` | Enable JetStream for persistent/durable messaging |

### Service-Specific Metrics (connection status)

```go
natsfx.ProvideConnOption(func() devkitnats.ConnOption {
    return devkitnats.WithConnOptions(
        natsclient.DisconnectErrHandler(func(_ *natsclient.Conn, _ error) {
            metrics.NatsConnectionStatus.Set(0)
        }),
        natsclient.ReconnectHandler(func(_ *natsclient.Conn) {
            metrics.NatsConnectionStatus.Set(1)
        }),
    )
})
```

## Subject Naming Convention

Format: `{domain}.{entity}.{action}`

Examples:
- Outbound: `compliance_chat.message.created`, `compliance_tickets.ticket.updated`
- Inbound: `platform.users.deleted`, `accounting.invoice.created`

Define in `internal/nats/subjects.go`:

```go
const (
    SubjectMessageCreated = "compliance_chat.message.created"
)
```

## Publishing Outbound Events

### Step 1: Define Payload

Add to `internal/core/event/{entity}_payloads.go`:

```go
package event

type OrderPayload struct {
    ID        string `json:"id"`
    TenantID  string `json:"tenant_id"`
    CreatedAt string `json:"created_at"`
}
```

### Step 2: Publish from Service/Repository

Inject `*nats.Publisher` (provided by FX module) and call `Publish`:

```go
import (
    natsclient "github.com/nats-io/nats.go"
    devkitnats "gitlab.com/umo-tech-ltd-group/platform/devkit/common/nats"
    intnats "my-service/internal/nats"
)

func (r *Repo) CreateOrder(ctx context.Context, order *domain.Order) error {
    if err := r.db.Insert(ctx, order); err != nil {
        return fmt.Errorf("insert order: %w", err)
    }

    payload := event.OrderPayload{
        ID:        order.ID,
        TenantID:  order.TenantID,
        CreatedAt: order.CreatedAt.Format(time.RFC3339Nano),
    }

    // Async: don't block/fail the DB write.
    go func() {
        if err := r.pub.Publish(context.Background(), intnats.SubjectOrderCreated, payload); err != nil {
            r.log.Error(ctx, "nats: publish order.created failed", logger.Err(err))
        }
    }()

    return nil
}
```

Metadata (tenant, trace, request ID, user ID, timestamp, source) is automatically written to headers — no manual metadata struct needed.

### With Extra Headers (e.g., Centrifugo)

```go
extra := make(natsclient.Header)
extra.Set("X-Centrifugo-Publish", "true")
extra.Set("X-Centrifugo-Channel", fmt.Sprintf("channel:%s", id))

if err := pub.Publish(ctx, subject, payload,
    devkitnats.WithExtraHeaders(extra),
); err != nil {
    return err
}
```

## Subscribing to Inbound Events

### Step 1: Define Payload

```go
type ExternalOrderPayload struct {
    ID     string `json:"id"`
    Status string `json:"status"`
}
```

### Step 2: Create Handler

```go
type OrderCreatedHandler struct {
    service order.Service
    log     logger.Logger
}

func (h *OrderCreatedHandler) Handle(ctx context.Context, payload event.ExternalOrderPayload, msg *natsclient.Msg) error {
    tenantID, ok := xctx.TenantID(ctx) // extracted from x-tenant-id header
    if !ok || tenantID == "" {
        return fmt.Errorf("%w: missing tenant", nats.ErrInvalidPayload)
    }

    if err := h.service.Process(ctx, tenantID, payload.ID); err != nil {
        h.log.Error(ctx, "failed to process order", logger.Err(err))
        return fmt.Errorf("process order: %w", err)
    }
    return nil
}
```

### Step 3: Register Subscription

```go
func RegisterSubscriptions(sub *devkitnats.Subscriber, h *natshandlers.OrderCreatedHandler) error {
    return devkitnats.SubscribeJSON(sub, intnats.SubjectOrderCreated, h.Handle)
}
```

For queue groups:

```go
return devkitnats.SubscribeQueueJSON(sub, intnats.SubjectOrderCreated, "workers", h.Handle)
```

## File Structure

```
internal/
├── core/event/
│   ├── {entity}_payloads.go  # Outbound event payloads
│   └── errors.go             # Domain-level event errors (ErrInvalidTenantID etc.)
├── nats/
│   └── subjects.go           # Subject constants
├── di/nats/
│   └── module.go             # RegisterSubscriptions invoked via FX
└── handlers/nats/
    └── {event}_handler.go    # Inbound event handlers
```

> **Removed:** `internal/core/event/event.go` (Event[T], Metadata structs) and per-service `publisher.go` / `subscriber.go` — these are now in `devkit/common/nats`.

## Error Handling

Return `fmt.Errorf("%w: ...", nats.ErrInvalidPayload)` for data errors (logged at WARN, not ERROR). Return any other error for infrastructure/business errors (logged at ERROR).

```go
var (
    ErrInvalidTenantID = errors.New("invalid tenant id")
    ErrMissingPayload  = errors.New("missing payload")
)
```

## Observability

NATS operations are automatically instrumented by `devkit/common/nats`:

- **Tracing**: OTel producer/consumer spans with `nats.subject`, `nats.payload_size` attributes
- **Logging**: Publish/receive/error at DEBUG/WARN/ERROR level with subject and duration
- **Context**: Tenant ID, request ID, trace ID extracted into every handler's context

Add business metrics per domain:

```go
var OrderEventsTotal = prometheus.NewCounterVec(
    prometheus.CounterOpts{Namespace: "myservice", Subsystem: "business", Name: "order_events_total"},
    []string{"action", "result"},
)
// In handler: metrics.OrderEventsTotal.WithLabelValues("created", "success").Inc()
```

## Migration from Legacy Body-Envelope Pattern

Services that previously used `Event[T]` + `Metadata` in the body are being migrated. During the transition:

- New `devkit` `Subscriber` handles messages from **both** old (no headers) and new (headers) publishers gracefully — if headers are absent, context is empty but the handler still runs.
- Old `Event[T]` wrapper must be removed from payload structs once all publishers are updated.

Migration order: `statistic` → `compliance-tickets` → `compliance-chat`.

## Checklist: Adding a New Event

### Publishing
- [ ] Define payload struct in `internal/core/event/`
- [ ] Add subject constant to `internal/nats/subjects.go`
- [ ] Call `pub.Publish(ctx, subject, payload)` in service/repository
- [ ] Add business metrics for publish success/failure
- [ ] Add unit tests for payload mapping

### Subscribing
- [ ] Define external payload in `internal/core/event/`
- [ ] Create handler in `internal/handlers/nats/`
- [ ] Register with `devkitnats.SubscribeJSON` (or `SubscribeQueueJSON`) in DI module
- [ ] Use `xctx.TenantID(ctx)` — do not read from payload metadata
- [ ] Add business metrics for handler
- [ ] Add unit tests with valid/invalid payloads

## Onboarding a New Service

1. Request NATS access from DevOps (provide subject list).
2. Add `natsfx.Module(cfg.Nats, "service-name")` to FX app — provides `*nats.Publisher` and `*nats.Subscriber`.
3. Define subjects in `internal/nats/subjects.go`.
4. Local docker-compose: `nats://localhost:4222`, no auth.
5. Set `nats.name` in service `defaults()` for connection visibility.
