---
name: go-service-architect
description: Expert guidance for creating new Go microservices or refactoring existing ones following the Hexagonal Architecture standard. Use when the user wants to create a new service, refactor an existing service, understand service architecture, implement CRUD operations for a domain, set up dependency injection, add observability, add Temporal workflows/activities, or asks about service templates. Triggers on requests like "create a new service", "refactor service", "add a domain", "implement user service", "set up tracing", "add Temporal workflow", "add workflow orchestration".
---

# Go Service Architect

Expert agent for building production-ready Go microservices following the Hexagonal Architecture standard, using devkit/common library for bootstrapping and observability.

## Overview

This skill helps developers:
- Create new microservices from scratch using devkit/common
- Refactor existing services to follow the standard architecture
- Implement new domains/features within existing services
- Set up proper dependency injection with Uber Fx modules
- Configure observability using devkit/common (logging, tracing, metrics)
- Add Temporal workflow orchestration using devkit/common/temporal

## Quick Reference

### Architecture Layers

```
Handlers (Transport) → Services (Business) → Application (Domain)
                              ↓
                      Repositories → External Clients
```

### Directory Structure

```
service/
├── cmd/
│   ├── root.go           # CLI setup (Cobra)
│   ├── serve.go          # Combined HTTP+gRPC command
│   ├── http.go           # HTTP-only command
│   └── grpc.go           # gRPC-only command
├── internal/
│   ├── config/
│   │   └── configuration.go  # Uses devkit/common/config
│   ├── di/                   # Fx DI modules
│   │   ├── http/module.go
│   │   ├── grpc/module.go
│   │   ├── postgres/module.go
│   │   ├── nats/module.go       # Preferred messaging
│   │   └── temporal/module.go   # Registrar constructors (if using Temporal)
│   ├── core/                 # Domain layer (NO external deps)
│   │   └── <domain>/
│   │       ├── <entity>.go   # Domain entity
│   │       ├── <role>.go     # Enums/value objects
│   │       └── errors.go     # Domain-specific errors
│   ├── services/             # Service layer (business logic)
│   │   └── <domain>/
│   │       ├── service.go    # Service interface (port)
│   │       ├── default.go    # Business logic implementation
│   │       └── instrumented.go # Observability wrapper (devkit/common)
│   ├── repo/                 # Repository layer
│   │   ├── repo.go           # Repository interface (port)
│   │   ├── root.go           # Root repository (composition)
│   │   ├── postgres/         # PostgreSQL implementations
│   │   └── instrumentation.go
│   ├── orchestration/        # Temporal orchestration (if using Temporal)
│   │   ├── workflows/
│   │   │   └── <domain>/
│   │   │       ├── types.go          # Versioned input/output structs
│   │   │       ├── workflow.go       # Workflow functions (deterministic)
│   │   │       └── workflow_test.go  # Replay + unit tests
│   │   └── activities/
│   │       └── <domain>/
│   │           ├── types.go          # Input/output structs
│   │           ├── activities.go     # Activity struct with methods
│   │           └── activities_test.go
│   ├── handlers/             # Transport layer
│   │   ├── grpc/             # gRPC handlers
│   │   └── http/             # HTTP handlers + middleware
│   ├── clients/              # External service clients (3-file pattern)
│   │   └── <service-name>/
│   │       ├── client.go         # Interface definition
│   │       ├── default_client.go # gRPC implementation
│   │       └── instrumented.go   # Observability wrapper
│   └── publisher/            # Event publishers (3-file pattern) — prefer NATS
│       ├── publisher.go          # Interface definition
│       ├── instrumented.go       # Observability wrapper
│       └── nats/
│           └── publisher.go      # NATS JetStream implementation
└── test/                    # Integration & E2E tests
```

> **Proto definitions:** live in the centralized `proto-api` repository. New services consume `gitlab.com/umo-tech-ltd-group/platform/proto-api/gen/go` — do not add local `api/protobuf/` codegen. See the `proto-api-migration` skill.
>
> **Messaging:** prefer NATS + JetStream (`nats-events` skill). Kafka in `devkit/common/kafka` is **deprecated** — only for maintaining legacy publishers.

### Three-File Pattern (Services, Repos, Clients)

| File | Purpose |
|------|---------|
| `service.go` | Interface DEFINITION (not type alias) |
| `default.go` | Business logic implementation |
| `instrumented.go` | Observability wrapper using devkit/common |

**Example structure:**
```
internal/services/counterparty/
├── service.go       # Interface defined directly here
├── default.go       # DefaultService implementation
├── default_test.go  # Unit tests
└── instrumented.go  # InstrumentedService wrapper
```

## Bootstrap Pattern (devkit/common)

All services bootstrap using devkit/common Fx modules. This is the standard pattern:

```go
// cmd/serve.go
import (
    "go.uber.org/fx"
    loggerfx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger/fx"
    zaplogger "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger/zap"
    tracefx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace/fx"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"
    _ "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/otel"  // OTel backend
)

func runServeService() {
    // Load configuration first
    cfg, meta, err := config.Load()
    if err != nil {
        fmt.Fprintf(os.Stderr, "Failed to load config: %v\n", err)
        os.Exit(1)
    }

    app := fx.New(
        // 1. Fx internal logger (OPTIONAL but recommended)
        loggerfx.WithFxLoggerFromConfig(cfg.Logger),

        // 2. Core platform module (ALWAYS FIRST)
        // Provides shutdown.Manager with priority-based hook collection
        platformfx.Module(cfg.Platform),

        // 3. Logger module with OTel integration
        // Auto-adds trace_id, span_id, tenant_id, request_id to logs
        loggerfx.ModuleWithOptions(cfg.Logger,
            zaplogger.WithOTelTracing(),
            zaplogger.WithContextValues(),
        ),

        // 4. Trace module (distributed tracing)
        tracefx.Module(cfg.Trace),

        // 5. Provide configuration
        fx.Provide(func() *config.Configuration { return cfg }),

        // 6. Infrastructure modules
        postgres.Module,     // Database
        // nats.Module,      // NATS + JetStream (preferred for new services)
        // redis.Module,     // Redis caching (if needed)
        // sentryfx.Module,  // Error tracking (if needed)
        // pyroscopefx.Module, // Continuous profiling (if needed)

        // 7. Transport modules (HTTP/gRPC)
        http.Module,
        grpc.Module,

        // 8. Application lifecycle
        fx.Invoke(registerServiceLifecycle),
    )

    app.Run()
}
```

### Module Order (Critical)

1. `platformfx.Module` - Always first (provides shutdown manager)
2. `loggerfx.ModuleWithOptions` - Logger with OTel integration
3. `tracefx.Module` - Distributed tracing
4. Infrastructure modules (database, cache, message queue)
5. Transport modules (HTTP, gRPC) - Always last

### Conditional Module Inclusion

Not all services need all modules. Include only what your service uses:

| If service uses... | Include module | Skip if not used |
|--------------------|----------------|------------------|
| HTTP handlers      | `http.Module`  | gRPC-only services |
| gRPC handlers      | `grpc.Module`  | HTTP-only services |
| NATS events        | `natsfx.Module` | No event publishing/consuming |
| Redis caching      | `redis.Module` | No caching requirements |
| Temporal workflows | `temporalfx.Module` | No workflow orchestration |
| Error tracking     | `sentryfx.Module` | No Sentry integration |
| Profiling          | `pyroscopefx.Module` | No continuous profiling |
| Feature flags      | `featurescriptfx.Module` | No feature flag evaluation |
| Kafka events (legacy) | `kafka.Module` | **Deprecated** — prefer NATS for new services |

**Note**: Even gRPC-only services often keep a minimal HTTP infra server for `/health`, `/metrics`, and `/ready` endpoints. This is the recommended pattern.

## DI Module Pattern

Each infrastructure component is an Fx module in `internal/di/`:

```go
// internal/di/grpc/module.go
package grpc

import (
    "context"
    "go.uber.org/fx"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"
    
    grpchandler "your-service/internal/handlers/grpc"
    "your-service/internal/services/counterparty"
)

var Module = fx.Module("grpc",
    // Provide dependencies
    fx.Provide(NewHandler),
    
    // Lifecycle hooks (OnStart ONLY)
    fx.Invoke(StartHandler),
    
    // Shutdown hooks with priority (SEPARATE from OnStart)
    platformfx.ProvideShutdownHook(NewHandlerShutdownHook),
)

func NewHandler(counterpartySvc counterparty.Service) *grpchandler.Handler {
    return grpchandler.NewHandler(counterpartySvc)
}

// StartHandler registers ONLY the OnStart hook.
func StartHandler(lc fx.Lifecycle, handler *grpchandler.Handler) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            return handler.Start(ctx)
        },
        // NO OnStop here - handled by shutdown hook!
    })
}

// NewHandlerShutdownHook creates a shutdown hook with server priority.
func NewHandlerShutdownHook(handler *grpchandler.Handler) platformfx.ShutdownHook {
    return platformfx.ServerHook("grpc-server", handler.Stop)
}
```

> **Key Pattern**: Always separate startup (`fx.Invoke`) from shutdown (`platformfx.ProvideShutdownHook`). This ensures proper priority ordering during shutdown. See `references/shutdown-patterns.md` for complete guidance.

### Shutdown Hook Priorities

Use `platformfx.ProvideShutdownHook()` for proper ordering (lower = shutdown first):

| Priority | Constant | Component |
|----------|----------|-----------|
| 10 | `PriorityServer` | HTTP/gRPC servers |
| 20 | `PriorityWorker` | Background workers |
| 40 | `PriorityCache` | Redis, caches |
| 60 | `PriorityDatabase` | Database connections, Temporal clients |
| 90 | `PriorityTracer` | Tracing exporters |
| 100 | `PriorityLogger` | Logger (last) |

```go
// For servers (HTTP, gRPC) - uses PriorityServer (10)
func NewGRPCShutdownHook(handler *Handler) platformfx.ShutdownHook {
    return platformfx.ServerHook("grpc-server", handler.Stop)
}

// For databases - uses PriorityDatabase (60)
func NewDBShutdownHook(db *sql.DB) platformfx.ShutdownHook {
    return platformfx.DatabaseHook("postgres-db", func(ctx context.Context) error {
        return db.Close()
    })
}
```

> **Important**: For comprehensive shutdown patterns including database, Temporal, Kafka, and more, see `references/shutdown-patterns.md`.

## Instrumentation (devkit/common)

> **REQUIRED PATTERN**: All instrumented wrappers MUST use `trace.Instrument(ctx, method)` for automatic span creation. Do NOT use `trace.Start(ctx, "manual.name")` - it is error-prone, lacks code location attributes, and is considered deprecated for service/repository instrumentation.

Use devkit/common observability packages for instrumentation wrappers:

```go
// internal/services/user/instrumented.go
package users

import (
    "context"
    "time"
    
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace"
    
    "your-service/internal/core/user"
)

type InstrumentedService struct {
    inner *DefaultService
    log   logger.Logger
}

func NewInstrumentedService(s *DefaultService, log logger.Logger) *InstrumentedService {
    return &InstrumentedService{
        inner: s,
        log:   log.Named("user.service"),
    }
}

func (s *InstrumentedService) CreateUser(ctx context.Context, id, email, name string) (*user.User, error) {
    start := time.Now()
    
    // Automatic span creation from method reference
    ctx, span := trace.Instrument(ctx, s.inner.CreateUser)
    defer span.End()

    // Add business-specific attributes
    span.SetAttributes(
        trace.String("user.id", id),
        trace.String("user.email", email),
    )

    // Log with auto-enriched context (trace_id, span_id, tenant_id, request_id)
    s.log.Info(ctx, "creating user",
        logger.String("id", id),
        logger.String("email", email),
    )

    // Call inner service
    result, err := s.inner.CreateUser(ctx, id, email, name)

    // Record duration
    span.SetAttributes(trace.Float64("duration_seconds", time.Since(start).Seconds()))

    if err != nil {
        span.RecordError(err)
        span.SetStatus(trace.StatusError, "failed to create user")
        s.log.Error(ctx, "failed to create user",
            logger.Err(err),
            logger.Duration("duration", time.Since(start)),
        )
        return nil, err
    }

    span.SetStatus(trace.StatusOK, "user created")
    s.log.Info(ctx, "user created successfully",
        logger.String("id", id),
        logger.Duration("duration", time.Since(start)),
    )

    return result, nil
}
```

## gRPC Server (devkit/common)

Use devkit/common grpcserver with standard interceptor chain:

```go
// internal/di/grpc/module.go (or internal/handlers/grpc/server.go)
import (
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/grpcerr"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/grpcserver"
    tracegrpc "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace/grpc"
)

func NewGRPCServer(cfg *config.Configuration, log logger.Logger) (*grpc.Server, error) {
    // Build interceptor chain (order matters - outermost first)
    unaryInterceptors := []grpc.UnaryServerInterceptor{
        // 1. Tracing - creates server span, extracts trace context
        tracegrpc.UnaryServerInterceptor(
            tracegrpc.WithServerSkipper(tracegrpc.SkipHealthChecks()),
        ),
        // 2. Request ID - extracts from metadata or generates UUID
        grpcserver.RequestIDUnaryInterceptor(),
        // 3. Logging - logs requests with method, duration, status
        grpcserver.LoggingUnaryInterceptor(
            grpcserver.WithLoggingLogger(log),
            grpcserver.WithLoggingSkipper(grpcserver.SkipHealthChecks()),
        ),
        // 4. Metrics - Prometheus metrics
        grpcserver.MetricsUnaryInterceptor(
            grpcserver.WithMetricsSkipper(grpcserver.SkipHealthChecks()),
        ),
        // 5. Recovery - recovers from panics
        grpcserver.RecoveryUnaryInterceptor(
            grpcserver.WithRecoveryLogger(log),
        ),
        // 6. Error Mapping - converts domain errors to gRPC status
        grpcerr.MappingUnaryInterceptor(),
        // 7. Validation - validates requests
        grpcserver.ValidationUnaryInterceptor(),
    }

    builder := grpcserver.NewBuilder(cfg.GRPC).
        WithUnaryInterceptors(unaryInterceptors...).
        WithHealthCheck(false).   // Register manually
        WithReflection(false)     // Based on config

    return builder.Build()
}
```

## HTTP Server (devkit/common)

Use devkit/common http server builder:

```go
// internal/di/http/module.go (or internal/handlers/http/server.go)
import (
    commonhttp "gitlab.com/umo-tech-ltd-group/platform/devkit/common/http"
    tracehttp "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace/http"
)

func NewHTTPServer(cfg *config.Configuration, engine *gin.Engine, log logger.Logger) *http.Server {
    return commonhttp.NewServerBuilder().
        WithAddr(cfg.HTTP.Addr).
        WithEngine(engine).
        WithReadTimeout(cfg.HTTP.ReadTimeout).
        WithWriteTimeout(cfg.HTTP.WriteTimeout).
        WithShutdownTimeout(cfg.HTTP.ShutdownTimeout).
        Build()
}

func NewGinEngine(log logger.Logger) *gin.Engine {
    gin.SetMode(gin.ReleaseMode)
    engine := gin.New()
    
    // Middleware chain (order matters - REQUIRED middleware marked)
    engine.Use(
        commonhttp.RecoveryMiddleware(log),       // 1. Panic recovery (REQUIRED)
        tracehttp.TracingMiddleware(              // 2. OpenTelemetry spans (REQUIRED)
            tracehttp.WithSkipper(tracehttp.SkipHealthChecks()),
            tracehttp.WithTraceIDHeader("X-Trace-Id"),
        ),
        contextEnrichmentMiddleware(),            // 3. request_id, tenant_id, user_id
        commonhttp.LoggerMiddleware(log),         // 4. Request logging (REQUIRED)
        commonhttp.MetricsMiddleware(             // 5. HTTP metrics (REQUIRED)
            commonhttp.WithExcludePaths("/health", "/ready", "/metrics"),
        ),
        commonhttp.CORSMiddleware(                // 6. CORS (configure as needed)
            []string{"*"},
            []string{"GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"},
            []string{"Origin", "Content-Type", "Accept", "Authorization"},
        ),
    )
    
    return engine
}
```

## Configuration (devkit/common) — MANDATORY PATTERN

> **All Go services MUST use `config.Load[T]()` from `devkit/common/config` (v0.17.0+).** Manual Viper setup, `v.SetDefault()`, `v.BindEnv()` calls, and hand-rolled config loaders are legacy patterns that MUST be refactored when touching a service's config.
>
> **Reference implementation:** `services/core/internal/config/config.go`

### Config Rules (Enforced)

1. **`mapstructure` tags on every field** — derives YAML keys and env var names automatically
2. **`default` tags for library-provided defaults** — eliminates manual `SetDefault()` calls
3. **Value types for sub-configs** (not pointers) — no `nil` checks needed in DI modules
4. **Embed devkit/common config types directly** when they match (`logger.Config`, `trace.Config`, `sentry.Config`, `platformfx.Config`, `featurescript.Config`)
5. **Service-specific defaults in `defaults()` map** — only for values not coverable by struct tags (e.g., slice values, service-specific overrides)
6. **`WithEnvironmentFile("ENVIRONMENT", "./configs")`** — loads `{ENVIRONMENT}.yaml` (defaults to `local.yaml`)
7. **`EnvBinder` interface** auto-discovers non-standard env vars (OTEL_*, SENTRY_*) from embedded devkit types
8. **`WithEnvBindings()`** for service-specific legacy env var mappings only
9. **Never `import "github.com/spf13/viper"` directly** in service config packages

### Precedence (highest to lowest)

1. Explicit overrides (`WithOverrides`)
2. Environment variables (auto-mapped from `mapstructure` tags: `postgresql.host` → `POSTGRESQL_HOST`)
3. Config file (YAML from `WithEnvironmentFile`)
4. `WithDefaults()` map
5. `default` struct tags (lowest priority)

### Config Struct Pattern

```go
// internal/config/config.go
package config

import (
    "fmt"
    "os"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/config"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/featurescript"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/sentry"
)

const serviceName = "myservice"

type (
    PostgresConfig struct {
        Host     string `mapstructure:"host"     default:"postgres"`
        Port     string `mapstructure:"port"     default:"5432"`
        User     string `mapstructure:"user"     default:"postgres"`
        Password string `mapstructure:"password" default:"postgres"`
        Name     string `mapstructure:"db_name"`
        SSLMode  string `mapstructure:"ssl_mode" default:"disable"`
    }

    HTTPConfig struct {
        InfraPort string `mapstructure:"infra_port" default:"7777"`
        ApiPort   string `mapstructure:"api_port"   default:"8080"`
    }

    GRPCConfig struct {
        Port string `mapstructure:"port" default:"50051"`
    }

    Config struct {
        ServiceName   string              `mapstructure:"service_name" default:"myservice"`
        Environment   string              `mapstructure:"environment"  default:"local"`
        Postgres      PostgresConfig      `mapstructure:"postgresql"`
        HTTP          HTTPConfig          `mapstructure:"http"`
        GRPC          GRPCConfig          `mapstructure:"grpc"`
        Logger        logger.Config       `mapstructure:"logger"`
        Trace         trace.Config        `mapstructure:"trace"`
        Platform      platformfx.Config   `mapstructure:"platform"`
        Sentry        sentry.Config       `mapstructure:"sentry"`
        FeatureScript featurescript.Config `mapstructure:"featurescript"`
    }
)

func Load() (*Config, error) {
    cfg, _, err := config.Load[Config](
        config.WithEnvironmentFile("ENVIRONMENT", "./configs"),
        config.WithDefaults(defaults()),
        config.WithRedactKeys("postgresql.password", "sentry.dsn"),
        config.WithEnvBindings(map[string]string{
            // Only for legacy env vars that don't follow mapstructure convention
            "http.infra_port": "INFRA_PORT",
        }),
    )
    if err != nil {
        return nil, fmt.Errorf("failed to load config: %w", err)
    }

    // Propagate service identity to observability sub-configs.
    cfg.Logger.Service.Name = cfg.ServiceName
    cfg.Logger.Service.Environment = cfg.Environment
    cfg.Trace.Service.Name = cfg.ServiceName
    cfg.Trace.Service.Environment = cfg.Environment
    if cfg.Sentry.Environment == "" {
        cfg.Sentry.Environment = cfg.Environment
    }
    cfg.Sentry.ServerName = cfg.ServiceName

    return &cfg, nil
}

// defaults returns only service-specific values not covered by struct tags.
func defaults() map[string]any {
    return map[string]any{
        "postgresql.db_name":      serviceName,
        "trace.exporter.endpoint": "localhost:4317",
        "trace.exporter.insecure": true,
        "trace.sampling.ratio":    1.0,
    }
}
```

### What goes where

| Value source | When to use | Example |
|---|---|---|
| `default` struct tag | Universal defaults from devkit or obvious values | `default:"5432"`, `default:"postgres"` |
| `defaults()` map | Service-specific overrides, slice values, dynamic names | `"postgresql.db_name": serviceName` |
| YAML config file | Environment-specific values | `configs/dev.yaml`, `configs/prod.yaml` |
| `WithEnvBindings()` | Legacy env var names that don't match mapstructure | `"http.infra_port": "INFRA_PORT"` |
| `EnvBinder` interface | Non-standard env vars in devkit types (auto-discovered) | `OTEL_*`, `SENTRY_*` |

### Refactoring Legacy Config (MANDATORY when touching config)

When working on a Go service that still uses manual Viper setup:

1. Replace `*SubConfig` pointers with value types `SubConfig`
2. Add `mapstructure` + `default` tags to all struct fields
3. Replace `setDefaults()` / `bindEnvs()` with `defaults()` map + struct tags
4. Replace manual `viper.New()` + `v.ReadInConfig()` with `config.Load[Config]()`
5. Remove `import "github.com/spf13/viper"` from service config packages
6. Update YAML keys to match mapstructure tags (underscore-separated, not dot-separated)
7. Remove `nil` checks for sub-configs in DI modules
8. Add post-load propagation for `ServiceName`/`Environment` → observability configs

## Technology Stack

| Component | Technology | devkit/common Module |
|-----------|------------|---------------------|
| DI Framework | Uber Fx | `platformfx` |
| Logging | Zap | `logger/fx`, `logger/zap` |
| Tracing | OpenTelemetry | `observability/trace/fx` |
| gRPC Server | grpc-go | `grpcserver` |
| gRPC Client | grpc-go | `grpcclient`, `grpcclient/fx` |
| gRPC Errors | grpc-go | `grpcerr` |
| HTTP Server | Gin | `http` (ServerBuilder) |
| Configuration | Viper | `config`, `config/fx` |
| Remote Config | Redis | `config/remoteconfig` |
| Shutdown | Graceful | `shutdown`, `platformfx` |
| Database | PostgreSQL/pgx | `postgres`, `postgres/fx` |
| Migrations | Atlas | `postgres/atlas` (see `references/atlas-migrations.md`) |
| Cache / State | Redis | `redis`, `sharedmemory` |
| Messaging | NATS + JetStream | `nats` (preferred for new services) |
| Messaging (legacy) | Kafka/Sarama | **Deprecated** — see `references/kafka-templates.md` |
| Audit Logging | saas audit-log v3 (gRPC/NATS) | `auditlogclient`, `auditlogclient/fx` |
| Workflow Orchestration | Temporal | `temporal`, `temporal/fx`, `temporal/otel`, `temporal/registry` |
| Error Tracking | Sentry | `sentry` (see `sentry-integration` skill) |
| Profiling | Grafana Pyroscope | `pyroscope` (see `pyroscope-integration` skill) |
| Feature Flags | FeatureScript | `featurescript` (see `featurescript-client` skill) |
| Context Values | stdlib | `xctx` (TenantID, RequestID, UserID, CorrelationID) |
| ID Generation | CUID2 | `cuid` |
| Financial Math | shopspring/decimal | `money` |
| Pagination | stdlib | `pagination` (Offset, Limit, Span) |
| Pointer Helpers | stdlib | `ptr` (`MapNil`, `MapNilErr`) |

## Compliance Checklist

Before completing a service, verify:

**Architecture:**
- [ ] Bootstrap uses `platformfx.Module` first
- [ ] Logger uses `loggerfx.ModuleWithOptions` with OTel integration
- [ ] Domain entities have NO external dependencies
- [ ] Services depend on interfaces, not implementations
- [ ] Shutdown hooks registered via `platformfx.ProvideShutdownHook`

**Instrumentation (MANDATORY):**
- [ ] All service layer wrappers use `trace.Instrument(ctx, method)` (NOT `trace.Start`)
- [ ] All repository layer wrappers use `trace.Instrument(ctx, method)` (NOT `trace.Start`)
- [ ] All client wrappers use `trace.Instrument(ctx, method)` (NOT `trace.Start`)
- [ ] HTTP middleware includes `MetricsMiddleware` from `devkit/common/http`
- [ ] gRPC interceptors include `MetricsUnaryInterceptor` from `devkit/common/grpcserver`

**Transport (both required):**
- [ ] HTTP handlers implemented with devkit/common middleware chain (Recovery, Tracing, Logger, Metrics, CORS)
- [ ] gRPC handlers implemented with devkit/common interceptor chain (Tracing, RequestID, Logging, Metrics, Recovery, ErrorMapping, Validation)
- [ ] Proto files defined in `api/proto/`
- [ ] Proto mapping layer for complex conversions (see `references/protomap-patterns.md`)

**Configuration (MANDATORY — devkit/common v0.17.0+):**
- [ ] Config struct uses `mapstructure` tags on every field
- [ ] Config struct uses `default` tags for library-provided defaults (no manual `SetDefault`)
- [ ] Sub-configs are value types (not pointers) — no `nil` checks in DI modules
- [ ] devkit/common types embedded directly (`logger.Config`, `trace.Config`, `sentry.Config`, `platformfx.Config`, `featurescript.Config`)
- [ ] `config.Load[Config]()` with `WithEnvironmentFile` — no direct `viper` import
- [ ] Service-specific defaults in `defaults()` map (only values not covered by struct tags)
- [ ] `WithEnvBindings()` only for legacy env vars — standard vars auto-mapped via `mapstructure` tags
- [ ] Post-load propagation of `ServiceName`/`Environment` → Logger, Trace, Sentry configs
- [ ] `Sanitized()` method redacts passwords and DSNs — no `nil` checks needed with value types
- [ ] YAML keys match `mapstructure` tags (underscore-separated, e.g. `sample_rate` not `sample.rate`)

**Infrastructure:**
- [ ] Database migrations use Atlas with `devkit/common/postgres/atlas`
- [ ] PostgreSQL uses Ent ORM (preferred) or `postgresfx.Module` from `devkit/common/postgres/fx`
- [ ] Redis caching for ephemeral data (if applicable, see `references/redis-patterns.md`)

**Temporal (if applicable):**
- [ ] Bootstrap includes `temporalfx.Module(cfg.Temporal)` with OTel tracing config
- [ ] Workflows are deterministic — no `time.Now()`, `time.Sleep`, `rand.*`, I/O, client connections, or goroutines, channels, `select`. All time uses in Workflows `workflow.Now(ctx)` / `workflow.Sleep(ctx, d)`, `workflow.SideEffect` for randomness, `workflow.NewSelector`, `workflow.Go`
- [ ] Workflow inputs/outputs are versioned structs (no primitives, no `map[string]any`)
- [ ] Workflows invoke struct-based activities via method value references (`var a *Activities; workflow.ExecuteActivity(ctx, a.Method, ...)`), NOT string names
- [ ] Activities are idempotent; use workflow-derived idempotency keys
- [ ] Activity options always specify all timeouts + retry policy (use `commontemporal.DefaultActivityOptions()`)
- [ ] Activity logs enriched with Temporal metadata via `activityLog(ctx)` helper (workflow_id, run_id, attempt) — see `references/temporal-patterns.md` §5 and §7
- [ ] Heartbeats placed AFTER slow calls (not before); `HeartbeatTimeout` only set on activities that actually heartbeat
- [ ] `ctx.Err()` checked between sequential external calls for cancellation responsiveness
- [ ] Each activity owns one concern (single-responsibility); conditional side effects moved to separate activities or workflow-level branching
- [ ] Workflows needing rollback use `defer` + `workflow.NewDisconnectedContext` Saga pattern (compensation stack in reverse order) — see `references/temporal-patterns.md` §4, Compensation and Workflow Cancellation
- [ ] Signal-based cancellation distinguished from workflow cancellation (signal does NOT cancel `ctx`; `NewDisconnectedContext` only needed for workflow cancellation)
- [ ] Non-retryable errors use `temporal.NewNonRetryableApplicationError`
- [ ] Workflow evolution uses `workflow.GetVersion` for any semantic change
- [ ] Long-lived workflows include Continue-As-New strategy
- [ ] Workflows/activities registered via `temporalfx.Provide*Registrar`
- [ ] `ExecuteWorkflow` called from service layer (not handler)
- [ ] `cmd/worker.go` exists for independent worker scaling
- [ ] `serve --worker=false` mode tested for API-only deployment
- [ ] Worker can scale independently from API pods
- [ ] Worker shutdown hook at `PriorityServer` (10), client at `PriorityDatabase` (60)

**Production Readiness:**
- [ ] Ent ORM with Atlas migrations (preferred over raw pgx, see `references/ent-orm-patterns.md`)
- [ ] Integration tests with Docker Compose (see `references/testing-patterns.md`)
- [ ] E2E tests for critical workflows
- [ ] Custom business metrics (see `references/custom-metrics.md`)

**Security:**
- [ ] Trivy scan passes: `trivy fs --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed .` → 0 findings

**Verification (MUST complete before finishing):**
- [ ] Service starts without errors
- [ ] HTTP health endpoint works: `curl http://localhost:8080/health`
- [ ] HTTP CRUD endpoints work (create, get, list, update, delete)
- [ ] gRPC health check works: `grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check`
- [ ] gRPC service methods work (list services, call each RPC)
- [ ] Logs show trace context (trace_id, span_id, request_id)
- [ ] Service shuts down gracefully (no errors on Ctrl+C)

## Reference Documents

For detailed guidance, read the reference files in this skill's `references/` directory:

### Core Templates
- `references/bootstrap-templates.md` - Complete bootstrap code, DI modules, configuration, **standalone logger patterns**
- `references/domain-implementation.md` - Domain entities, services (3-file pattern), and handlers
- `references/grpc-templates.md` - **gRPC server/client with full instrumentation, proto files, handlers**
- `references/clients-templates.md` - **External service clients with 3-file pattern (interface, implementation, instrumented)**
- `references/new-service-workflow.md` - Step-by-step guide for creating new services
- `references/infrastructure-templates.md` - Makefile, docker-compose, Atlas setup
- `references/shutdown-patterns.md` - **Comprehensive shutdown management: priorities, database/server/Temporal/NATS patterns**
- `references/kafka-templates.md` - **Legacy only** — Kafka/Sarama patterns (deprecated; prefer `nats-events` skill)

### Database & Persistence
- `references/atlas-migrations.md` - **Atlas database migrations with declarative schema, Go SDK integration**
- `references/ent-orm-patterns.md` - **Ent ORM with Atlas (preferred over raw pgx): schema definitions, type-safe queries, repository patterns**
- `references/redis-patterns.md` - **Redis repository and caching patterns: key naming, TTL, instrumentation**

### Advanced Patterns
- `references/temporal-patterns.md` - **Temporal workflow orchestration: config, bootstrap, workflows, activities, signals, versioning, testing, replay**
- `references/testing-patterns.md` - **Testing infrastructure: unit tests, integration tests with Docker Compose, E2E tests**
- `references/protomap-patterns.md` - **Proto mapping layer: bidirectional conversion, enum handling, collection patterns**
- `references/custom-metrics.md` - **Custom business metrics with OpenTelemetry: counters, histograms, gauges**

## Common Tasks

### "Create a new microservice"

1. Ask for: service name, module path, domain(s), operations needed
2. Create directory structure following the layout in this skill's "Directory Structure" section
3. Copy templates from skill reference files:
   - Bootstrap code from `references/bootstrap-templates.md`
   - Infrastructure files from `references/infrastructure-templates.md`
   - Domain implementation from `references/domain-implementation.md`
   - **gRPC handlers from `references/grpc-templates.md`** (always include gRPC)
4. Initialize Go module: `go mod init <module-path>`
5. Update `internal/config/configuration.go` with service-specific config
6. Implement domain entities in `internal/core/<domain>/`
7. Implement services in `internal/services/<domain>/` (3-file pattern)
8. Create **both** HTTP and gRPC handlers in `internal/handlers/`
9. Create DI modules in `internal/di/` (http, grpc, postgres)
10. Wire bootstrap in `cmd/serve.go` following `references/bootstrap-templates.md`
11. Set up Atlas migrations using `references/atlas-migrations.md`
12. Run `go mod tidy && go build ./...` to verify compilation
13. **Start the service and verify all endpoints:**
    - Start dependencies: `make up`
    - Run migrations: `make migrate-db`
    - Run service: `make run` (or `go run .`)
    - Test HTTP endpoints: `curl http://localhost:8080/health` and CRUD endpoints
    - Test gRPC endpoints: `grpcurl -plaintext localhost:50051 list` and service methods
    - Verify logs show proper tracing context (trace_id, span_id)
    - Stop service and dependencies when verification complete

### "Add CRUD for a new entity"

1. Create entity in `internal/core/<domain>/<entity>.go`
2. Create errors in `internal/core/<domain>/errors.go`
3. Create service interface in `internal/services/<domain>/service.go`
4. Create service implementation in `internal/services/<domain>/default.go`
5. Create instrumented wrapper in `internal/services/<domain>/instrumented.go`
6. Add repository interface to `internal/repo/repo.go`
7. Add repository implementation in `internal/repo/postgres/`
8. Add **both** HTTP handlers in `internal/handlers/http/` **and** gRPC handlers in `internal/handlers/grpc/`
9. Update proto file in `api/proto/` with new RPCs (see `references/grpc-templates.md`)
10. Update DI modules to wire new components
11. **Run and verify:** Start service, test all new HTTP and gRPC endpoints work correctly

### "Set up observability"

1. Ensure `loggerfx.ModuleWithOptions` with `zaplogger.WithOTelTracing()`
2. Ensure `tracefx.Module` is included in bootstrap
3. Import OTel backend: `_ "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/otel"`
4. Wrap all services with instrumentation using `trace.Instrument`
5. Use `logger.Logger` interface with context-aware methods
6. Add gRPC interceptors from `grpcserver` and `tracegrpc`
7. Add HTTP middleware from `commonhttp` and `tracehttp`

### "Add external service client"

1. Create client directory: `internal/clients/<service-name>/`
2. Create interface in `client.go` with domain types (not proto types)
3. Create gRPC implementation in `default_client.go` using `grpcclient.NewBuilder()`
4. Create instrumented wrapper in `instrumented.go` using `trace.Instrument()`
5. Add client config to `ClientsConfig` in `internal/config/configuration.go`
6. Add YAML config to `config/configuration.yaml` under `clients:`
7. Wire in Fx module: provide DefaultClient, then provide interface (instrumented)
8. Add shutdown hook with `platformfx.ProvideShutdownHook`
9. See `references/clients-templates.md` for complete templates

### "Add NATS event publishing"

Prefer NATS + JetStream for all new services. Follow the **`nats-events`** skill end-to-end (publisher/subscriber ports, subjects, headers via `xctx`, Fx wiring).

1. Wire `natsfx.Module` when the service needs JetStream.
2. Implement domain publisher/subscriber ports; put metadata in NATS headers (not the body).
3. Annotate proto events/commands with NATS subjects in proto-api when applicable (`nats-subjects` skill there).

### "Add Kafka event publishing" (legacy only)

**Deprecated.** Use only when maintaining an existing Kafka publisher. New work must use NATS (`nats-events` skill). If you must touch Kafka: see `references/kafka-templates.md` and keep the graceful-disable Fx pattern — do not introduce Kafka into greenfield services.

### "Add audit logging"

devkit `auditlogclient` (v0.32.0+) emits VARA/compliance audit events to the saas audit-log v3 service over gRPC or NATS JetStream. See the `auditlog-client` skill for the full reference; quick path:

1. Define an `auditlog.Service` port with typed event structs in `internal/services/auditlog/service.go` (keep call-sites decoupled from the transport).
2. Define the manifest as a package-level `var Manifest = auditlogclient.DefineEvents(auditlogclient.Manifest{"<group>": {"<event>": {Target: "<entity>"}}})` — group/event keys drive the derived `SCREAMING_SNAKE` action.
3. Implement an adapter satisfying `auditlog.Service` that calls `client.Emit(ctx, group, event, auditlogclient.EmitParams{...})` per event; tenant/initiator/correlation are auto-filled from `xctx`.
4. Add `AuditLog auditlogclient.Config` to the service `Configuration` struct (`mapstructure:"audit_log"`) and an `audit_log:` YAML block (`transport: nats|grpc`, `source: <service-name>`).
5. Wire `auditlogclientfx.Module(cfg.AuditLog, Manifest)` in an Fx module:
   - **NATS transport**: requires `natsfx.Module` to already be in the graph (provides `*nats.JetStreamPublisher`); no extra shutdown hook needed (NATS owns the connection).
   - **gRPC transport**: self-dials `cfg.AuditLog.GRPC.URL`; devkit registers its own shutdown hook.
6. For a conditional NATS-only deployment, gate the module on `cfg.Nats.Enabled && cfg.Nats.JetStream.Enabled` and fall back to a logger stub otherwise — see `saas/services/compliance-chat/internal/di/auditlog/module.go` for a reference implementation.
7. Optional: use `auditlogclient.NewMethodRegistry()` + `auditlogclientfx.NewUnaryServerInterceptor` for RPC-level auto-emit instead of (or alongside) manual `Emit` calls.

### "Set up Atlas migrations"

1. Create `atlas/` directory with `schema.sql` and `atlas.hcl`
2. Define database schema in `atlas/schema.sql` (declarative, source of truth)
3. Create `atlas/atlas.hcl` configuration with database connection variables. **Must include `revisions_schema = "public"` in every `migration {}` block** (prevents init-container crash loops caused by Atlas trying to recreate a separate `atlas_schema_revisions` schema on restart)
4. Add `atlas.Config` to `internal/config/configuration.go` (using devkit/common/postgres/atlas)
5. Add YAML config to `config/configuration.yaml` under `atlas:`
6. Create `cmd/migratedb/cmd.go` CLI command using devkit/common/postgres/atlas.Migrator
7. Register `migrate-db` command in `cmd/root.go`
8. Update Makefile with Atlas targets (`atlas-install`, `atlas-diff`, `migrate-db`)
9. Update Dockerfile to include Atlas CLI
10. See `references/atlas-migrations.md` for complete templates

### "Migrate from golang-migrate to Atlas"

1. Create `atlas/` directory structure
2. Generate `schema.sql` from existing database: `atlas schema inspect -u "postgres://..." > atlas/schema.sql`
3. Create `atlas/atlas.hcl` configuration
4. Initialize Atlas migrations: `atlas migrate diff initial --env local`
5. Replace Makefile targets (remove golang-migrate, add Atlas)
6. Create `cmd/migratedb/cmd.go` using `devkit/common/postgres/atlas.Migrator`
7. Add `atlas.Config` to Configuration struct
8. Update Dockerfile to include Atlas CLI
9. Test migrations work correctly
10. Remove old `migrations/` directory after verification
11. See `references/atlas-migrations.md` Section 10 for detailed guide

### "Set up Ent ORM with Atlas" (Preferred DB Approach)

1. Initialize Ent: `go run -mod=mod entgo.io/ent/cmd/ent new {{Entity}}`
2. Define schema in `internal/repo/postgres/ent/schema/{{entity}}.go`
3. Generate Ent code: `go generate ./internal/repo/postgres/...`
4. Create repository wrapping Ent client in `internal/repo/postgres/`
5. Add type conversion mappers (domain ↔ Ent)
6. Configure Atlas in `atlas/atlas.hcl` pointing to `schema.sql`
7. Initialize Ent client with otelsql instrumentation in Fx module
8. See `references/ent-orm-patterns.md` for complete patterns

### "Add Testing Infrastructure"

1. Create `test/infra/` with Docker Compose management:
   - `suite.go` - Infrastructure controller
   - `docker.go` - Docker Compose lifecycle
   - `grpc.go` - gRPC client management
   - `wait.go` - Service readiness waiting
2. Create `test/integration/` with suite pattern:
   - `suite.go` - Setup/teardown
   - `helpers.go` - Test utilities
3. Create `deployment/local/docker-compose.test.yml` for test isolation
4. Add Makefile targets: `test-unit`, `test-integration`, `test-e2e`
5. See `references/testing-patterns.md` for complete templates

### "Add Redis Caching Layer"

1. Add Redis config section to `internal/config/configuration.go`
2. Create `internal/repo/redis/` with repository pattern:
   - `repo.go` - Base repository
   - `types.go` - Redis-specific types (for JSON)
   - `{{entity}}.go` - Entity operations
   - `instrumentation.go` - Observability wrapper
3. Add Redis client provider in Fx module with lifecycle hooks
4. Register shutdown hook with appropriate priority
5. Use consistent key naming: `{domain}:{entity}:{id}`
6. See `references/redis-patterns.md` for complete patterns

### "Add Temporal Workflow Orchestration"

1. Add `temporal.Config` and `temporalotel.TracingConfig` to `internal/config/configuration.go`
2. Add YAML config to `config/configuration.yaml` under `temporal:` and `temporal_otel:`
3. Add `temporalfx.Module(cfg.Temporal)` to bootstrap in `cmd/serve.go` (after tracefx, before infra)
4. Provide OTel tracing config: `fx.Provide(func() *temporalotel.TracingConfig { return &cfg.TemporalOTel })`
5. Create workflow input/output structs in `internal/orchestration/workflows/<domain>/types.go`
6. Implement workflow function in `internal/orchestration/workflows/<domain>/workflow.go`:
   - Use `commontemporal.DefaultActivityOptions()` for activity contexts
   - Invoke struct-based activities via method value references (`var a *Activities; workflow.ExecuteActivity(ctx, a.Method, ...)`)
   - All time via `workflow.Now(ctx)` / `workflow.Sleep(ctx, d)`
   - Version changes with `workflow.GetVersion`
   - If workflow steps have side effects needing rollback, implement `defer` + `workflow.NewDisconnectedContext` Saga pattern (compensation stack in reverse order) — see `references/temporal-patterns.md` §4, Compensation and Workflow Cancellation
7. Create activity struct in `internal/orchestration/activities/<domain>/activities.go`:
   - Inject service/repo dependencies
   - Add `activityLog(ctx)` helper that enriches injected logger with Temporal metadata (workflow_id, run_id, attempt)
   - Heartbeat AFTER slow operations (not before); check `ctx.Err()` between external calls
   - Each activity owns one concern — avoid mixing unrelated side effects
   - Classify non-retryable errors with `temporal.NewNonRetryableApplicationError`
   - Ensure idempotency using workflow-derived keys
   - Move conditional logic (feature flags) to workflow-level branching via dedicated activities
8. Create registrars using `temporalfx.ProvideWorkflowRegistrar` and `temporalfx.ProvideActivityRegistrar`
9. Start workflows from service layer via `client.Client.ExecuteWorkflow`
10. Write workflow tests with `testsuite.WorkflowTestSuite` and replay tests
11. See `references/temporal-patterns.md` for complete templates and examples

### "Add Proto Mapping Layer"

1. Create `internal/protomap/` package
2. Define bidirectional conversion functions:
   - `{{Entity}}ToProto(domain) (*pb.{{Entity}}, error)`
   - `ProtoTo{{Entity}}(proto) (*domain.{{Entity}}, error)`
3. Add enum conversion functions
4. Add collection conversion helpers
5. Use in gRPC handlers instead of inline conversion
6. See `references/protomap-patterns.md` for complete patterns

### "Add Custom Business Metrics"

1. Create `internal/metrics/` package:
   - `metrics.go` - Metric definitions and initialization
   - `attributes.go` - Common attribute helpers
2. Initialize metrics using OTel Meter API (singleton pattern)
3. Add nil-safe recording methods
4. Provide via Fx with service name from config
5. Call from instrumented service layer
6. Metric types: `Int64Counter`, `Float64Histogram`, `Int64UpDownCounter`
7. Use HTTP metrics middleware from `devkit/common/http` for request metrics
8. See `references/custom-metrics.md` for complete patterns
