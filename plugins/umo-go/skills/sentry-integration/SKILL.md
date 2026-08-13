---
name: sentry-integration
description: Integrating Sentry error tracking into Go microservices using devkit/common/sentry package. Use when adding Sentry to a new service, debugging Sentry configuration, reviewing error tracking patterns, or when the user asks about Sentry, error tracking, or error reporting in Go services.
---

# Sentry Integration for Go Microservices

## Overview

The `devkit/common/sentry` package provides a reusable Sentry SDK integration for Go microservices. It wraps the official [sentry-go SDK](https://docs.sentry.io/platforms/go/) and follows devkit/common patterns: functional options, Uber Fx modules, gRPC interceptors, and context-aware helpers.

## Quick Setup Checklist

### 1. Add Config (devkit/common v0.17.0+)

> **Use `sentry.Config` from devkit/common directly.** Do NOT create a local `SentryConfig` struct or `ToCommonConfig()` conversion method. The devkit type has `default` tags and implements `EnvBinder` for automatic `SENTRY_*` env var discovery.

In `internal/config/config.go`:

```go
import "gitlab.com/umo-tech-ltd-group/platform/devkit/common/sentry"

type Config struct {
    // ... other fields ...
    Sentry sentry.Config `mapstructure:"sentry"`  // Value type, not pointer
}
```

The `sentry.Config` type already provides:
- `default` tags for all fields (sample rates, debug, etc.)
- `EnvBinder` interface that auto-binds `SENTRY_DSN`, `SENTRY_DEBUG`, `SENTRY_RELEASE`, `SENTRY_ENVIRONMENT`
- No manual `v.BindEnv()` or `v.SetDefault()` calls needed

Add service-specific defaults in `defaults()` only if overriding devkit defaults:

```go
func defaults() map[string]any {
    return map[string]any{
        "sentry.traces_sample_rate": 0.1,
    }
}
```

Propagate service identity in post-load:

```go
if cfg.Sentry.Environment == "" {
    cfg.Sentry.Environment = cfg.Environment
}
cfg.Sentry.ServerName = cfg.ServiceName
```

Redact DSN via `config.WithRedactKeys("sentry.dsn")` (contains auth token).

### 2. Wire Fx Module

In `cmd/run.go`:

```go
import sentryfx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/sentry/fx"

// Use cfg.Sentry directly — no conversion needed
fxApp := fx.New(
    platformfx.Module(cfg.Platform),
    loggerfx.ModuleWithOptions(cfg.Logger, ...),
    tracefx.Module(cfg.Trace),
    sentryfx.Module(cfg.Sentry),  // <-- direct use, no ToCommonConfig()
    // ... DI modules ...
)
```

### 3. Add gRPC Interceptors

In the gRPC handler:

```go
import sentrygrpc "gitlab.com/umo-tech-ltd-group/platform/devkit/common/sentry/grpc"

// Position: after Tracing (2), before Logging (4)
grpc.ChainUnaryInterceptor(
    grpcserver.RecoveryUnaryInterceptor(...),       // 1. Recovery
    tracegrpc.UnaryServerInterceptor(...),           // 2. Tracing
    sentrygrpc.UnaryServerInterceptor(               // 3. Sentry
        sentrygrpc.WithServerSkipper(skipHealthChecks),
    ),
    grpcserver.LoggingUnaryInterceptor(...),         // 4. Logging
    // ...
)
```

### 4. Add YAML Config

> **YAML keys must match `mapstructure` tags** — underscore-separated, not dot-separated.

```yaml
sentry:
  dsn: ""                  # From SENTRY_DSN env var (auto-bound via EnvBinder)
  debug: false
  sample_rate: 1.0
  enable_tracing: false
  traces_sample_rate: 0.1
  release: ""
```

## Required Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `SENTRY_DSN` | Project DSN (provided by DevOps) | Yes (empty = disabled) |
| `SENTRY_ENVIRONMENT` | Auto-read by SDK as fallback | No (use config) |
| `SENTRY_RELEASE` | Auto-read by SDK as fallback | No (use config or ldflags) |

## Manual Error Capture

Use context-aware helpers that auto-enrich with trace_id, tenant_id, request_id:

```go
import "gitlab.com/umo-tech-ltd-group/platform/devkit/common/sentry"

// Capture an error with full context
sentry.CaptureError(ctx, err)

// Capture a message
sentry.CaptureMessage(ctx, "unexpected state detected")
```

## Key Design Decisions

- **Graceful degradation**: Empty DSN = Sentry disabled, service runs normally
- **Hub cloning per request**: Proper scope isolation, no cross-request data leaks
- **Shutdown priority 95**: After tracer (90), before logger (100)
- **Default ReportOn**: Only codes.Internal, codes.Unknown, codes.DataLoss, codes.Unavailable
- **No PII by default**: `SendDefaultPII: false`

## Common Pitfalls

1. **Missing `sentry.Flush` on shutdown**: Always use the Fx module or call `sentry.Close(ctx)`. Without flush, buffered events are lost.
2. **Not cloning hub per request**: The global hub shares scope. Always clone in interceptors (the package does this automatically).
3. **Capturing too many error codes**: Don't capture NotFound/InvalidArgument/PermissionDenied -- they're expected behavior, not bugs.
4. **Forgetting DSN redaction**: The DSN contains an auth token. Always redact in `Sanitized()`.

## Detailed Reference

See `references/integration-patterns.md` for:
- Full config struct reference
- gRPC interceptor options
- Custom BeforeSend hooks
- Filtering patterns
- Testing with mock transport
