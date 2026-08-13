# Redis Patterns

This document describes patterns for using Redis for caching and ephemeral data storage in Go microservices.

## Overview

Redis is used for:
- **Caching**: Frequently accessed data with TTL
- **Ephemeral storage**: Workflow execution contexts, session data
- **Rate limiting**: Distributed rate limiting (see separate documentation)
- **Distributed locking**: Cross-instance coordination

**When to use Redis vs PostgreSQL:**
| Use Case | Redis | PostgreSQL |
|----------|-------|------------|
| Ephemeral data (sessions, contexts) | Yes | No |
| Frequently read, rarely written | Yes | Backup |
| Complex queries | No | Yes |
| ACID transactions | No | Yes |
| Data that can be regenerated | Yes | No |

## Directory Structure

```
internal/repo/redis/
├── repo.go                       # Base repository
├── types.go                      # Redis-specific types (for JSON)
├── {{entity}}.go                 # Entity-specific operations
├── instrumentation.go            # Observability wrapper
└── keys.go                       # Key naming utilities
```

## Configuration Pattern

### Config Struct

```go
// internal/config/redis.go
package config

import "time"

// RedisConfig holds Redis connection settings.
type RedisConfig struct {
    Host         string        `mapstructure:"host" validate:"required"`
    Port         string        `mapstructure:"port" validate:"required"`
    Password     string        `mapstructure:"password"`
    DB           int           `mapstructure:"db"`
    MaxRetries   int           `mapstructure:"max_retries"`
    PoolSize     int           `mapstructure:"pool_size"`
    MinIdleConns int           `mapstructure:"min_idle_conns"`
    DialTimeout  time.Duration `mapstructure:"dial_timeout"`
    ReadTimeout  time.Duration `mapstructure:"read_timeout"`
    WriteTimeout time.Duration `mapstructure:"write_timeout"`
}

// Addr returns the Redis address.
func (c *RedisConfig) Addr() string {
    return c.Host + ":" + c.Port
}

// DefaultRedisConfig returns default Redis configuration.
func DefaultRedisConfig() *RedisConfig {
    return &RedisConfig{
        Host:         "localhost",
        Port:         "6379",
        DB:           0,
        MaxRetries:   3,
        PoolSize:     10,
        MinIdleConns: 5,
        DialTimeout:  5 * time.Second,
        ReadTimeout:  3 * time.Second,
        WriteTimeout: 3 * time.Second,
    }
}
```

### Configuration YAML

```yaml
# config/configuration.yaml
redis:
  host: localhost
  port: "6379"
  password: ""
  db: 0
  max_retries: 3
  pool_size: 10
  min_idle_conns: 5
  dial_timeout: 5s
  read_timeout: 3s
  write_timeout: 3s
```

## Client Initialization with Fx

```go
// internal/di/redis/module.go
package redis

import (
    "context"
    "fmt"

    "github.com/redis/go-redis/v9"
    "go.uber.org/fx"

    "{{module}}/internal/config"
    redisrepo "{{module}}/internal/repo/redis"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"
)

// Module provides Redis dependencies.
var Module = fx.Module("redis",
    fx.Provide(NewClient),
    fx.Provide(redisrepo.NewRepo),
    fx.Provide(NewInstrumentedRepo),
    platformfx.ProvideShutdownHook(NewShutdownHook),
)

// NewClient creates a Redis client with the provided configuration.
func NewClient(cfg *config.Configuration, lc fx.Lifecycle) (*redis.Client, error) {
    client := redis.NewClient(&redis.Options{
        Addr:         cfg.Redis.Addr(),
        Password:     cfg.Redis.Password,
        DB:           cfg.Redis.DB,
        MaxRetries:   cfg.Redis.MaxRetries,
        PoolSize:     cfg.Redis.PoolSize,
        MinIdleConns: cfg.Redis.MinIdleConns,
        DialTimeout:  cfg.Redis.DialTimeout,
        ReadTimeout:  cfg.Redis.ReadTimeout,
        WriteTimeout: cfg.Redis.WriteTimeout,
    })

    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            // Verify connection on startup
            if err := client.Ping(ctx).Err(); err != nil {
                return fmt.Errorf("failed to ping Redis: %w", err)
            }
            return nil
        },
    })

    return client, nil
}

// NewShutdownHook creates a shutdown hook for Redis.
func NewShutdownHook(client *redis.Client) platformfx.ShutdownHook {
    return platformfx.ShutdownHook{
        Name:     "redis",
        Priority: platformfx.PriorityCache, // Close after servers, before database
        Shutdown: func(ctx context.Context) error {
            return client.Close()
        },
    }
}

// NewInstrumentedRepo creates an instrumented Redis repository.
func NewInstrumentedRepo(repo *redisrepo.Repo, log logger.Logger) *redisrepo.InstrumentedRepo {
    return redisrepo.NewInstrumentedRepo(repo, log)
}
```

## Repository Pattern

### Base Repository

```go
// internal/repo/redis/repo.go
package redis

import (
    "github.com/redis/go-redis/v9"
)

// Repo provides Redis repository operations.
type Repo struct {
    client *redis.Client
}

// NewRepo creates a new Redis repository.
func NewRepo(client *redis.Client) *Repo {
    return &Repo{
        client: client,
    }
}
```

### Key Naming Utilities

```go
// internal/repo/redis/keys.go
package redis

import (
    "fmt"
    "strings"
    "time"
)

// Key prefixes and TTLs for different entity types.
const (
    // Workflow execution contexts
    WorkflowExecutionContextKeyPrefix = "workflow:execution:context:"
    WorkflowExecutionContextTTL       = 7 * 24 * time.Hour // 7 days

    // Product cache
    ProductCacheKeyPrefix = "product:cache:"
    ProductCacheTTL       = 1 * time.Hour

    // Session data
    SessionKeyPrefix = "session:"
    SessionTTL       = 24 * time.Hour
)

// KeyBuilder helps construct consistent Redis keys.
type KeyBuilder struct {
    prefix string
}

// NewKeyBuilder creates a new key builder with the given prefix.
func NewKeyBuilder(prefix string) *KeyBuilder {
    return &KeyBuilder{prefix: prefix}
}

// Build constructs a key from the prefix and provided parts.
func (kb *KeyBuilder) Build(parts ...string) string {
    return kb.prefix + strings.Join(parts, ":")
}

// Example usage:
// builder := NewKeyBuilder(ProductCacheKeyPrefix)
// key := builder.Build(tenantID, productID) // "product:cache:tenant-1:prod-123"
```

### Redis-Specific Types

```go
// internal/repo/redis/types.go
package redis

import "time"

// WorkflowExecutionContext is the Redis representation of a workflow execution context.
// Note: This is separate from the domain type to allow Redis-specific serialization.
type WorkflowExecutionContext struct {
    ID                string              `json:"id"`
    WorkflowID        string              `json:"workflow_id"`
    WorkflowVersion   string              `json:"workflow_version"`
    CurrentActivityID string              `json:"current_activity_id"`
    Input             map[string]any      `json:"input,omitempty"`
    Output            map[string]any      `json:"output,omitempty"`
    ActivityContexts  map[string]any      `json:"activity_contexts,omitempty"`
    IsCompleted       bool                `json:"is_completed"`
    CreatedAt         time.Time           `json:"created_at"`
    UpdatedAt         time.Time           `json:"updated_at"`
}

// ProductCache is the Redis representation of a cached product.
type ProductCache struct {
    ID          string         `json:"id"`
    Name        string         `json:"name"`
    Description string         `json:"description"`
    Price       float64        `json:"price"`
    Quantity    int            `json:"quantity"`
    Status      string         `json:"status"`
    Attributes  map[string]any `json:"attributes,omitempty"`
    CachedAt    time.Time      `json:"cached_at"`
}
```

### Entity Operations

```go
// internal/repo/redis/workflow_execution_contexts.go
package redis

import (
    "context"
    "encoding/json"
    "fmt"

    "github.com/redis/go-redis/v9"

    "{{module}}/internal/core/execution"
)

// SaveWorkflowExecutionContext saves a workflow execution context to Redis.
func (r *Repo) SaveWorkflowExecutionContext(ctx context.Context, ec *execution.WorkflowExecutionContext) error {
    // Convert domain type to Redis type
    redisEC := coreToRedisWorkflowExecutionContext(ec)

    // Serialize to JSON
    data, err := json.Marshal(redisEC)
    if err != nil {
        return fmt.Errorf("failed to marshal workflow execution context: %w", err)
    }

    // Build key and save with TTL
    key := WorkflowExecutionContextKeyPrefix + ec.ID
    err = r.client.Set(ctx, key, data, WorkflowExecutionContextTTL).Err()
    if err != nil {
        return fmt.Errorf("failed to save workflow execution context: %w", err)
    }

    return nil
}

// GetWorkflowExecutionContext retrieves a workflow execution context from Redis.
func (r *Repo) GetWorkflowExecutionContext(ctx context.Context, id string) (*execution.WorkflowExecutionContext, error) {
    key := WorkflowExecutionContextKeyPrefix + id

    data, err := r.client.Get(ctx, key).Bytes()
    if err != nil {
        if err == redis.Nil {
            return nil, nil // Not found
        }
        return nil, fmt.Errorf("failed to get workflow execution context: %w", err)
    }

    var redisEC WorkflowExecutionContext
    if err := json.Unmarshal(data, &redisEC); err != nil {
        return nil, fmt.Errorf("failed to unmarshal workflow execution context: %w", err)
    }

    // Convert Redis type to domain type
    return redisToWorkflowExecutionContext(&redisEC), nil
}

// DeleteWorkflowExecutionContext deletes a workflow execution context from Redis.
func (r *Repo) DeleteWorkflowExecutionContext(ctx context.Context, id string) error {
    key := WorkflowExecutionContextKeyPrefix + id
    return r.client.Del(ctx, key).Err()
}
```

### Type Conversion (Mappers)

```go
// internal/repo/redis/mappers.go
package redis

import (
    "time"

    "{{module}}/internal/core/execution"
)

// coreToRedisWorkflowExecutionContext converts domain type to Redis type.
func coreToRedisWorkflowExecutionContext(ec *execution.WorkflowExecutionContext) *WorkflowExecutionContext {
    return &WorkflowExecutionContext{
        ID:                ec.ID,
        WorkflowID:        ec.Workflow.ID,
        WorkflowVersion:   ec.Workflow.Version,
        CurrentActivityID: ec.CurrentActivityID,
        Input:             ec.Input,
        Output:            ec.Output,
        ActivityContexts:  ec.ActivityContexts,
        IsCompleted:       ec.IsCompleted,
        CreatedAt:         ec.CreatedAt,
        UpdatedAt:         time.Now(),
    }
}

// redisToWorkflowExecutionContext converts Redis type to domain type.
func redisToWorkflowExecutionContext(r *WorkflowExecutionContext) *execution.WorkflowExecutionContext {
    return &execution.WorkflowExecutionContext{
        ID: r.ID,
        Workflow: &execution.WorkflowReference{
            ID:      r.WorkflowID,
            Version: r.WorkflowVersion,
        },
        CurrentActivityID: r.CurrentActivityID,
        Input:             r.Input,
        Output:            r.Output,
        ActivityContexts:  r.ActivityContexts,
        IsCompleted:       r.IsCompleted,
        CreatedAt:         r.CreatedAt,
    }
}
```

## Instrumentation Pattern

Use devkit/common for tracing and logging.

```go
// internal/repo/redis/instrumentation.go
package redis

import (
    "context"

    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/codes"

    "{{module}}/internal/core/execution"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace"
)

// InstrumentedRepo wraps Repo with tracing and logging.
type InstrumentedRepo struct {
    repo   *Repo
    logger logger.Logger
}

// NewInstrumentedRepo creates a new instrumented Redis repository.
func NewInstrumentedRepo(repo *Repo, logger logger.Logger) *InstrumentedRepo {
    return &InstrumentedRepo{
        repo:   repo,
        logger: logger,
    }
}

// SaveWorkflowExecutionContext saves with instrumentation.
func (r *InstrumentedRepo) SaveWorkflowExecutionContext(
    ctx context.Context,
    ec *execution.WorkflowExecutionContext,
) error {
    ctx, span := trace.Instrument(ctx, r.SaveWorkflowExecutionContext)
    defer span.End()

    span.SetAttributes(
        attribute.String("execution.id", ec.ID),
        attribute.String("workflow.id", ec.Workflow.ID),
        attribute.String("operation", "redis.set"),
    )

    log := r.logger.With(
        logger.String("execution_id", ec.ID),
        logger.String("workflow_id", ec.Workflow.ID),
    )
    log.Debug(ctx, "saving workflow execution context to redis")

    err := r.repo.SaveWorkflowExecutionContext(ctx, ec)

    if err != nil {
        log.Error(ctx, "failed to save workflow execution context to redis",
            logger.Error(err),
        )
        span.RecordError(err)
        span.SetStatus(codes.Error, "failed to save to redis")
        return err
    }

    log.Debug(ctx, "workflow execution context saved to redis successfully")
    span.SetStatus(codes.Ok, "saved to redis")
    return nil
}

// GetWorkflowExecutionContext gets with instrumentation.
func (r *InstrumentedRepo) GetWorkflowExecutionContext(
    ctx context.Context,
    id string,
) (*execution.WorkflowExecutionContext, error) {
    ctx, span := trace.Instrument(ctx, r.GetWorkflowExecutionContext)
    defer span.End()

    span.SetAttributes(
        attribute.String("execution.id", id),
        attribute.String("operation", "redis.get"),
    )

    log := r.logger.With(logger.String("execution_id", id))
    log.Debug(ctx, "getting workflow execution context from redis")

    ec, err := r.repo.GetWorkflowExecutionContext(ctx, id)

    if err != nil {
        log.Error(ctx, "failed to get workflow execution context from redis",
            logger.Error(err),
        )
        span.RecordError(err)
        span.SetStatus(codes.Error, "failed to get from redis")
        return nil, err
    }

    if ec == nil {
        log.Debug(ctx, "workflow execution context not found in redis")
        span.SetStatus(codes.Ok, "not found")
        return nil, nil
    }

    log.Debug(ctx, "workflow execution context retrieved from redis")
    span.SetStatus(codes.Ok, "retrieved from redis")
    return ec, nil
}
```

## Caching Patterns

### Cache-Aside Pattern

```go
// internal/services/product/cached.go
package product

import (
    "context"
    "time"

    productcore "{{module}}/internal/core/product"
)

// CachedService wraps a service with caching.
type CachedService struct {
    service Service
    cache   Cache
    ttl     time.Duration
}

// Cache interface for product caching.
type Cache interface {
    Get(ctx context.Context, id string) (*productcore.Product, error)
    Set(ctx context.Context, product *productcore.Product, ttl time.Duration) error
    Delete(ctx context.Context, id string) error
}

// NewCachedService creates a cached product service.
func NewCachedService(service Service, cache Cache, ttl time.Duration) *CachedService {
    return &CachedService{
        service: service,
        cache:   cache,
        ttl:     ttl,
    }
}

// GetByID gets a product, checking cache first.
func (s *CachedService) GetByID(ctx context.Context, id string) (*productcore.Product, error) {
    // Try cache first
    product, err := s.cache.Get(ctx, id)
    if err == nil && product != nil {
        return product, nil // Cache hit
    }

    // Cache miss - get from service
    product, err = s.service.GetByID(ctx, id)
    if err != nil {
        return nil, err
    }

    // Cache the result (async to not block response)
    if product != nil {
        go func() {
            _ = s.cache.Set(context.Background(), product, s.ttl)
        }()
    }

    return product, nil
}

// Update updates a product and invalidates cache.
func (s *CachedService) Update(ctx context.Context, id string, input *UpdateInput) (*productcore.Product, error) {
    product, err := s.service.Update(ctx, id, input)
    if err != nil {
        return nil, err
    }

    // Invalidate cache
    _ = s.cache.Delete(ctx, id)

    return product, nil
}

// Delete deletes a product and invalidates cache.
func (s *CachedService) Delete(ctx context.Context, id string) error {
    err := s.service.Delete(ctx, id)
    if err != nil {
        return err
    }

    // Invalidate cache
    _ = s.cache.Delete(ctx, id)

    return nil
}
```

### Redis Cache Implementation

```go
// internal/repo/redis/product_cache.go
package redis

import (
    "context"
    "encoding/json"
    "fmt"
    "time"

    "github.com/redis/go-redis/v9"

    productcore "{{module}}/internal/core/product"
)

// ProductCacheRepo implements product caching with Redis.
type ProductCacheRepo struct {
    client *redis.Client
}

// NewProductCacheRepo creates a new product cache repository.
func NewProductCacheRepo(client *redis.Client) *ProductCacheRepo {
    return &ProductCacheRepo{client: client}
}

// Get retrieves a product from cache.
func (r *ProductCacheRepo) Get(ctx context.Context, id string) (*productcore.Product, error) {
    key := ProductCacheKeyPrefix + id

    data, err := r.client.Get(ctx, key).Bytes()
    if err != nil {
        if err == redis.Nil {
            return nil, nil // Cache miss
        }
        return nil, fmt.Errorf("failed to get product from cache: %w", err)
    }

    var cached ProductCache
    if err := json.Unmarshal(data, &cached); err != nil {
        return nil, fmt.Errorf("failed to unmarshal cached product: %w", err)
    }

    return cacheToProduct(&cached), nil
}

// Set stores a product in cache.
func (r *ProductCacheRepo) Set(ctx context.Context, p *productcore.Product, ttl time.Duration) error {
    key := ProductCacheKeyPrefix + p.ID

    cached := productToCache(p)
    data, err := json.Marshal(cached)
    if err != nil {
        return fmt.Errorf("failed to marshal product for cache: %w", err)
    }

    return r.client.Set(ctx, key, data, ttl).Err()
}

// Delete removes a product from cache.
func (r *ProductCacheRepo) Delete(ctx context.Context, id string) error {
    key := ProductCacheKeyPrefix + id
    return r.client.Del(ctx, key).Err()
}

func productToCache(p *productcore.Product) *ProductCache {
    return &ProductCache{
        ID:          p.ID,
        Name:        p.Name,
        Description: p.Description,
        Price:       p.Price.InexactFloat64(),
        Quantity:    p.Quantity,
        Status:      string(p.Status),
        Attributes:  p.Attributes,
        CachedAt:    time.Now(),
    }
}

func cacheToProduct(c *ProductCache) *productcore.Product {
    return &productcore.Product{
        ID:          c.ID,
        Name:        c.Name,
        Description: c.Description,
        Price:       decimal.NewFromFloat(c.Price),
        Quantity:    c.Quantity,
        Status:      productcore.Status(c.Status),
        Attributes:  c.Attributes,
    }
}
```

## Error Handling

### Checking for Not Found

```go
import "github.com/redis/go-redis/v9"

func (r *Repo) Get(ctx context.Context, id string) (*Entity, error) {
    data, err := r.client.Get(ctx, key).Bytes()
    if err != nil {
        if err == redis.Nil {
            return nil, nil // Not found - return nil, nil
        }
        return nil, fmt.Errorf("failed to get from redis: %w", err)
    }
    // ... deserialize and return
}
```

### Error Wrapping Pattern

```go
// Always wrap errors with context
if err := r.client.Set(ctx, key, data, ttl).Err(); err != nil {
    return fmt.Errorf("failed to save %s to redis: %w", entityType, err)
}
```

## Composing Repositories

### Root Repository Pattern

```go
// internal/repo/root.go
package repo

import (
    "{{module}}/internal/repo/postgres"
    "{{module}}/internal/repo/redis"
)

// RootRepo composes multiple repository backends.
type RootRepo struct {
    postgres *postgres.Repo
    redis    *redis.Repo
}

// NewRootRepo creates a new root repository.
func NewRootRepo(postgres *postgres.Repo, redis *redis.Repo) *RootRepo {
    return &RootRepo{
        postgres: postgres,
        redis:    redis,
    }
}

// Delegate methods to appropriate backend:

// SaveProduct delegates to PostgreSQL (persistent storage).
func (r *RootRepo) SaveProduct(ctx context.Context, p *product.Product) error {
    return r.postgres.SaveProduct(ctx, p)
}

// SaveWorkflowExecutionContext delegates to Redis (ephemeral storage).
func (r *RootRepo) SaveWorkflowExecutionContext(ctx context.Context, ec *execution.WorkflowExecutionContext) error {
    return r.redis.SaveWorkflowExecutionContext(ctx, ec)
}
```

## Quick Reference

### Common Redis Operations

```go
// String operations
client.Set(ctx, "key", "value", ttl)
client.Get(ctx, "key")
client.Del(ctx, "key")
client.Exists(ctx, "key")

// Hash operations
client.HSet(ctx, "hash", "field", "value")
client.HGet(ctx, "hash", "field")
client.HGetAll(ctx, "hash")
client.HDel(ctx, "hash", "field")

// List operations
client.LPush(ctx, "list", "value")
client.RPush(ctx, "list", "value")
client.LRange(ctx, "list", 0, -1)

// Set operations
client.SAdd(ctx, "set", "member")
client.SMembers(ctx, "set")
client.SIsMember(ctx, "set", "member")

// Sorted set operations
client.ZAdd(ctx, "zset", redis.Z{Score: 1.0, Member: "member"})
client.ZRange(ctx, "zset", 0, -1)

// TTL operations
client.Expire(ctx, "key", ttl)
client.TTL(ctx, "key")

// Pipeline for batch operations
pipe := client.Pipeline()
pipe.Set(ctx, "key1", "value1", ttl)
pipe.Set(ctx, "key2", "value2", ttl)
_, err := pipe.Exec(ctx)
```

### Key Design Guidelines

| Pattern | Example | Use Case |
|---------|---------|----------|
| `{domain}:{entity}:{id}` | `product:cache:prod-123` | Single entity |
| `{domain}:{entity}:{tenant}:{id}` | `order:cache:t1:ord-456` | Multi-tenant |
| `{domain}:{entity}:list:{tenant}` | `product:list:t1` | Entity lists |
| `{domain}:{aggregate}:{id}:*` | `workflow:exec:wf-1:*` | Pattern matching |
