# Remote Config Go API Reference

Package: `gitlab.com/umo-tech-ltd-group/platform/devkit/common/config/remoteconfig`

## ConfigOption

Schema definition for a single config key:

```go
type ConfigOption struct {
    Value       any    // Default value (type determines env parsing)
    Mode        Mode   // Access mode flags (default: ModeRead | ModeWrite)
    Validate    string // go-playground/validator tag (e.g. "required,min=1,max=10")
    Group       string // Logical grouping (e.g. "infrastructure", "feature-flags")
    Description string // Human-readable documentation
}
```

## Mode Flags

Bitwise flags controlling access:

| Mode | Value | Behavior |
|------|-------|----------|
| `ModeLock` | 1 | Locked after initialization, not remotely updatable |
| `ModeRead` | 2 | Reads from env vars; env var is checked using the config key name |
| `ModeWrite` | 4 | Allows runtime updates via `Set()`, persisted to storage |

Combine with bitwise OR: `ModeRead | ModeWrite` (typical for tunable settings).

Helper methods: `mode.HasLock()`, `mode.HasRead()`, `mode.HasWrite()`.

## InternalConfig

Runtime state of a config key (returned by `GetConfig`, `GetAll`):

```go
type InternalConfig struct {
    Key         string
    Value       any
    Mode        Mode
    Type        string // "string", "int", "bool", "float64", "time"
    Description string
    Group       string
}
```

## ChangeEvent

Notification when a value changes:

```go
type ChangeEvent struct {
    Key      string
    OldValue any
    NewValue any
    Source   string // "env", "remote", "set", "reset"
}
```

## Service API

### Constructor

```go
func New(schema map[string]ConfigOption, opts ...Option) (*Service, error)
```

### Lifecycle

```go
func (s *Service) Start(ctx context.Context) error   // Performs initial sync, starts background goroutines
func (s *Service) Shutdown(ctx context.Context) error // Cancels goroutines, closes channels and storage
func (s *Service) Done() <-chan struct{}               // Closed when shutdown completes
func (s *Service) IsShutdown() bool
```

### Read

```go
func (s *Service) Get(key string) any                                    // Returns current value (nil if missing)
func (s *Service) GetConfig(key string) *InternalConfig                  // Returns full config (nil if missing)
func (s *Service) Has(key string) bool                                   // Checks existence
func (s *Service) GetAll(mode Mode, group string) map[string]*InternalConfig // Filter by mode/group (0/"" for all)
```

### Write

```go
func (s *Service) Set(ctx context.Context, key string, value any) error // Validates, updates cache and storage
func (s *Service) Reset(ctx context.Context) error                      // Resets to defaults, clears storage
func (s *Service) Clear(ctx context.Context) error                      // Removes all from cache and storage
func (s *Service) Sync(ctx context.Context) error                       // Manual sync with storage
```

### Change Notifications

```go
func (s *Service) OnChange() <-chan *ChangeEvent            // All changes (buffered, drops when full)
func (s *Service) OnChangeValue(key string) <-chan *ChangeEvent // Per-key changes (closed on Shutdown)
```

Channel buffer size defaults to 100. Events are dropped (non-blocking send) when the buffer is full -- consumers should process promptly or call `Get()` to read the latest value.

## Storage Interface

```go
type Storage interface {
    Size(ctx context.Context) (int, error)
    Get(ctx context.Context, key string) (*InternalConfig, error)
    Set(ctx context.Context, key string, value *InternalConfig) error
    SetMany(ctx context.Context, items map[string]*InternalConfig) error
    GetAll(ctx context.Context) (map[string]*InternalConfig, error)
    Delete(ctx context.Context, key string) error
    Clear(ctx context.Context) error
    Close() error
}
```

### Built-in Implementations

**MemoryStorage** -- in-memory, single-instance or testing:

```go
storage := remoteconfig.NewMemoryStorage()
```

**RedisStorage** -- Redis-backed, multi-instance production:

```go
// From config
storage, err := remoteconfig.NewRedisStorage(remoteconfig.RedisConfig{
    Addrs:     []string{"localhost:6379"},
    KeyPrefix: "myservice:remoteconfig:",
})

// From existing client (preferred when Redis client is already in FX container)
storage := remoteconfig.NewRedisStorageFromClient(redisClient, "myservice:remoteconfig:")
```

Redis key prefix convention: `<service-name>:remoteconfig:` (e.g. `core:remoteconfig:`).

## Functional Options

```go
remoteconfig.WithStorage(storage)           // Set backing storage
remoteconfig.WithLogger(log)                // Set logger
remoteconfig.WithTracer(tracer)             // Set tracer
remoteconfig.WithRefreshEnvInterval(10*time.Second) // Env polling interval (0 to disable)
remoteconfig.WithSyncStorageInterval(5*time.Second) // Storage sync interval (0 to disable)
remoteconfig.WithEnvRefresh(true)           // Enable/disable env polling
remoteconfig.WithVerbose(false)             // Enable verbose logging
remoteconfig.WithChannelBufferSize(100)     // Change channel buffer size
```

## Config (for YAML loading)

```go
type Config struct {
    Enabled             bool          `mapstructure:"enabled"`
    RefreshEnvInterval  time.Duration `mapstructure:"refresh_env_interval"`
    SyncStorageInterval time.Duration `mapstructure:"sync_storage_interval"`
    EnableEnvRefresh    bool          `mapstructure:"enable_env_refresh"`
    Verbose             bool          `mapstructure:"verbose"`
    Redis               RedisConfig   `mapstructure:"redis"`
}
```

YAML example:

```yaml
remote_config:
  enabled: true
  sync_storage_interval: "5s"
  refresh_env_interval: "10s"
  enable_env_refresh: true
  verbose: false
```

## FX Module

Package: `gitlab.com/umo-tech-ltd-group/platform/devkit/common/config/remoteconfig/fx`

### Module

`remoteconfigfx.Module` is an `fx.Module` that:
- Creates `*remoteconfig.Service` via `NewService`
- Registers a `platformfx.ShutdownHook` (priority 35)
- Registers an FX lifecycle hook to call `Start` on `OnStart`

**Required in FX container:** `map[string]remoteconfig.ConfigOption` (the schema).

**Optional in FX container:** `remoteconfig.Storage`, `logger.Logger`, `trace.Tracer`, `*remoteconfig.Config`.

**Provides:** `*remoteconfig.Service`.

### Helper Functions

```go
// Provide Redis storage from an existing redis.UniversalClient in the container
remoteconfigfx.ProvideRedisStorageFromClient("myservice:remoteconfig:")

// Provide Redis storage from a RedisConfig
remoteconfigfx.ProvideRedisStorage(redisCfg)

// Provide static storage instance
remoteconfigfx.ProvideStorage(memoryStorage)

// Provide YAML config as *remoteconfig.Config
remoteconfigfx.ProvideConfig(cfg.RemoteConfig)

// Provide additional functional options
remoteconfigfx.ProvideOption(remoteconfig.WithVerbose(true))
```

## gRPC Handler

Package: `gitlab.com/umo-tech-ltd-group/platform/devkit/common/config/remoteconfig/grpc`

Proto: `gitlab.com/umo-tech-ltd-group/platform/proto-api/gen/go/shared/remote-config/v1`

```go
import (
    ffrcpb "gitlab.com/umo-tech-ltd-group/platform/proto-api/gen/go/ff/remote_config"
    rcpb "gitlab.com/umo-tech-ltd-group/platform/proto-api/gen/go/shared/remote-config/v1"
    rcgrpc "gitlab.com/umo-tech-ltd-group/platform/devkit/common/config/remoteconfig/grpc"
)

rcHandler := rcgrpc.NewHandler(remoteConfigService)
rcpb.RegisterRemoteConfigServiceServer(grpcServer, rcHandler)
```

For backward compatibility with historical clients that call the legacy
`ff.remote_config.RemoteConfigService` path, register the generated legacy
proto service with a thin adapter. Do not mutate `ServiceDesc.ServiceName`:
that breaks gRPC reflection clients such as Postman because the listed symbol
has no proto descriptor.

```go
ffrcpb.RegisterRemoteConfigServiceServer(grpcServer, ffRemoteConfigAlias{inner: rcHandler})
```

The gRPC handler has its own FX module at `remoteconfig/grpc/fx`:

```go
import rcgrpcfx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/config/remoteconfig/grpc/fx"

// Add to fx.New()
rcgrpcfx.Module
```

## Value Resolution Priority

1. **Remote storage (Redis)** -- highest, always wins after sync
2. **Environment variables** -- if `ModeRead` is set and no remote value exists
3. **Default value** -- from `ConfigOption.Value` in the schema

## Validation

Uses `go-playground/validator/v10` tags in `ConfigOption.Validate`:

```go
"KAFKA_MAX_RETRIES": {
    Value:    3,
    Mode:     remoteconfig.ModeRead | remoteconfig.ModeWrite,
    Validate: "min=0,max=100",  // Validated on initialize and Set()
}
```

Validation runs on initialization (from schema defaults / env vars) and on every `Set()` call. If validation fails, `Set()` returns `ErrValidationFailed` and the value is not changed.
