---
name: remote-config
description: Understand and apply remote config patterns for Go and Node/Nest services. Go uses devkit/common/config/remoteconfig with Redis storage, schema-driven config, and FX integration. Node uses @ff/config with DIConfig, Joi validation, and RemoteConfigModule. Use when adding runtime-configurable settings, defining config schemas, wiring remote config with FX or NestJS, or debugging config-related issues.
---

# Remote Config

Remote config provides schema-driven, runtime-updatable configuration backed by Redis. Each service defines a config schema with typed keys, modes, validation rules, and groups. Values are synced from Redis every 5 seconds, with env-var fallback and change notifications.

## Go Services (`devkit/common/config/remoteconfig`)

Import path: `gitlab.com/umo-tech-ltd-group/platform/devkit/common/config/remoteconfig`

### Quick Setup Checklist

#### 1. Define Schema

Create `internal/remoteconfig/schema.go` returning the config schema:

```go
package remoteconfig

import "gitlab.com/umo-tech-ltd-group/platform/devkit/common/config/remoteconfig"

func Schema() map[string]remoteconfig.ConfigOption {
    return map[string]remoteconfig.ConfigOption{
        "KAFKA_MAX_RETRIES": {
            Value:       3,
            Mode:        remoteconfig.ModeRead | remoteconfig.ModeWrite,
            Validate:    "min=0,max=100",
            Group:       "infrastructure",
            Description: "Maximum Kafka consumer retry attempts",
        },
        "GRPC_CLIENT_TIMEOUT_MS": {
            Value:       30000,
            Mode:        remoteconfig.ModeRead | remoteconfig.ModeWrite,
            Validate:    "min=1000,max=120000",
            Group:       "infrastructure",
            Description: "Default gRPC client call timeout in milliseconds",
        },
    }
}
```

**Mode flags:**
- `ModeLock` -- env-only, not remotely updatable (secrets, static config)
- `ModeRead` -- readable at runtime, can fall back to env var
- `ModeWrite` -- allows runtime updates via gRPC API
- `ModeRead | ModeWrite` -- the typical combination for tunable settings

#### 2. Add Config

Embed `remoteconfig.Config` in the service config struct (`internal/config/config.go`):

```go
import "gitlab.com/umo-tech-ltd-group/platform/devkit/common/config/remoteconfig"

type Config struct {
    // ... existing fields ...
    RemoteConfig remoteconfig.Config `mapstructure:"remote_config"`
}
```

YAML config (`configs/local.yaml`):

```yaml
remote_config:
  sync_storage_interval: "5s"
  refresh_env_interval: "10s"
  env_refresh: true
  verbose: false
```

#### 3. Create Service-Local DI Module

Create `internal/di/remoteconfig/module.go`:

```go
package remoteconfig

import (
    "go.uber.org/fx"

    devkitrc "gitlab.com/umo-tech-ltd-group/platform/devkit/common/config/remoteconfig"
    remoteconfigfx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/config/remoteconfig/fx"

    corerc "your-service/internal/remoteconfig"
)

var Module = fx.Options(
    fx.Provide(func() map[string]devkitrc.ConfigOption {
        return corerc.Schema()
    }),
    remoteconfigfx.ProvideRedisStorageFromClient("myservice:remoteconfig:"),
    remoteconfigfx.Module,
)
```

The key prefix (`"myservice:remoteconfig:"`) namespaces Redis keys to avoid collisions.

#### 4. Wire in `cmd/run.go`

Add after the Redis module (remote config requires `redis.UniversalClient` in the FX container):

```go
import (
    remoteconfigfx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/config/remoteconfig/fx"
    diremoteconfig "your-service/internal/di/remoteconfig"
)

fxApp := fx.New(
    // ... infra modules ...

    diredis.Module,  // Redis client (required)

    remoteconfigfx.ProvideConfig(cfg.RemoteConfig),
    diremoteconfig.Module,

    // ... DI modules ...
)
```

#### 5. Register gRPC Handler

In the gRPC handler, register the `RemoteConfigService` so the backoffice UI can read/update config at runtime:

```go
import (
    ffrcpb "gitlab.com/umo-tech-ltd-group/platform/proto-api/gen/go/ff/remote_config"
    rcpb "gitlab.com/umo-tech-ltd-group/platform/proto-api/gen/go/shared/remote-config/v1"
    rcgrpc "gitlab.com/umo-tech-ltd-group/platform/devkit/common/config/remoteconfig/grpc"
)

func (h *Handler) registerServices() {
    // ... register domain services ...

    rcHandler := rcgrpc.NewHandler(h.remoteConfigSvc)
    rcpb.RegisterRemoteConfigServiceServer(h.server, rcHandler)
}
```

For backward compatibility with historical clients that call the legacy
`ff.remote_config.RemoteConfigService` path, register the generated legacy
proto service with a thin adapter. Do not mutate `ServiceDesc.ServiceName`:
that breaks gRPC reflection clients such as Postman because the listed symbol
has no proto descriptor.

```go
ffrcpb.RegisterRemoteConfigServiceServer(h.server, ffRemoteConfigAlias{inner: rcHandler})
```

#### 6. Use in Code

Inject `*remoteconfig.Service` and read values:

```go
type MyService struct {
    rc *remoteconfig.Service
}

func (s *MyService) DoWork(ctx context.Context) {
    maxRetries := s.rc.Get("KAFKA_MAX_RETRIES").(int)
    // ...
}
```

Subscribe to changes:

```go
go func() {
    for event := range s.rc.OnChange() {
        log.Info(ctx, "config changed",
            logger.String("key", event.Key),
            logger.Any("old", event.OldValue),
            logger.Any("new", event.NewValue),
        )
    }
}()
```

### Value Resolution Priority

1. **Remote storage (Redis)** -- highest priority
2. **Environment variables** -- if `ModeRead` is set
3. **Default value** -- from `ConfigOption.Value` in the schema

### File Locations (Go)

| File | Change |
|------|--------|
| `internal/remoteconfig/schema.go` | Define config schema (`map[string]ConfigOption`) |
| `internal/config/config.go` | Embed `remoteconfig.Config` with `mapstructure:"remote_config"` tag |
| `internal/di/remoteconfig/module.go` | FX module: provide schema, Redis storage, wire `remoteconfigfx.Module` |
| `cmd/run.go` | Add `remoteconfigfx.ProvideConfig(...)` and `diremoteconfig.Module` |
| `internal/handlers/grpc/handler.go` | Register `RemoteConfigServiceServer` gRPC handler |
| `configs/local.yaml` | Add `remote_config:` section |

---

## Node/Nest Services (`@ff/config`)

### Quick Start

When working on Node/Nest services that use `@ff/config`:

1. **Identify the config source**: check `services/<service>/src/config.ts` (or similar).
2. **Respect config modes**: `LOCK` values are env-only; `READ|WRITE` can be updated remotely.
3. **Keep seeds/dev defaults explicit**: seed values are ok for dev; do not force env for seed-only values.
4. **Validate with Joi**: every config entry should include a schema and sensible defaults.
5. **Use DIConfig**: inject `DIConfig` and access values via the Proxy (`this.config.MY_KEY`).

### Workflow

#### 1. Check config definition

- Locate the service config (`src/config.ts`).
- Verify each key has:
  - default `value`
  - `schema` (Joi)
  - `mod` (READ/WRITE/LOCK)

#### 2. Decide env vs remote

- **Env-only**: use `LOCK` for secrets and values that must be static.
- **Remote-configurable**: use `READ | WRITE` for values that can change at runtime.
- **Dev seeds**: keep constants in seed files unless explicitly required by prod.

#### 3. Use config in code

- Inject `DIConfig` into services.
- Prefer direct access via proxy for clarity:
  - `this.config.FEATURE_FLAG`

#### 4. Reload config safely

- Config updates are applied at runtime by the remote-config system.
- Confirm changes propagate without requiring service restarts.

### Examples

**Injecting config**
```ts
constructor(@Inject(DIConfig) private readonly config: Config) {}
```

**Accessing values**
```ts
const port = this.config.PORT;
const name = this.config.NAME;
```

## Additional Resources

- Node key concepts and access modes: [reference.md](reference.md)
- Go API reference (ConfigOption, Storage, Service, FX module, gRPC handler): [reference-go.md](reference-go.md)

## Out of scope

This skill covers Go (`devkit/.../remoteconfig`) and NestJS (`@ff/config`) only. For Bun + Effect services (`auditlog`, `exchange`, `fs`, …), use `@umo/*` config patterns in that service (see its `AGENTS.md`) — not `@ff/config`.
