# Bootstrap Templates

Complete, copy-paste ready templates for bootstrapping Go microservices using devkit/common.

## Table of Contents

1. [Main Entry Point](#1-main-entry-point)
2. [Root Command](#2-root-command)
3. [Serve Command](#3-serve-command)
3a. [Standalone Logger for CLI Commands](#3a-standalone-logger-for-cli-commands)
4. [Configuration](#4-configuration)
5. [HTTP DI Module](#5-http-di-module)
6. [gRPC DI Module](#6-grpc-di-module)
7. [PostgreSQL DI Module](#7-postgresql-di-module)
8. [HTTP Middleware](#8-http-middleware)
9. [HTTP Router](#9-http-router)

---

## 1. Main Entry Point

```go
// main.go
package main

import (
    "your-service/cmd"
)

func main() {
    cmd.Execute()
}
```

---

## 2. Root Command

```go
// cmd/root.go
package cmd

import (
    "context"
    "fmt"
    "os"

    "github.com/spf13/cobra"
    "go.uber.org/fx"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "your-service/internal/config"
)

var rootCmd = &cobra.Command{
    Use:   "myservice",
    Short: "myservice microservice",
    Long:  `A microservice built with devkit/common.`,
    Run: func(cmd *cobra.Command, args []string) {
        // Default to serve command
        serveCmd.Run(cmd, args)
    },
}

// Execute runs the root command.
func Execute() {
    if err := rootCmd.Execute(); err != nil {
        fmt.Fprintf(os.Stderr, "Error: %v\n", err)
        os.Exit(1)
    }
}

func init() {
    // Add flags here if needed
}

// registerServiceLifecycle registers service-level lifecycle logging.
func registerServiceLifecycle(lc fx.Lifecycle, log logger.Logger, cfg *config.Configuration) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            log.Info(ctx, "Service started",
                logger.String("service", cfg.ServiceName),
                logger.String("environment", cfg.Environment),
            )
            return nil
        },
        OnStop: func(ctx context.Context) error {
            log.Info(ctx, "Service stopped",
                logger.String("service", cfg.ServiceName),
            )
            return nil
        },
    })
}
```

---

## 3. Serve Command

```go
// cmd/serve.go
package cmd

import (
    "fmt"
    "os"

    "github.com/spf13/cobra"
    "go.uber.org/fx"

    loggerfx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger/fx"
    zaplogger "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger/zap"
    tracefx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace/fx"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"
    "your-service/internal/config"
    grpcdi "your-service/internal/di/grpc"
    httpdi "your-service/internal/di/http"
    "your-service/internal/di/postgres"

    // Import the OTel trace backend
    _ "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/otel"
)

var serveCmd = &cobra.Command{
    Use:   "serve",
    Short: "Start both HTTP and gRPC servers",
    Long: `Start both HTTP and gRPC servers.

This command runs the service with both transport layers:
- HTTP server on :8080 (configurable via http.addr)
- gRPC server on :50051 (configurable via grpc.addr)

Example usage:
  myservice serve
  curl http://localhost:8080/health
  grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check`,
    Run: func(cmd *cobra.Command, args []string) {
        runServeService()
    },
}

func init() {
    rootCmd.AddCommand(serveCmd)
}

// runServeService initializes and runs both HTTP and gRPC services with Fx.
func runServeService() {
    // Load configuration first (needed for module initialization)
    cfg, meta, err := config.Load()
    if err != nil {
        fmt.Fprintf(os.Stderr, "Failed to load config: %v\n", err)
        os.Exit(1)
    }

    // Log any configuration warnings (e.g., deprecated keys)
    for _, w := range meta.Warnings {
        fmt.Fprintf(os.Stderr, "Config warning: %s\n", w)
    }

    app := fx.New(
        // 1. Make Fx use our logger for its internal events
        loggerfx.WithFxLoggerFromConfig(cfg.Logger),

        // 2. Core platform module (provides shutdown manager)
        // ALWAYS FIRST - provides shutdown.Manager with hook collection
        platformfx.Module(cfg.Platform),

        // 3. Logger module with OTel integration
        // Auto-adds trace_id, span_id to logs via WithOTelTracing()
        // Auto-adds xctx values (tenant_id, request_id) via WithContextValues()
        loggerfx.ModuleWithOptions(cfg.Logger,
            zaplogger.WithOTelTracing(),
            zaplogger.WithContextValues(),
        ),

        // 4. Trace module (distributed tracing)
        tracefx.Module(cfg.Trace),

        // 5. Provide the configuration
        fx.Provide(func() *config.Configuration { return cfg }),

        // 6. Infrastructure modules
        postgres.Module, // Database with tracing

        // 7. Transport modules (HTTP/gRPC)
        httpdi.Module,
        grpcdi.Module,

        // 8. Application lifecycle logging
        fx.Invoke(registerServiceLifecycle),
    )

    app.Run()
}
```

---

## 3a. Standalone Logger for CLI Commands

For CLI commands (migrate, seed, etc.) that don't use the full Fx bootstrap, create a standalone logger:

```go
// cmd/migrate.go
package cmd

import (
    "context"
    "fmt"
    "time"

    "github.com/spf13/cobra"
    
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    zaplogger "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger/zap"
    
    "your-service/internal/config"
    "your-service/internal/migrations"
)

var migrateCmd = &cobra.Command{
    Use:   "migrate",
    Short: "Run database migrations",
    RunE: func(cmd *cobra.Command, args []string) error {
        cfg, _, err := config.Load()
        if err != nil {
            return fmt.Errorf("failed to load config: %w", err)
        }

        // Create standalone logger for CLI command
        logCfg := logger.DefaultConfig().
            WithService(cfg.ServiceName, "", cfg.Environment)

        if cfg.Environment == "local" || cfg.Environment == "development" {
            logCfg = logCfg.WithLevel("debug").WithDevelopment(true)
        } else {
            logCfg = logCfg.WithLevel("info")
        }

        log, err := zaplogger.New(logCfg)
        if err != nil {
            return fmt.Errorf("failed to create logger: %w", err)
        }
        defer log.Sync()

        // Use the logger
        ctx := context.Background()
        log.Info(ctx, "Starting migrations", logger.String("environment", cfg.Environment))

        migrator := migrations.NewMigrator(log, cfg)
        defer migrator.Close()

        ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
        defer cancel()

        if err := migrator.Run(ctx); err != nil {
            log.Error(ctx, "Migration failed", logger.Err(err))
            return fmt.Errorf("migration failed: %w", err)
        }

        log.Info(ctx, "Migrations completed successfully")
        return nil
    },
}

func init() {
    rootCmd.AddCommand(migrateCmd)
}
```

### Key Differences from Fx Bootstrap

| Aspect | Fx Bootstrap | Standalone CLI |
|--------|--------------|----------------|
| Logger creation | `loggerfx.ModuleWithOptions()` | `zaplogger.New()` directly |
| OTel tracing | Auto-enabled via `WithOTelTracing()` | Usually not needed |
| Context values | Auto-enabled via `WithContextValues()` | Usually not needed |
| Lifecycle | Managed by Fx | Manual `defer log.Sync()` |

### Logger Configuration Methods

```go
// Start with defaults
logCfg := logger.DefaultConfig()

// Chain configuration methods
logCfg = logCfg.
    WithService("service-name", "v1.0.0", "production"). // name, version, env
    WithLevel("info").                                    // debug, info, warn, error
    WithFormat("json").                                   // json or console
    WithDevelopment(false)                               // false for production
```

---

## 4. Configuration (devkit/common v0.17.0+)

> **MANDATORY:** All Go services must use `config.Load[T]()` from `devkit/common/config`.
> Do NOT use `viper.New()`, `v.SetDefault()`, or `v.BindEnv()` directly in service config packages.
> Reference implementation: `services/core/internal/config/config.go`.

### Key Principles

1. **`mapstructure` tags on every field** — auto-derives env var names (`postgresql.host` → `POSTGRESQL_HOST`)
2. **`default` tags for universal defaults** — replaces manual `SetDefault()` calls
3. **Value types** for sub-configs (not pointers) — no `nil` checks in DI modules
4. **`defaults()` map** only for service-specific values not covered by struct tags
5. **`WithEnvironmentFile()`** — loads `{ENVIRONMENT}.yaml` from configs dir
6. **`EnvBinder` interface** on devkit types auto-discovers non-standard env vars (OTEL_*, SENTRY_*)
7. **`WithEnvBindings()`** only for legacy env var names that don't match mapstructure convention

### Precedence (highest to lowest)

1. Explicit overrides (`WithOverrides`)
2. Environment variables (auto-mapped: `mapstructure` tag → `UPPER_SNAKE_CASE`)
3. Config file (YAML)
4. `WithDefaults()` map
5. `default` struct tags

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
        Port     int    `mapstructure:"port"     default:"5432"`
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

    RedisConfig struct {
        Host     string `mapstructure:"host"     default:"localhost"`
        Port     int    `mapstructure:"port"     default:"6379"`
        Addrs    []string `mapstructure:"addrs"`
        Password string `mapstructure:"password"`
    }

    // Deprecated: use NATS config for new services (see nats-events skill).
    KafkaConfig struct {
        Brokers       []string `mapstructure:"brokers"`
        ConsumerGroup string   `mapstructure:"consumer_group"`
    }

    NATSConfig struct {
        URL string `mapstructure:"url" default:"nats://localhost:4222"`
    }

    Config struct {
        ServiceName   string              `mapstructure:"service_name" default:"myservice"`
        Environment   string              `mapstructure:"environment"  default:"local"`
        Postgres      PostgresConfig      `mapstructure:"postgresql"`
        HTTP          HTTPConfig          `mapstructure:"http"`
        GRPC          GRPCConfig          `mapstructure:"grpc"`
        Redis         RedisConfig         `mapstructure:"redis"`
        NATS          NATSConfig          `mapstructure:"nats"`
        Kafka         KafkaConfig         `mapstructure:"kafka"` // Deprecated: prefer NATS
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
        config.WithRedactKeys("postgresql.password", "redis.password", "sentry.dsn"),
        config.WithEnvBindings(map[string]string{
            // Only for legacy env vars that don't follow mapstructure convention.
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
        "nats.url":                "nats://localhost:4222",
        // Deprecated: Kafka defaults — only for legacy services
        // "kafka.brokers":        []string{"localhost:9092"},
        // "kafka.consumer_group": serviceName + "-consumer",
        "trace.exporter.endpoint": "localhost:4317",
        "trace.exporter.insecure": true,
        "trace.sampling.ratio":    1.0,
    }
}
```

### Configuration YAML (environment-specific)

```yaml
# configs/local.yaml — loaded when ENVIRONMENT=local or unset
postgresql:
  db_name: myservice

logger:
  level: debug
  format: console
  development: true

sentry:
  sample_rate: 1.0
  traces_sample_rate: 0.1

trace:
  enabled: true
  development: true
  sampling:
    ratio: 1.0
  exporter:
    endpoint: "localhost:4317"
    insecure: true
```

```yaml
# configs/prod.yaml — loaded when ENVIRONMENT=production
sentry:
  sample_rate: 1.0
  traces_sample_rate: 0.05
```

### Refactoring Legacy Config (MANDATORY when touching config)

If the service still uses manual Viper setup:

1. Replace `*SubConfig` pointers → value types `SubConfig`
2. Add `mapstructure` + `default` tags to all struct fields
3. Replace `setDefaults()` / `bindEnvs()` → `defaults()` map + struct tags
4. Replace `viper.New()` + `v.ReadInConfig()` → `config.Load[Config]()`
5. Remove `import "github.com/spf13/viper"` from service config
6. Update YAML keys to match mapstructure tags (underscore-separated)
7. Remove `nil` checks for sub-configs in DI modules
8. Add post-load propagation: `ServiceName`/`Environment` → Logger, Trace, Sentry

### DI Module Adaptation

Sub-configs are value types, so DI modules pass addresses when libraries need pointers:

```go
// internal/di/redis/module.go
func provideRedisClient(cfg Config) (*redis.ClusterClient, error) {
    redisCfg := &cfg.Redis  // Take address of value type
    opts := &redis.ClusterOptions{
        Addrs:    redisCfg.Addrs,
        Password: redisCfg.Password,
    }
    return redis.NewClusterClient(opts), nil
}
```

---

## 5. HTTP DI Module

```go
// internal/di/http/module.go
package http

import (
    "context"
    "net/http"

    "github.com/gin-gonic/gin"
    "go.uber.org/fx"

    commonhttp "gitlab.com/umo-tech-ltd-group/platform/devkit/common/http"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"

    "your-service/internal/config"
    "your-service/internal/core/item"
    itemservice "your-service/internal/services/item"
    httphandlers "your-service/internal/handlers/http"
)

// Module provides the HTTP server as an Fx module.
var Module = fx.Module("http",
    // Provide Gin engine
    fx.Provide(NewGinEngine),

    // Provide domain services
    fx.Provide(NewItemService),

    // Provide HTTP handlers
    fx.Provide(httphandlers.NewHandlers),

    // Provide HTTP server
    fx.Provide(NewHTTPServer),

    // Register lifecycle hooks for HTTP server startup
    fx.Invoke(RegisterHTTPLifecycle),

    // Register shutdown hook with proper priority
    platformfx.ProvideShutdownHook(NewHTTPShutdownHook),
)

// NewGinEngine creates a new Gin engine with middleware.
func NewGinEngine(log logger.Logger) *gin.Engine {
    gin.SetMode(gin.ReleaseMode)
    engine := gin.New()
    middleware := httphandlers.SetupMiddleware(log)
    engine.Use(middleware...)
    return engine
}

// NewItemService creates a new item service instance.
func NewItemService(repo item.Repository, log logger.Logger, provider trace.Provider) *itemservice.Service {
    return itemservice.NewService(repo, log, provider)
}

// NewHTTPServer creates a new HTTP server.
func NewHTTPServer(
    cfg *config.Configuration,
    engine *gin.Engine,
    handlers *httphandlers.Handlers,
    log logger.Logger,
) *http.Server {
    // Setup routes
    httphandlers.SetupRoutes(engine, handlers)

    // Build server using common HTTP utilities
    builder := commonhttp.NewServerBuilder().
        WithAddr(cfg.HTTP.Addr).
        WithEngine(engine).
        WithReadTimeout(cfg.HTTP.ReadTimeout).
        WithWriteTimeout(cfg.HTTP.WriteTimeout).
        WithShutdownTimeout(cfg.HTTP.ShutdownTimeout)

    return builder.Build()
}

// RegisterHTTPLifecycle registers lifecycle hooks for HTTP server startup.
// NOTE: This only has OnStart - shutdown is handled by the shutdown hook!
func RegisterHTTPLifecycle(lc fx.Lifecycle, server *http.Server, log logger.Logger) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            log.Info(ctx, "Starting HTTP server", logger.String("addr", server.Addr))
            go func() {
                if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
                    log.Error(ctx, "HTTP server error", logger.Err(err))
                }
            }()
            return nil
        },
        // NO OnStop here - handled by NewHTTPShutdownHook!
    })
}

// NewHTTPShutdownHook creates a shutdown hook for the HTTP server.
func NewHTTPShutdownHook(server *http.Server, cfg *config.Configuration, log logger.Logger) platformfx.ShutdownHook {
    return platformfx.ServerHook("http-server", func(ctx context.Context) error {
        log.Info(ctx, "Shutting down HTTP server")
        shutdownCtx, cancel := context.WithTimeout(ctx, cfg.HTTP.ShutdownTimeout)
        defer cancel()
        if err := server.Shutdown(shutdownCtx); err != nil {
            log.Error(ctx, "HTTP server shutdown error", logger.Err(err))
            return err
        }
        log.Info(ctx, "HTTP server shutdown complete")
        return nil
    })
}
```

---

## 6. gRPC DI Module

```go
// internal/di/grpc/module.go
package grpc

import (
    "context"
    "net"

    "go.uber.org/fx"
    "google.golang.org/grpc"
    "google.golang.org/grpc/health"
    "google.golang.org/grpc/health/grpc_health_v1"
    "google.golang.org/grpc/reflection"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/grpcerr"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/grpcserver"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    tracegrpc "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace/grpc"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"

    pb "your-service/api/proto/item/v1"
    "your-service/internal/config"
    grpchandlers "your-service/internal/handlers/grpc"
)

// Module provides the gRPC server as an Fx module.
var Module = fx.Module("grpc",
    // Provide gRPC handlers
    fx.Provide(grpchandlers.NewHandlers),

    // Provide gRPC server
    fx.Provide(NewGRPCServer),

    // Register gRPC services
    fx.Invoke(RegisterGRPCServices),

    // Register lifecycle hooks
    fx.Invoke(RegisterGRPCLifecycle),

    // Provide shutdown hook with proper priority
    platformfx.ProvideShutdownHook(NewGRPCShutdownHook),
)

// GRPCServerResult holds the gRPC server and related components.
type GRPCServerResult struct {
    fx.Out
    Server       *grpc.Server
    HealthServer *health.Server
}

// NewGRPCServer creates a new gRPC server with observability interceptors.
func NewGRPCServer(cfg *config.Configuration, log logger.Logger) (GRPCServerResult, error) {
    // Build interceptor chain (order matters - outermost first)
    unaryInterceptors := []grpc.UnaryServerInterceptor{
        // 1. Tracing - creates server span, extracts trace context
        tracegrpc.UnaryServerInterceptor(
            tracegrpc.WithServerSkipper(tracegrpc.SkipHealthChecks()),
        ),
        // 2. Request ID - extracts from metadata or generates new UUID
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

    streamInterceptors := []grpc.StreamServerInterceptor{
        tracegrpc.StreamServerInterceptor(
            tracegrpc.WithServerSkipper(tracegrpc.SkipHealthChecks()),
        ),
        grpcserver.RequestIDStreamInterceptor(),
        grpcserver.LoggingStreamInterceptor(
            grpcserver.WithLoggingLogger(log),
            grpcserver.WithLoggingSkipper(grpcserver.SkipHealthChecks()),
        ),
        grpcserver.MetricsStreamInterceptor(
            grpcserver.WithMetricsSkipper(grpcserver.SkipHealthChecks()),
        ),
        grpcserver.RecoveryStreamInterceptor(
            grpcserver.WithRecoveryLogger(log),
        ),
        grpcerr.MappingStreamInterceptor(),
        grpcserver.ValidationStreamInterceptor(),
    }

    // Build gRPC server
    builder := grpcserver.NewBuilder(cfg.GRPC).
        WithHealthCheck(false).
        WithReflection(false).
        WithUnaryInterceptors(unaryInterceptors...).
        WithStreamInterceptors(streamInterceptors...)

    server, err := builder.Build()
    if err != nil {
        return GRPCServerResult{}, err
    }

    return GRPCServerResult{
        Server:       server,
        HealthServer: health.NewServer(),
    }, nil
}

// RegisterGRPCServices registers all gRPC services with the server.
func RegisterGRPCServices(
    server *grpc.Server,
    healthServer *health.Server,
    handlers *grpchandlers.Handlers,
    cfg *config.Configuration,
) {
    // Register item service
    pb.RegisterItemServiceServer(server, handlers)

    // Register health service
    grpc_health_v1.RegisterHealthServer(server, healthServer)

    // Set initial health status
    healthServer.SetServingStatus("", grpc_health_v1.HealthCheckResponse_SERVING)
    healthServer.SetServingStatus("item.v1.ItemService", grpc_health_v1.HealthCheckResponse_SERVING)

    // Enable reflection for development
    if cfg.GRPC.Reflection {
        reflection.Register(server)
    }
}

// RegisterGRPCLifecycle registers lifecycle hooks for the gRPC server.
// NOTE: This only has OnStart - shutdown is handled by the shutdown hook!
func RegisterGRPCLifecycle(
    lc fx.Lifecycle,
    server *grpc.Server,
    cfg *config.Configuration,
    log logger.Logger,
) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            log.Info(ctx, "Starting gRPC server", logger.String("addr", cfg.GRPC.Addr))
            lis, err := net.Listen("tcp", cfg.GRPC.Addr)
            if err != nil {
                return err
            }
            go func() {
                if err := server.Serve(lis); err != nil {
                    log.Error(ctx, "gRPC server stopped", logger.Err(err))
                }
            }()
            return nil
        },
        // NO OnStop here - handled by NewGRPCShutdownHook!
    })
}

// NewGRPCShutdownHook creates a shutdown hook for the gRPC server.
func NewGRPCShutdownHook(
    server *grpc.Server,
    healthServer *health.Server,
    log logger.Logger,
) platformfx.ShutdownHook {
    return platformfx.ServerHook("grpc-server", func(ctx context.Context) error {
        log.Info(ctx, "Shutting down gRPC server")
        healthServer.SetServingStatus("", grpc_health_v1.HealthCheckResponse_NOT_SERVING)
        stopped := make(chan struct{})
        go func() {
            server.GracefulStop()
            close(stopped)
        }()
        select {
        case <-stopped:
            log.Info(ctx, "gRPC server shutdown complete")
            return nil
        case <-ctx.Done():
            log.Warn(ctx, "gRPC server graceful shutdown timeout, forcing stop")
            server.Stop()
            return ctx.Err()
        }
    })
}
```

---

## 7. PostgreSQL DI Module

### Option A: With pgxpool (raw PostgreSQL)

```go
// internal/di/postgres/module.go
package postgres

import (
    "context"
    "fmt"

    "github.com/jackc/pgx/v5/pgxpool"
    "go.uber.org/fx"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"

    "your-service/internal/config"
    "your-service/internal/core/item"
    itempostgres "your-service/internal/repo/postgres/item"
)

// Module provides the PostgreSQL database as an Fx module.
var Module = fx.Module("postgres",
    // Provide connection pool
    fx.Provide(NewPostgresPool),

    // Provide repository implementations
    fx.Provide(NewItemRepository),

    // Register lifecycle hooks (OnStart only)
    fx.Invoke(RegisterPostgresLifecycle),

    // Register shutdown hook (separate from OnStart)
    platformfx.ProvideShutdownHook(NewPostgresShutdownHook),
)

// NewPostgresPool creates a new PostgreSQL connection pool.
func NewPostgresPool(cfg *config.Configuration, log logger.Logger) (*pgxpool.Pool, error) {
    ctx := context.Background()

    poolConfig, err := pgxpool.ParseConfig(cfg.Postgres.ConnectionString())
    if err != nil {
        return nil, fmt.Errorf("failed to parse postgres config: %w", err)
    }

    pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
    if err != nil {
        return nil, fmt.Errorf("failed to create postgres pool: %w", err)
    }

    log.Info(ctx, "PostgreSQL connection pool created",
        logger.String("host", cfg.Postgres.Host),
        logger.Int("port", cfg.Postgres.Port),
        logger.String("database", cfg.Postgres.Database),
    )

    return pool, nil
}

// RegisterPostgresLifecycle verifies database connection on startup.
func RegisterPostgresLifecycle(lc fx.Lifecycle, pool *pgxpool.Pool, log logger.Logger) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            log.Info(ctx, "Testing PostgreSQL connection")
            if err := pool.Ping(ctx); err != nil {
                return fmt.Errorf("failed to ping postgres: %w", err)
            }
            log.Info(ctx, "PostgreSQL connection verified")
            return nil
        },
        // NO OnStop - handled by shutdown hook!
    })
}

// NewPostgresShutdownHook creates a shutdown hook for PostgreSQL.
func NewPostgresShutdownHook(pool *pgxpool.Pool, log logger.Logger) platformfx.ShutdownHook {
    return platformfx.DatabaseHook("postgres-pool", func(ctx context.Context) error {
        log.Info(ctx, "Closing PostgreSQL connection pool")
        pool.Close()
        log.Info(ctx, "PostgreSQL connection pool closed")
        return nil
    })
}
```

### Option B: With Ent ORM (Recommended)

When using Ent ORM, you need shutdown hooks for BOTH the underlying `*sql.DB` AND the `*ent.Client`:

```go
// internal/di/postgres/module.go
package postgres

import (
    "context"
    "database/sql"
    "fmt"

    "entgo.io/ent/dialect"
    entsql "entgo.io/ent/dialect/sql"
    "github.com/XSAM/otelsql"
    "go.uber.org/fx"
    semconv "go.opentelemetry.io/otel/semconv/v1.4.0"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"

    "your-service/internal/config"
    "your-service/internal/repo"
    "your-service/internal/repo/pq"
    "your-service/internal/repo/pq/ent"
)

// Module provides the PostgreSQL database with Ent ORM as an Fx module.
var Module = fx.Module("postgres",
    fx.Provide(NewPostgres),      // *sql.DB with OTel instrumentation
    fx.Provide(NewEntClient),     // *ent.Client
    fx.Provide(NewRepo),          // *pq.Repo
    fx.Provide(NewInstrumentedRepo),
    
    // IMPORTANT: Shutdown hooks for BOTH sql.DB and ent.Client
    platformfx.ProvideShutdownHook(NewDBShutdownHook),
    platformfx.ProvideShutdownHook(NewEntClientShutdownHook),
)

// NewPostgres creates a new *sql.DB with OTel instrumentation.
func NewPostgres(cfg *config.Config, log logger.Logger) (*sql.DB, error) {
    db, err := otelsql.Open("postgres", cfg.Postgres.ConnectionString(),
        otelsql.WithAttributes(semconv.DBSystemPostgreSQL),
        otelsql.WithDBName(cfg.Postgres.Name),
    )
    if err != nil {
        return nil, fmt.Errorf("failed to open postgres: %w", err)
    }

    db.SetMaxOpenConns(cfg.Postgres.MaxOpenConns)
    db.SetMaxIdleConns(cfg.Postgres.MaxIdleConns)
    db.SetConnMaxLifetime(cfg.Postgres.MaxConnLifetime)

    // Register DB stats metrics (optional but recommended)
    if err := otelsql.RegisterDBStatsMetrics(db, otelsql.WithAttributes(
        semconv.DBSystemPostgreSQL,
    )); err != nil {
        log.Warn(context.Background(), "failed to register db stats metrics", logger.Err(err))
    }

    return db, nil
}

// NewEntClient creates an Ent client from the sql.DB.
// NOTE: No fx.Lifecycle.OnStop here - handled by shutdown hook!
func NewEntClient(db *sql.DB) *ent.Client {
    return ent.NewClient(ent.Driver(entsql.OpenDB(dialect.Postgres, db)))
}

// NewRepo creates the base repository.
func NewRepo(client *ent.Client, log logger.Logger) *pq.Repo {
    return pq.NewRepo(client, log.Named("pq_repo"))
}

// NewInstrumentedRepo creates the instrumented repository wrapper.
func NewInstrumentedRepo(r *pq.Repo, log logger.Logger) repo.Repo {
    return pq.NewInstrumentedRepo(r, log)
}

// NewDBShutdownHook creates a shutdown hook for the raw sql.DB connection.
func NewDBShutdownHook(db *sql.DB) platformfx.ShutdownHook {
    return platformfx.DatabaseHook("postgres-db", func(ctx context.Context) error {
        return db.Close()
    })
}

// NewEntClientShutdownHook creates a shutdown hook for the Ent ORM client.
func NewEntClientShutdownHook(client *ent.Client) platformfx.ShutdownHook {
    return platformfx.DatabaseHook("ent-client", func(ctx context.Context) error {
        return client.Close()
    })
}
```

> **Important**: When using Ent ORM, always register shutdown hooks for BOTH `*sql.DB` and `*ent.Client`. Missing the `*sql.DB` shutdown hook can cause connection leaks. See `references/shutdown-patterns.md` for more details.

---

## 8. HTTP Middleware

```go
// internal/handlers/http/middleware.go
package http

import (
    "github.com/gin-gonic/gin"

    commonhttp "gitlab.com/umo-tech-ltd-group/platform/devkit/common/http"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    tracehttp "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace/http"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/xctx"
)

// SetupMiddleware configures and returns common middleware for the HTTP server.
func SetupMiddleware(log logger.Logger) []commonhttp.HandlerFunc {
    return []commonhttp.HandlerFunc{
        // 1. Recovery middleware to handle panics
        commonhttp.RecoveryMiddleware(log),

        // 2. Tracing middleware to create spans for HTTP requests
        tracehttp.TracingMiddleware(
            tracehttp.WithSkipper(tracehttp.SkipHealthChecks()),
            tracehttp.WithTraceIDHeader("X-Trace-Id"),
        ),

        // 3. Context enrichment middleware
        ContextEnrichmentMiddleware(),

        // 4. Logger middleware to log all requests
        commonhttp.LoggerMiddleware(log),

        // 5. CORS middleware
        commonhttp.CORSMiddleware(
            []string{"*"},
            []string{"GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"},
            []string{"Origin", "Content-Type", "Accept", "Authorization"},
        ),
    }
}

// ContextEnrichmentMiddleware enriches the request context with common values.
func ContextEnrichmentMiddleware() commonhttp.HandlerFunc {
    return func(c *gin.Context) {
        ctx := c.Request.Context()

        // Extract or generate request ID
        requestID := c.GetHeader("X-Request-Id")
        if requestID == "" {
            requestID = xctx.GenerateRequestID()
        }
        ctx = xctx.WithRequestID(ctx, requestID)
        c.Header("X-Request-Id", requestID)

        // Extract tenant ID if present
        if tenantID := c.GetHeader("X-Tenant-Id"); tenantID != "" {
            ctx = xctx.WithTenantID(ctx, tenantID)
        }

        // Extract user ID if present
        if userID := c.GetHeader("X-User-Id"); userID != "" {
            ctx = xctx.WithUserID(ctx, userID)
        }

        c.Request = c.Request.WithContext(ctx)
        c.Next()
    }
}
```

---

## 9. HTTP Router

```go
// internal/handlers/http/router.go
package http

import (
    "net/http"

    "github.com/gin-gonic/gin"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

// Handlers aggregates all domain-specific handlers.
type Handlers struct {
    Item *ItemHandlers
}

// NewHandlers creates a new aggregated Handlers instance.
func NewHandlers(item *ItemHandlers) *Handlers {
    return &Handlers{Item: item}
}

// SetupRoutes configures all HTTP routes for the service.
func SetupRoutes(engine *gin.Engine, handlers *Handlers) {
    // Health check endpoints
    engine.GET("/health", HealthCheck)
    engine.GET("/ready", ReadyCheck)

    // Prometheus metrics endpoint
    engine.GET("/metrics", gin.WrapH(promhttp.Handler()))

    // API v1 routes
    v1 := engine.Group("/api/v1")
    {
        setupItemRoutes(v1, handlers.Item)
    }
}

// setupItemRoutes configures item-related routes.
func setupItemRoutes(rg *gin.RouterGroup, h *ItemHandlers) {
    items := rg.Group("/items")
    {
        items.POST("", h.Create)
        items.GET("", h.List)
        items.GET("/:id", h.Get)
        items.PUT("/:id", h.Update)
        items.DELETE("/:id", h.Delete)
    }
}

// HealthCheck handles health check requests.
func HealthCheck(c *gin.Context) {
    c.JSON(http.StatusOK, gin.H{"status": "healthy"})
}

// ReadyCheck handles readiness check requests.
func ReadyCheck(c *gin.Context) {
    c.JSON(http.StatusOK, gin.H{"status": "ready"})
}
```
