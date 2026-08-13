---
name: featurescript-client
description: Integrating the FeatureScript feature flag client into Go microservices using devkit/common/featurescript. Use when adding feature flags to a Go service, checking feature toggle patterns, wiring FeatureScript with Uber FX, configuring gRPC interceptors for context propagation, or when the user asks about feature flags, feature toggles, or FeatureScript in Go services.
---

# FeatureScript Client for Go Microservices

## Overview

The `devkit/common/featurescript` package provides a Go client for the FeatureScript feature flag system. It evaluates a DSL-defined schema of contexts, predicates, and features against runtime data, enabling context-aware feature gating, probabilistic rollout, and cross-service context propagation via gRPC metadata.

Import path: `gitlab.com/umo-tech-ltd-group/platform/devkit/common/featurescript`

Key capabilities:
- DSL evaluation (contexts, predicates, features, `percent(N)`)
- gRPC context propagation via `x-featurescript-context` metadata
- Static feature overrides (dev/staging kill switches)
- Public feature filtering for API responses
- Resilient server-stream reconnection with exponential backoff
- Uber FX lifecycle integration

## Quick Setup Checklist

### 1. Add Config (devkit/common v0.17.0+)

> **Use `featurescript.Config` from devkit/common directly.** The devkit type has `default` tags for all fields. Do NOT call `v.BindEnv()` manually — env vars are auto-mapped from `mapstructure` tags (e.g., `FEATURESCRIPT_SERVER_ADDR`).

In `internal/config/config.go`:

```go
import "gitlab.com/umo-tech-ltd-group/platform/devkit/common/featurescript"

type Config struct {
    // ... existing fields ...
    FeatureScript featurescript.Config `mapstructure:"featurescript"`  // Value type
}
```

The `featurescript.Config` type already provides `default` tags for retry settings. No manual `v.BindEnv()` or `v.SetDefault()` calls needed — env vars like `FEATURESCRIPT_SERVER_ADDR` are auto-derived from the `mapstructure:"server_addr"` tag under the `featurescript` prefix.

Add service-specific overrides in `defaults()` only if needed:

```go
func defaults() map[string]any {
    return map[string]any{
        "featurescript.server_addr": "featurescript:5000",
    }
}
```

### 2. Create Service-Local DI Module

Create `internal/di/featurescript/module.go` that bundles the gRPC connection provider, the devkit FX module, and a shutdown hook for the connection:

```go
package featurescript

import (
    "context"

    "your-service/internal/config"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/featurescript"
    fsfx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/featurescript/fx"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"
    "go.uber.org/fx"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
)

func Module(cfg featurescript.Config) fx.Option {
    return fx.Options(
        fx.Provide(provideFSConnection),
        fsfx.Module(cfg),
        platformfx.ProvideShutdownHook(provideFSConnectionShutdownHook),
    )
}

func provideFSConnection(appCfg *config.Config, log logger.Logger) (*grpc.ClientConn, error) {
    addr := appCfg.FeatureScript.ServerAddr
    log.Info(context.Background(), "creating featurescript gRPC connection",
        logger.String("address", addr),
    )
    return grpc.NewClient(addr,
        grpc.WithTransportCredentials(insecure.NewCredentials()),
    )
}

// Priority 30: after servers (10) but before caches (40).
func provideFSConnectionShutdownHook(conn *grpc.ClientConn) platformfx.ShutdownHook {
    return platformfx.NewShutdownHook("featurescript-conn", 30, func(_ context.Context) error {
        if conn == nil {
            return nil
        }
        return conn.Close()
    })
}
```

### 3. Wire in `cmd/run.go`

With the service-local module from Step 2, `cmd/run.go` stays clean:

```go
import difeaturescript "your-service/internal/di/featurescript"

fxApp := fx.New(
    platformfx.Module(platformCfg),
    loggerfx.ModuleWithOptions(loggerCfg, ...),
    tracefx.Module(traceCfg),
    sentryfx.Module(sentryCfg),
    // ... other infra modules ...

    difeaturescript.Module(cfg.FeatureScript),  // After infra, before DI modules

    // DI modules
    diservices.Module,
    digrpc.Module,
)
```

The underlying FX module requires `*grpc.ClientConn` and `logger.Logger` in the container. It provides `*featurescript.Client` and starts/stops the client with the FX lifecycle.

### 4. Add gRPC Interceptors

Register interceptors for automatic FS context propagation. Position them after tracing and sentry interceptors:

**Server side** (in gRPC server setup):

```go
import "gitlab.com/umo-tech-ltd-group/platform/devkit/common/featurescript"

grpc.ChainUnaryInterceptor(
    recoveryInterceptor,                          // 1. Recovery
    tracegrpc.UnaryServerInterceptor(...),        // 2. Tracing
    sentrygrpc.UnaryServerInterceptor(...),       // 3. Sentry
    featurescript.UnaryServerInterceptor(),        // 4. FeatureScript
    loggingInterceptor,                           // 5. Logging
    // ...
),
grpc.ChainStreamInterceptor(
    // ... same order ...
    featurescript.StreamServerInterceptor(),
),
```

**Client side** (for outgoing calls to other services):

```go
grpc.WithChainUnaryInterceptor(
    featurescript.UnaryClientInterceptor(),
),
grpc.WithChainStreamInterceptor(
    featurescript.StreamClientInterceptor(),
),
```

The server interceptor extracts `x-featurescript-context` from incoming gRPC metadata and attaches it to the Go context. The client interceptor injects it into outgoing metadata.

### 5. Add YAML Config

> **YAML keys must match `mapstructure` tags** — underscore-separated.

In `configs/local.yaml` (or equivalent):

```yaml
featurescript:
  server_addr: "featurescript:50051"
  max_retry_attempts: 0    # 0 = infinite retries
  retry_delay: "1s"
  max_retry_delay: "30s"
  # Static overrides (optional):
  # features:
  #   maintenanceMode: true
  # public_features:
  #   - darkMode
  #   - gradualRollout
```

### 6. Inject and Use

Inject `*featurescript.Client` into services or handlers via FX:

```go
type PaymentHandler struct {
    fs *featurescript.Client
}

func NewPaymentHandler(fs *featurescript.Client) *PaymentHandler {
    return &PaymentHandler{fs: fs}
}
```

## Required Environment Variables

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `FEATURESCRIPT_SERVER_ADDR` | gRPC address of the FeatureScript server | Yes | (none) |
| `FEATURESCRIPT_MAX_RETRY_ATTEMPTS` | Max reconnection attempts (0 = infinite) | No | `0` |
| `FEATURESCRIPT_RETRY_DELAY` | Base delay between reconnects | No | `1s` |
| `FEATURESCRIPT_MAX_RETRY_DELAY` | Max delay between reconnects | No | `30s` |

**Alternative env var pattern:** Some deployment environments provide `SAAS_FS_GRPC_HOST` and `SAAS_FS_GRPC_PORT` separately instead of `FEATURESCRIPT_SERVER_ADDR`. Handle this in the config loader by composing the address after loading:

```go
if fsHost := os.Getenv("SAAS_FS_GRPC_HOST"); fsHost != "" {
    fsPort := os.Getenv("SAAS_FS_GRPC_PORT")
    if fsPort == "" {
        fsPort = "5000"
    }
    cfg.FeatureScript = cfg.FeatureScript.WithServerAddr(
        fmt.Sprintf("%s:%s", fsHost, fsPort))
}
```

## Context Propagation

FeatureScript evaluates features against a **context** -- a data shape defined in the DSL schema (e.g., `user.tier`, `request.channel`).

### Setting Context in the Entry Point

At the service boundary (e.g., HTTP gateway, first gRPC handler), attach the evaluation context:

```go
ctx := featurescript.WithContext(goCtx, map[string]any{
    "user": map[string]any{
        "id":      userID,
        "role":    userRole,
        "tier":    userTier,
        "country": userCountry,
    },
    "request": map[string]any{
        "ip":      clientIP,
        "channel": "api",
    },
})
```

### Struct Context (Alternative)

The evaluator resolves dotted identifiers via reflection. Use typed structs for compile-time safety:

```go
type EvalContext struct {
    User    UserCtx
    Request RequestCtx
}
type UserCtx struct {
    ID      int64
    Role    string
    Tier    string
    Country string
}
type RequestCtx struct {
    IP      string
    Channel string
}

ctx := featurescript.WithContext(goCtx, EvalContext{
    User:    UserCtx{ID: 42, Role: "admin", Tier: "premium", Country: "DE"},
    Request: RequestCtx{IP: "10.0.0.1", Channel: "api"},
})
```

Field matching is case-insensitive (`user.tier` matches `UserCtx.Tier`).

### Automatic Cross-Service Propagation

Once interceptors are registered (Step 4), the context propagates automatically:

1. Client interceptor serializes FS context as JSON into `x-featurescript-context` gRPC metadata
2. Server interceptor deserializes it and attaches to the Go context
3. Downstream handlers call `IsEnabled` -- context is already available

No manual wiring needed between services.

## Usage Patterns

### Feature Check in a gRPC Handler

```go
func (s *Server) CreatePayment(
    ctx context.Context,
    req *pb.CreatePaymentRequest,
) (*pb.CreatePaymentResponse, error) {
    if s.fs.IsEnabled("newCheckoutFlow", ctx) {
        return s.createPaymentV2(ctx, req)
    }
    return s.createPaymentLegacy(ctx, req)
}
```

### Public Features for API Responses

Expose only whitelisted features to external consumers:

```go
func (s *Server) GetConfig(
    ctx context.Context,
    _ *pb.GetConfigRequest,
) (*pb.GetConfigResponse, error) {
    features := s.fs.GetPublicFeatures(ctx)
    // features is map[string]bool filtered to public-safe flags.
    return &pb.GetConfigResponse{Flags: features}, nil
}
```

Configure which features are public in the config:

```go
cfg := featurescript.DefaultConfig().
    WithPublicFeatures([]string{"darkMode", "newUI", "gradualRollout"})
```

If `PublicFeatures` is empty, `GetPublicFeatures` returns all features.

### Static Overrides for Dev/Staging

Force features on or off via config. Static overrides always take precedence over the server-provided schema:

```go
cfg := featurescript.DefaultConfig().
    WithServerAddr("featurescript:50051").
    WithFeatures(map[string]bool{
        "maintenanceMode": true,   // Force maintenance on
        "betaDashboard":   false,  // Disable beta in staging
    })
```

Or via YAML:

```yaml
featurescript:
  server_addr: "featurescript:50051"
  features:
    maintenanceMode: true
    betaDashboard: false
```

### Batch Feature Evaluation

Evaluate all features at once instead of calling `IsEnabled` per feature:

```go
all := client.GetFeatures(ctx)
for name, enabled := range all {
    log.Info(ctx, "feature state", logger.String("feature", name), logger.Bool("enabled", enabled))
}
```

## FX Module Requirements

The `featurescript/fx` module expects these types in the FX container:

| Dependency | Type | Description |
|-----------|------|-------------|
| gRPC connection | `*grpc.ClientConn` | Connection to the FeatureScript server |
| Logger | `logger.Logger` | Structured logger from devkit |

It provides:

| Type | Description |
|------|-------------|
| `featurescript.Source` | gRPC-backed source with resilient streaming |
| `*featurescript.Client` | Main client (started on FX OnStart, stopped on OnStop) |

The module also registers a `platformfx.ShutdownHook` for graceful cleanup.

## Common Pitfalls

1. **Missing server interceptors**: Without `featurescript.UnaryServerInterceptor()`, the FS context from incoming gRPC metadata is never extracted. All `IsEnabled` calls will evaluate against a nil context (features default to `false`).

2. **No gRPC connection to FS server**: The FX module requires `*grpc.ClientConn` in the container. If the service doesn't already provide one, you must add a provider (see Step 3). Without it, the FX app will fail to start.

3. **Using `IsEnabled` before `Start` completes**: The client fetches the initial schema during `Start`. If you need to check features very early, wait on `client.Ready()`:
   ```go
   <-client.Ready()
   if client.IsEnabled("feature", ctx) { ... }
   ```
   In practice, FX lifecycle ordering handles this -- the client starts before handlers receive requests.

4. **Passing raw struct without `WithContext`**: The client extracts FS context from `context.Context` via `ContextFrom()`. If you pass a raw struct directly as the `ctx` argument to `IsEnabled`, it works (used as the eval context directly), but if you pass a `context.Context` without having called `WithContext`, the evaluator gets nil and all features evaluate to `false`.

5. **Client interceptor without server interceptor on the other end**: The client interceptor injects context into outgoing metadata, but the receiving service must have the server interceptor registered to extract it. Both sides must be configured.

## File Locations

When adding FeatureScript to a service, touch these files:

| File | Change |
|------|--------|
| `internal/config/config.go` | Add `FeatureScript featurescript.Config` field (value type, `mapstructure` tag). No manual `BindEnv` or `SetDefault` — devkit `default` tags handle it. Add `SAAS_FS_GRPC_HOST`/`PORT` composition if needed. |
| `internal/di/featurescript/module.go` | Create service-local DI module: gRPC connection provider, `fsfx.Module`, shutdown hook |
| `cmd/run.go` | Add `difeaturescript.Module(cfg.FeatureScript)` after infra modules |
| `internal/di/grpc/module.go` | Add server interceptors to the interceptor chain |
| `internal/di/clients/module.go` | Add client interceptors on outgoing connections |
| Handler/service files | Inject `*featurescript.Client`, call `IsEnabled`/`GetFeatures` |
| `configs/local.yaml` | Add `featurescript:` section (underscore-separated keys) |
