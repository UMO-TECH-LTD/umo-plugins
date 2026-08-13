# Shutdown Management Patterns

Comprehensive guide for implementing graceful shutdown in Go microservices using `devkit/common/platformfx`.

## Table of Contents

1. [Overview](#1-overview)
2. [Priority Ordering](#2-priority-ordering)
3. [Key Pattern: Separate OnStart from Shutdown](#3-key-pattern-separate-onstart-from-shutdown)
4. [Database Shutdown](#4-database-shutdown)
5. [Server Shutdown (HTTP/gRPC)](#5-server-shutdown-httpgrpc)
6. [Temporal Shutdown](#6-temporal-shutdown)
7. [Kafka Shutdown](#7-kafka-shutdown)
8. [Redis Shutdown](#8-redis-shutdown)
9. [Complete Module Examples](#9-complete-module-examples)
10. [Common Mistakes](#10-common-mistakes)

---

## 1. Overview

The `platformfx` module provides centralized shutdown management with priority-based ordering. Components are shut down in reverse registration order within each priority level.

### Why Use platformfx Shutdown Hooks?

Using `platformfx.ProvideShutdownHook` instead of direct `fx.Lifecycle.OnStop`:

- **Priority ordering**: Servers stop before databases
- **Centralized management**: Single point for shutdown coordination
- **Timeout handling**: Built-in timeout support
- **Logging**: Automatic shutdown progress logging
- **Consistency**: Same pattern across all components

### Basic Pattern

```go
var Module = fx.Module("component",
    fx.Provide(NewComponent),
    fx.Invoke(StartComponent),                              // OnStart only
    platformfx.ProvideShutdownHook(NewComponentShutdownHook), // Shutdown
)
```

---

## 2. Priority Ordering

Shutdown hooks run in priority order (lower = shutdown first):

| Priority | Constant               | Components                    | Rationale                              |
|----------|------------------------|-------------------------------|----------------------------------------|
| 10       | `PriorityServer`       | HTTP, gRPC servers            | Stop accepting new requests first      |
| 20       | `PriorityWorker`       | Background workers            | Stop processing after servers          |
| 40       | `PriorityCache`        | Redis, in-memory caches       | Stop cache before database             |
| 60       | `PriorityDatabase`     | PostgreSQL, Ent, Temporal     | Close DB connections after services    |
| 90       | `PriorityTracer`       | Tracing exporters             | Flush traces before logger             |
| 100      | `PriorityLogger`       | Logger                        | Always last                            |

### Hook Helper Functions

```go
// For servers (HTTP, gRPC) - Priority 10
platformfx.ServerHook("name", shutdownFunc)

// For databases - Priority 60
platformfx.DatabaseHook("name", shutdownFunc)

// Custom priority
platformfx.ShutdownHook{
    Name:     "custom-component",
    Priority: platformfx.PriorityWorker, // or any int
    Shutdown: shutdownFunc,
}
```

---

## 3. Key Pattern: Separate OnStart from Shutdown

**Critical Pattern**: Use `fx.Invoke` for startup and `platformfx.ProvideShutdownHook` for shutdown.

### Why Separate?

1. **Priority control**: `fx.Lifecycle.OnStop` doesn't support priority ordering
2. **Centralized management**: All shutdowns go through the shutdown manager
3. **Consistent logging**: Shutdown manager logs progress
4. **Timeout handling**: Centralized timeout management

### Before (Anti-pattern)

```go
// DON'T DO THIS - No priority ordering, no centralized management
func RegisterLifecycle(lc fx.Lifecycle, server *grpc.Server) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            go server.Serve(lis)
            return nil
        },
        OnStop: func(ctx context.Context) error {
            server.GracefulStop()
            return nil
        },
    })
}
```

### After (Correct Pattern)

```go
// DO THIS - Separate startup from shutdown with priorities
var Module = fx.Module("grpc",
    fx.Provide(NewHandler),
    fx.Invoke(StartHandler),                              // OnStart only
    platformfx.ProvideShutdownHook(NewHandlerShutdownHook), // Shutdown with priority
)

func StartHandler(lc fx.Lifecycle, handler *Handler) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            return handler.Start(ctx)
        },
        // NO OnStop here!
    })
}

func NewHandlerShutdownHook(handler *Handler) platformfx.ShutdownHook {
    return platformfx.ServerHook("grpc-server", handler.Stop)
}
```

---

## 4. Database Shutdown

### PostgreSQL with sql.DB

Both `*sql.DB` and `*ent.Client` need shutdown hooks:

```go
// internal/di/postgres/module.go
package postgres

import (
    "context"
    "database/sql"

    "go.uber.org/fx"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"
    
    "your-service/internal/repo/pq/ent"
)

var Module = fx.Module("postgres",
    fx.Provide(NewPostgres),      // *sql.DB
    fx.Provide(NewEntClient),     // *ent.Client
    fx.Provide(NewRepo),          // Repository
    fx.Provide(NewInstrumentedRepo),
    
    // Shutdown hooks for both DB and Ent client
    platformfx.ProvideShutdownHook(NewDBShutdownHook),
    platformfx.ProvideShutdownHook(NewEntClientShutdownHook),
)

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

### PostgreSQL with pgxpool

```go
func NewPoolShutdownHook(pool *pgxpool.Pool) platformfx.ShutdownHook {
    return platformfx.DatabaseHook("postgres-pool", func(ctx context.Context) error {
        pool.Close()
        return nil
    })
}
```

### Important: Remove OnStop from Providers

If your `NewEntClient` function has an `fx.Lifecycle.OnStop`, remove it:

```go
// BEFORE - Has OnStop (remove this)
func NewEntClient(lc fx.Lifecycle, db *sql.DB) *ent.Client {
    client := ent.NewClient(ent.Driver(entsql.OpenDB(dialect.Postgres, db)))
    
    lc.Append(fx.Hook{
        OnStop: func(ctx context.Context) error {
            return client.Close()  // REMOVE THIS
        },
    })
    
    return client
}

// AFTER - No OnStop, use shutdown hook instead
func NewEntClient(db *sql.DB) *ent.Client {
    return ent.NewClient(ent.Driver(entsql.OpenDB(dialect.Postgres, db)))
}
```

---

## 5. Server Shutdown (HTTP/gRPC)

### gRPC Server

```go
// internal/di/grpc/module.go
var Module = fx.Module("grpc",
    fx.Provide(NewHandler),
    fx.Invoke(StartHandler),
    platformfx.ProvideShutdownHook(NewHandlerShutdownHook),
)

// StartHandler registers only the OnStart hook.
func StartHandler(lc fx.Lifecycle, handler *grpchandler.Handler) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            return handler.Start(ctx)
        },
    })
}

// NewHandlerShutdownHook creates a shutdown hook with server priority.
func NewHandlerShutdownHook(handler *grpchandler.Handler) platformfx.ShutdownHook {
    return platformfx.ServerHook("grpc-server", handler.Stop)
}
```

### HTTP Server

```go
// internal/di/http/module.go
var Module = fx.Module("http",
    fx.Provide(NewInfraServer),
    fx.Invoke(StartInfraServer),
    platformfx.ProvideShutdownHook(NewInfraServerShutdownHook),
)

// StartInfraServer registers only the OnStart hook.
func StartInfraServer(lc fx.Lifecycle, server *infrahttp.InfraServer) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            return server.Start()
        },
    })
}

// NewInfraServerShutdownHook creates a shutdown hook for HTTP server.
func NewInfraServerShutdownHook(server *infrahttp.InfraServer) platformfx.ShutdownHook {
    return platformfx.ServerHook("http-infra", server.Stop)
}
```

---

## 6. Temporal Shutdown

Temporal services have multiple components that need separate shutdown hooks:

```go
// internal/di/temporal/module.go
var Module = fx.Module("temporal",
    fx.Provide(NewClient),
    fx.Provide(NewWorker),
    fx.Provide(NewNamespaceClient),
    
    // Shutdown hooks for all Temporal components
    platformfx.ProvideShutdownHook(NewWorkerShutdownHook),
    platformfx.ProvideShutdownHook(NewClientShutdownHook),
    platformfx.ProvideShutdownHook(NewNamespaceClientShutdownHook),
)

// NewWorkerShutdownHook stops the Temporal worker.
func NewWorkerShutdownHook(w worker.Worker) platformfx.ShutdownHook {
    return platformfx.DatabaseHook("temporal-worker", func(ctx context.Context) error {
        w.Stop()
        return nil
    })
}

// NewClientShutdownHook closes the Temporal client.
func NewClientShutdownHook(client temporalclient.Client) platformfx.ShutdownHook {
    return platformfx.DatabaseHook("temporal-client", func(ctx context.Context) error {
        client.Close()
        return nil
    })
}

// NewNamespaceClientShutdownHook closes the Temporal namespace client.
func NewNamespaceClientShutdownHook(client temporalclient.NamespaceClient) platformfx.ShutdownHook {
    return platformfx.DatabaseHook("temporal-ns-client", func(ctx context.Context) error {
        client.Close()
        return nil
    })
}
```

### Temporal with OnStart Hooks

If Temporal components need OnStart (e.g., namespace registration, worker start):

```go
// NewNamespaceClient creates the namespace client with startup registration.
func NewNamespaceClient(
    lc fx.Lifecycle,
    cfg *config.Config,
    log logger.Logger,
) (temporalclient.NamespaceClient, error) {
    client, err := temporalclient.NewNamespaceClient(...)
    if err != nil {
        return nil, err
    }

    // Keep OnStart for namespace registration
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            return registerNamespace(ctx, client, cfg.Temporal.Namespace)
        },
        // NO OnStop - handled by shutdown hook
    })

    return client, nil
}

// NewWorker creates the worker with startup.
func NewWorker(
    lc fx.Lifecycle,
    client temporalclient.Client,
    log logger.Logger,
) worker.Worker {
    w := worker.New(client, taskQueue, worker.Options{})
    
    // Keep OnStart for worker start
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            return w.Start()
        },
        // NO OnStop - handled by shutdown hook
    })
    
    return w
}
```

---

## 7. Kafka Shutdown

```go
// internal/di/kafka/module.go
var Module = fx.Module("kafka",
    fx.Provide(NewProducer),
    fx.Provide(NewConsumer),
    platformfx.ProvideShutdownHook(NewProducerShutdownHook),
    platformfx.ProvideShutdownHook(NewConsumerShutdownHook),
)

func NewProducerShutdownHook(producer sarama.SyncProducer) platformfx.ShutdownHook {
    return platformfx.DatabaseHook("kafka-producer", func(ctx context.Context) error {
        return producer.Close()
    })
}

func NewConsumerShutdownHook(consumer sarama.ConsumerGroup) platformfx.ShutdownHook {
    return platformfx.DatabaseHook("kafka-consumer", func(ctx context.Context) error {
        return consumer.Close()
    })
}
```

---

## 8. Redis Shutdown

```go
// internal/di/redis/module.go
var Module = fx.Module("redis",
    fx.Provide(NewRedisClient),
    platformfx.ProvideShutdownHook(NewRedisShutdownHook),
)

func NewRedisShutdownHook(client *redis.Client) platformfx.ShutdownHook {
    return platformfx.ShutdownHook{
        Name:     "redis-client",
        Priority: platformfx.PriorityCache, // Priority 40
        Shutdown: func(ctx context.Context) error {
            return client.Close()
        },
    }
}
```

---

## 9. Complete Module Examples

### Complete PostgreSQL Module with Ent

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

var Module = fx.Module("postgres",
    fx.Provide(NewPostgres),
    fx.Provide(NewEntClient),
    fx.Provide(NewRepo),
    fx.Provide(NewInstrumentedRepo),
    platformfx.ProvideShutdownHook(NewDBShutdownHook),
    platformfx.ProvideShutdownHook(NewEntClientShutdownHook),
)

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

    if err := otelsql.RegisterDBStatsMetrics(db, otelsql.WithAttributes(
        semconv.DBSystemPostgreSQL,
    )); err != nil {
        log.Warn(context.Background(), "failed to register db stats metrics", logger.Err(err))
    }

    return db, nil
}

func NewEntClient(db *sql.DB) *ent.Client {
    return ent.NewClient(ent.Driver(entsql.OpenDB(dialect.Postgres, db)))
}

func NewRepo(client *ent.Client, log logger.Logger) *pq.Repo {
    return pq.NewRepo(client, log)
}

func NewInstrumentedRepo(r *pq.Repo, log logger.Logger) repo.Repo {
    return pq.NewInstrumentedRepo(r, log)
}

func NewDBShutdownHook(db *sql.DB) platformfx.ShutdownHook {
    return platformfx.DatabaseHook("postgres-db", func(ctx context.Context) error {
        return db.Close()
    })
}

func NewEntClientShutdownHook(client *ent.Client) platformfx.ShutdownHook {
    return platformfx.DatabaseHook("ent-client", func(ctx context.Context) error {
        return client.Close()
    })
}
```

### Complete gRPC Module

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
    fx.Provide(NewHandler),
    fx.Invoke(StartHandler),
    platformfx.ProvideShutdownHook(NewHandlerShutdownHook),
)

func NewHandler(counterpartySvc counterparty.Service) *grpchandler.Handler {
    return grpchandler.NewHandler(counterpartySvc)
}

func StartHandler(lc fx.Lifecycle, handler *grpchandler.Handler) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            return handler.Start(ctx)
        },
    })
}

func NewHandlerShutdownHook(handler *grpchandler.Handler) platformfx.ShutdownHook {
    return platformfx.ServerHook("grpc-server", handler.Stop)
}
```

---

## 10. Common Mistakes

### Mistake 1: Using OnStop for Shutdown

```go
// WRONG - No priority ordering
lc.Append(fx.Hook{
    OnStop: func(ctx context.Context) error {
        return db.Close()
    },
})

// CORRECT - Use shutdown hook
platformfx.ProvideShutdownHook(NewDBShutdownHook)
```

### Mistake 2: Missing Shutdown for sql.DB

```go
// WRONG - Only closes Ent, not underlying sql.DB
var Module = fx.Module("postgres",
    fx.Provide(NewPostgres),    // *sql.DB - MISSING SHUTDOWN!
    fx.Provide(NewEntClient),
    platformfx.ProvideShutdownHook(NewEntClientShutdownHook),
)

// CORRECT - Shutdown hooks for both
var Module = fx.Module("postgres",
    fx.Provide(NewPostgres),
    fx.Provide(NewEntClient),
    platformfx.ProvideShutdownHook(NewDBShutdownHook),        // sql.DB
    platformfx.ProvideShutdownHook(NewEntClientShutdownHook), // ent.Client
)
```

### Mistake 3: Wrong Priority for Components

```go
// WRONG - Database at server priority shuts down before servers finish
return platformfx.ServerHook("postgres-db", db.Close) // Priority 10!

// CORRECT - Use DatabaseHook for databases
return platformfx.DatabaseHook("postgres-db", func(ctx context.Context) error {
    return db.Close()
}) // Priority 60
```

### Mistake 4: Forgetting to Remove OnStop After Migration

```go
// WRONG - Both OnStop and shutdown hook exist
func NewEntClient(lc fx.Lifecycle, db *sql.DB) *ent.Client {
    client := ent.NewClient(...)
    lc.Append(fx.Hook{
        OnStop: func(ctx context.Context) error {
            return client.Close() // This will run AND the shutdown hook!
        },
    })
    return client
}

// CORRECT - Remove OnStop, only use shutdown hook
func NewEntClient(db *sql.DB) *ent.Client {
    return ent.NewClient(...)
}
```

### Mistake 5: Not Handling Close Methods That Don't Return Errors

```go
// Some Close methods don't return errors
// WRONG - Causes compile error
return platformfx.DatabaseHook("temporal-client", client.Close)

// CORRECT - Wrap in function that returns error
return platformfx.DatabaseHook("temporal-client", func(ctx context.Context) error {
    client.Close()
    return nil
})
```

---

## Summary

1. **Always use `platformfx.ProvideShutdownHook`** for shutdown logic
2. **Separate OnStart from Shutdown** - Use `fx.Invoke` for startup, shutdown hook for cleanup
3. **Use appropriate priorities** - `ServerHook` for servers, `DatabaseHook` for databases
4. **Remember all components** - Both `*sql.DB` AND `*ent.Client` need shutdown hooks
5. **Remove OnStop hooks** - After migrating to shutdown hooks, remove old `fx.Lifecycle.OnStop` code
