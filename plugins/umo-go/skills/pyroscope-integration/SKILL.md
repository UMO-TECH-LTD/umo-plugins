---
name: pyroscope-integration
description: Integrating Grafana Pyroscope continuous profiling into Go microservices using devkit/common/pyroscope package. Use when adding Pyroscope to a new or existing Go service, wiring pyroscopefx.Module with Uber Fx, setting up CPU/memory/goroutine profiling, using WrapWithLabels for per-handler profiling, adding per-endpoint gRPC profiling with pyroscope/grpc interceptors, or when the user asks about continuous profiling, Pyroscope, flame graphs, or runtime profiling in Go services.
---

# Pyroscope Integration for Go Microservices

## Overview

The `devkit/common/pyroscope` package provides a reusable Grafana Pyroscope continuous profiling integration for Go microservices. It wraps the official `github.com/grafana/pyroscope-go` SDK and follows devkit/common patterns: functional options, Uber Fx lifecycle management, environment-based configuration, and safe no-op behaviour when profiling is disabled.

**Module path:** `gitlab.com/umo-tech-ltd-group/platform/devkit/common/pyroscope`
**gRPC interceptor path:** `gitlab.com/umo-tech-ltd-group/platform/devkit/common/pyroscope/grpc`
**Fx module path:** `gitlab.com/umo-tech-ltd-group/platform/devkit/common/pyroscope/fx`
**Minimum devkit version:** `v0.20.0` (for gRPC interceptors)
**Reference integration:** `saas/services/compliance-chat` (also wired in `kyc-compliance`, `compliance-tickets`, `reference-data`, and other active Go services)

## Quick Setup Checklist

### 1. Add Config

> **Use `pyroscope.Config` from devkit/common directly.** Do NOT create a local `PyroscopeConfig` struct. The devkit type has `default` tags and implements `EnvBinder` for automatic `PYROSCOPE_*` env var binding.

In `internal/config/config.go`:

```go
import "gitlab.com/umo-tech-ltd-group/platform/devkit/common/pyroscope"

type Config struct {
    // ... other fields ...
    Pyroscope pyroscope.Config `mapstructure:"pyroscope"`
}
```

Propagate `ApplicationName` from the service name in `Load()` post-load:

```go
if cfg.Pyroscope.ApplicationName == "" {
    cfg.Pyroscope.ApplicationName = cfg.ServiceName
}
```

If using token auth, redact the token in `config.WithRedactKeys`:

```go
config.WithRedactKeys("pyroscope.auth_token", "pyroscope.basic_auth_password"),
```

### 2. Wire the Fx Module

In `cmd/run.go`:

```go
import pyroscopefx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/pyroscope/fx"

fxApp := fx.New(
    platformfx.Module(cfg.Platform),          // Required: provides shutdown manager
    loggerfx.ModuleWithOptions(cfg.Logger, ...), // Required: provides logger
    tracefx.Module(cfg.Trace),
    sentryfx.Module(cfg.Sentry),
    pyroscopefx.Module(cfg.Pyroscope),        // After sentry, before transport modules
    // ... DI modules ...
)
```

The module automatically registers a shutdown hook at priority 85 (before tracer at 90, before Sentry at 95).

**Module ordering requirements:**
- Must come after `platformfx.Module` — needs the shutdown manager
- Must come after `loggerfx` — needs a logger to report start/stop events

### 3. Add YAML Config

In your `configs/<env>.yaml`:

```yaml
pyroscope:
  enabled: false                  # Set to true in envs with Pyroscope deployed
  server_address: ""              # http://pyroscope:4040 — from PYROSCOPE_SERVER_ADDRESS
  application_name: ""            # Defaults to ServiceName in Load() post-load
  auth_token: ""                  # From PYROSCOPE_AUTH_TOKEN (for Grafana Cloud)
  basic_auth_user: ""             # From PYROSCOPE_BASIC_AUTH_USER
  basic_auth_password: ""         # From PYROSCOPE_BASIC_AUTH_PASSWORD
  tenant_id: ""                   # From PYROSCOPE_TENANT_ID (multi-tenant deployments)
  upload_rate: 15s                # Profile upload interval
  mutex_profile_fraction: 0       # Enable mutex profiling (set > 0, e.g. 5)
  block_profile_rate: 0           # Enable block profiling (set > 0, e.g. 1)
  tags: {}                        # Static labels attached to all profiles
```

### 4. Per-Endpoint gRPC Profiling (recommended)

The `pyroscope/grpc` package provides interceptors that automatically attach a `grpc.method` label to all profiles collected during each gRPC request. This enables per-endpoint flamegraph breakdown in the Pyroscope UI without modifying individual handlers.

In `internal/handlers/grpc/handler.go`:

```go
import (
    pyroscopegrpc "gitlab.com/umo-tech-ltd-group/platform/devkit/common/pyroscope/grpc"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/grpcserver"
)

skipHealthChecks := grpcserver.CombineSkippers(
    grpcserver.SkipHealthChecks(),
    grpcserver.SkipReflection(),
)

h.server = grpc.NewServer(
    grpc.ChainUnaryInterceptor(
        // ... Recovery, Tracing, Sentry, FeatureScript ...
        pyroscopegrpc.UnaryServerInterceptor(
            pyroscopegrpc.WithServerSkipper(skipHealthChecks),
        ),
        // ... Logging, Metrics, RequestID, Validation ...
    ),
    grpc.ChainStreamInterceptor(
        // ... Recovery, Tracing, Sentry, FeatureScript ...
        pyroscopegrpc.StreamServerInterceptor(
            pyroscopegrpc.WithServerSkipper(skipHealthChecks),
        ),
        // ... Logging, Metrics, Validation ...
    ),
)
```

**Interceptor placement:** After tracing/sentry (so spans and hubs are set up) and before logging/metrics (so those run inside the labeled context).

**Interceptor options:**

| Option | Description |
|--------|-------------|
| `WithServerSkipper(fn)` | Skip labeling for certain methods (e.g., health checks). Compatible with `grpcserver.SkipHealthChecks()`, `grpcserver.SkipReflection()`, `grpcserver.CombineSkippers()`. |
| `WithExtraLabels(map)` | Add static labels to every request (e.g., `{"service": "compliance-chat"}`). Merged with the automatic `grpc.method` label. |

### 5. Manual Per-Handler Profiling Labels (optional)

For non-gRPC code paths or when you need custom labels beyond `grpc.method`, use `WrapWithLabels` to annotate hot code paths:

```go
import "gitlab.com/umo-tech-ltd-group/platform/devkit/common/pyroscope"

func (h *Handler) CreateUser(ctx context.Context, req *pb.CreateUserRequest) (*pb.CreateUserResponse, error) {
    var resp *pb.CreateUserResponse
    pyroscope.WrapWithLabels(ctx, map[string]string{
        "handler": "CreateUser",
        "tenant":  req.GetTenantId(),
    }, func(ctx context.Context) {
        resp, err = h.svc.CreateUser(ctx, req)
    })
    return resp, err
}
```

If labels is `nil` or empty, `fn` is called directly without overhead. Safe to call unconditionally.

> **Prefer gRPC interceptors over manual `WrapWithLabels`** for gRPC services — the interceptor automatically covers all current and future endpoints with zero per-handler code.

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `PYROSCOPE_SERVER_ADDRESS` | Pyroscope server URL (e.g. `http://pyroscope:4040`) | Yes (when enabled) |
| `PYROSCOPE_APPLICATION_NAME` | Application name shown in Pyroscope UI | No (defaults to ServiceName) |
| `PYROSCOPE_AUTH_TOKEN` | Auth token for Grafana Cloud Profiles | No |
| `PYROSCOPE_BASIC_AUTH_USER` | Basic auth username | No |
| `PYROSCOPE_BASIC_AUTH_PASSWORD` | Basic auth password | No |
| `PYROSCOPE_TENANT_ID` | Tenant ID for multi-tenant deployments | No |

All bindings are automatic via `Config.EnvBindings` — no manual `BindEnv` calls needed.

## Default Profile Types

The following profile types are enabled by default:

| Profile Type | Description |
|-------------|-------------|
| `ProfileCPU` | CPU time consumed |
| `ProfileAllocObjects` | Number of objects allocated |
| `ProfileAllocSpace` | Bytes allocated |
| `ProfileInuseObjects` | Objects currently in use |
| `ProfileInuseSpace` | Bytes currently in use |

Additional types added automatically when configured:
- `ProfileMutexCount` + `ProfileMutexDuration` — when `mutex_profile_fraction > 0`
- `ProfileBlockCount` + `ProfileBlockDuration` — when `block_profile_rate > 0`

Override via `pyroscope.WithProfileTypes(...)` option passed to `pyroscopefx.Module`.

## Functional Options

Pass options as additional arguments to `pyroscopefx.Module`:

```go
import (
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/pyroscope"
    pyroscopefx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/pyroscope/fx"
    pyroscopesdk "github.com/grafana/pyroscope-go"
)

pyroscopefx.Module(cfg.Pyroscope,
    pyroscope.WithLogger(pyroscope.StandardLogger),        // SDK stdout logging
    pyroscope.WithHTTPHeaders(map[string]string{...}),     // Custom upload headers
    pyroscope.WithUploadRate(30 * time.Second),            // Override upload interval
    pyroscope.WithProfileTypes(                            // Override profile types
        pyroscopesdk.ProfileCPU,
        pyroscopesdk.ProfileInuseSpace,
    ),
    pyroscope.WithDisableGCRuns(),                         // Reduce profiling overhead
)
```

## Key Design Decisions

- **No-op safety:** `Enabled: false` or empty `ServerAddress` → profiler is a no-op. Service starts normally in local/dev without a Pyroscope server. No error is returned.
- **Shutdown priority 85:** Profiler stops before the tracer exporter (priority 90) and Sentry (priority 95), ensuring the final profile batch captures the complete request lifecycle including trace flush.
- **Credential redaction:** `Config.MarshalJSON` and `Config.String()` automatically redact `AuthToken`, `BasicAuthUser`, and `BasicAuthPassword`. Still add `WithRedactKeys` for token auth to protect config file logging.
- **No goroutine leak:** The SDK manages its own goroutine; `Stop()` is always called via the shutdown hook.

## Common Pitfalls

1. **Forgetting `ApplicationName` propagation:** If `cfg.Pyroscope.ApplicationName` is not set in config, all profiles appear under an empty app name in the Pyroscope UI. Always set it in `Load()` post-load from `cfg.ServiceName`.

2. **Module ordering:** `pyroscopefx.Module` requires both `platformfx.Module` (shutdown manager) and `loggerfx` (logger) to already be present in the Fx app. Placing it before these will cause an Fx wiring error.

3. **Missing credential redaction:** When using `auth_token` or `basic_auth_password`, add `"pyroscope.auth_token"` and `"pyroscope.basic_auth_password"` to `config.WithRedactKeys(...)`. The `Config` type redacts these in its `String()` / `MarshalJSON()`, but Viper's own config dump may not.

4. **`WrapWithLabels` is a no-op without a running profiler:** If the profiler is disabled, `WrapWithLabels` still calls `fn` directly — it's safe. But labels will not appear in the Pyroscope UI, so don't add complex label computation on hot paths without a profiler check.

5. **Mutex/block profiling runtime overhead:** `mutex_profile_fraction` and `block_profile_rate` call `runtime.SetMutexProfileFraction` and `runtime.SetBlockProfileRate` globally. Enable only in production environments where you need this data, not in load tests.

6. **Labels require sufficient traffic:** Profiling labels set via `pprof.Do` (used internally by `WrapWithLabels` and the gRPC interceptors) are goroutine-local. For labels to appear in the Pyroscope UI, enough profiling samples must be captured during the labeled context. Short gRPC calls with low traffic may not produce visible labeled samples — generate sustained traffic (30-60s) and check CPU profile type first (sampled at ~100Hz), then memory profiles.

7. **gRPC interceptor requires devkit >= v0.20.0:** The `pyroscope/grpc` package was introduced in devkit/common `v0.20.0`. Ensure `go.mod` references at least this version when adding gRPC interceptors.
