# Custom Business Metrics

This document describes patterns for implementing custom business metrics using OpenTelemetry in Go microservices.

## Overview

Beyond standard HTTP/gRPC request metrics (provided by devkit/common), services often need **business metrics** to track:
- Domain-specific operations (orders created, payments processed)
- Business KPIs (active users, revenue)
- System health indicators (queue depths, cache hit rates)

**Why OpenTelemetry (OTel):**
- Vendor-neutral: Works with Prometheus, Datadog, etc.
- Consistent with devkit/common observability
- Supports metrics, traces, and logs correlation
- Standard instrumentation patterns

## Directory Structure

```
internal/metrics/
├── metrics.go              # Metric definitions and initialization
├── attributes.go           # Common attribute helpers
└── metrics_test.go         # Metric tests
```

## Metric Definition Pattern

### Singleton Initialization

```go
// internal/metrics/metrics.go
package metrics

import (
    "context"
    "sync"

    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/metric"
)

// Metrics holds all application business metrics.
type Metrics struct {
    // Product metrics
    ProductsCreated   metric.Int64Counter
    ProductsUpdated   metric.Int64Counter
    ProductsDeleted   metric.Int64Counter
    ProductOperations metric.Int64Counter

    // Order metrics
    OrdersCreated    metric.Int64Counter
    OrdersCompleted  metric.Int64Counter
    OrdersFailed     metric.Int64Counter
    OrderTotal       metric.Float64Counter
    OrderProcessTime metric.Float64Histogram

    // System metrics
    CacheHits   metric.Int64Counter
    CacheMisses metric.Int64Counter
    QueueDepth  metric.Int64UpDownCounter
}

var (
    globalMetrics *Metrics
    once          sync.Once
    initErr       error
)

// Initialize creates and initializes all metrics.
// Should be called once at application startup.
func Initialize(serviceName string) (*Metrics, error) {
    once.Do(func() {
        meter := otel.Meter(serviceName)
        m := &Metrics{}

        // Product metrics
        m.ProductsCreated, initErr = meter.Int64Counter(
            "products.created.total",
            metric.WithDescription("Total number of products created"),
            metric.WithUnit("{product}"),
        )
        if initErr != nil {
            return
        }

        m.ProductsUpdated, initErr = meter.Int64Counter(
            "products.updated.total",
            metric.WithDescription("Total number of products updated"),
            metric.WithUnit("{product}"),
        )
        if initErr != nil {
            return
        }

        m.ProductsDeleted, initErr = meter.Int64Counter(
            "products.deleted.total",
            metric.WithDescription("Total number of products deleted"),
            metric.WithUnit("{product}"),
        )
        if initErr != nil {
            return
        }

        m.ProductOperations, initErr = meter.Int64Counter(
            "products.operations.total",
            metric.WithDescription("Total number of product operations by type"),
            metric.WithUnit("{operation}"),
        )
        if initErr != nil {
            return
        }

        // Order metrics
        m.OrdersCreated, initErr = meter.Int64Counter(
            "orders.created.total",
            metric.WithDescription("Total number of orders created"),
            metric.WithUnit("{order}"),
        )
        if initErr != nil {
            return
        }

        m.OrdersCompleted, initErr = meter.Int64Counter(
            "orders.completed.total",
            metric.WithDescription("Total number of orders completed"),
            metric.WithUnit("{order}"),
        )
        if initErr != nil {
            return
        }

        m.OrdersFailed, initErr = meter.Int64Counter(
            "orders.failed.total",
            metric.WithDescription("Total number of orders failed"),
            metric.WithUnit("{order}"),
        )
        if initErr != nil {
            return
        }

        m.OrderTotal, initErr = meter.Float64Counter(
            "orders.total.amount",
            metric.WithDescription("Total order amount in currency"),
            metric.WithUnit("{currency}"),
        )
        if initErr != nil {
            return
        }

        m.OrderProcessTime, initErr = meter.Float64Histogram(
            "orders.processing.duration",
            metric.WithDescription("Order processing duration in seconds"),
            metric.WithUnit("s"),
            metric.WithExplicitBucketBoundaries(0.1, 0.5, 1, 2, 5, 10, 30, 60),
        )
        if initErr != nil {
            return
        }

        // System metrics
        m.CacheHits, initErr = meter.Int64Counter(
            "cache.hits.total",
            metric.WithDescription("Total number of cache hits"),
            metric.WithUnit("{hit}"),
        )
        if initErr != nil {
            return
        }

        m.CacheMisses, initErr = meter.Int64Counter(
            "cache.misses.total",
            metric.WithDescription("Total number of cache misses"),
            metric.WithUnit("{miss}"),
        )
        if initErr != nil {
            return
        }

        m.QueueDepth, initErr = meter.Int64UpDownCounter(
            "queue.depth",
            metric.WithDescription("Current queue depth"),
            metric.WithUnit("{item}"),
        )
        if initErr != nil {
            return
        }

        globalMetrics = m
    })

    return globalMetrics, initErr
}

// Get returns the global metrics instance.
// Returns nil if Initialize has not been called.
func Get() *Metrics {
    return globalMetrics
}
```

### Nil-Safe Recording Methods

```go
// internal/metrics/metrics.go (continued)

// RecordProductCreated increments the products created counter.
func (m *Metrics) RecordProductCreated(ctx context.Context, tenantID string) {
    if m == nil || m.ProductsCreated == nil {
        return
    }
    m.ProductsCreated.Add(ctx, 1, metric.WithAttributes(
        attribute.String("tenant_id", tenantID),
    ))
}

// RecordProductUpdated increments the products updated counter.
func (m *Metrics) RecordProductUpdated(ctx context.Context, tenantID string) {
    if m == nil || m.ProductsUpdated == nil {
        return
    }
    m.ProductsUpdated.Add(ctx, 1, metric.WithAttributes(
        attribute.String("tenant_id", tenantID),
    ))
}

// RecordProductDeleted increments the products deleted counter.
func (m *Metrics) RecordProductDeleted(ctx context.Context, tenantID string) {
    if m == nil || m.ProductsDeleted == nil {
        return
    }
    m.ProductsDeleted.Add(ctx, 1, metric.WithAttributes(
        attribute.String("tenant_id", tenantID),
    ))
}

// RecordProductOperation records a product operation with type attribute.
func (m *Metrics) RecordProductOperation(ctx context.Context, operation, tenantID string, success bool) {
    if m == nil || m.ProductOperations == nil {
        return
    }
    m.ProductOperations.Add(ctx, 1, metric.WithAttributes(
        attribute.String("operation", operation),
        attribute.String("tenant_id", tenantID),
        attribute.Bool("success", success),
    ))
}

// RecordOrderCreated increments the orders created counter.
func (m *Metrics) RecordOrderCreated(ctx context.Context, tenantID string) {
    if m == nil || m.OrdersCreated == nil {
        return
    }
    m.OrdersCreated.Add(ctx, 1, metric.WithAttributes(
        attribute.String("tenant_id", tenantID),
    ))
}

// RecordOrderCompleted increments the orders completed counter and total.
func (m *Metrics) RecordOrderCompleted(ctx context.Context, tenantID string, amount float64) {
    if m == nil {
        return
    }
    attrs := metric.WithAttributes(attribute.String("tenant_id", tenantID))

    if m.OrdersCompleted != nil {
        m.OrdersCompleted.Add(ctx, 1, attrs)
    }
    if m.OrderTotal != nil {
        m.OrderTotal.Add(ctx, amount, attrs)
    }
}

// RecordOrderFailed increments the orders failed counter.
func (m *Metrics) RecordOrderFailed(ctx context.Context, tenantID, reason string) {
    if m == nil || m.OrdersFailed == nil {
        return
    }
    m.OrdersFailed.Add(ctx, 1, metric.WithAttributes(
        attribute.String("tenant_id", tenantID),
        attribute.String("reason", reason),
    ))
}

// RecordOrderProcessingTime records order processing duration.
func (m *Metrics) RecordOrderProcessingTime(ctx context.Context, tenantID string, durationSec float64) {
    if m == nil || m.OrderProcessTime == nil {
        return
    }
    m.OrderProcessTime.Record(ctx, durationSec, metric.WithAttributes(
        attribute.String("tenant_id", tenantID),
    ))
}

// RecordCacheHit increments the cache hits counter.
func (m *Metrics) RecordCacheHit(ctx context.Context, cacheType string) {
    if m == nil || m.CacheHits == nil {
        return
    }
    m.CacheHits.Add(ctx, 1, metric.WithAttributes(
        attribute.String("cache_type", cacheType),
    ))
}

// RecordCacheMiss increments the cache misses counter.
func (m *Metrics) RecordCacheMiss(ctx context.Context, cacheType string) {
    if m == nil || m.CacheMisses == nil {
        return
    }
    m.CacheMisses.Add(ctx, 1, metric.WithAttributes(
        attribute.String("cache_type", cacheType),
    ))
}

// AdjustQueueDepth adjusts the queue depth gauge.
func (m *Metrics) AdjustQueueDepth(ctx context.Context, queueName string, delta int64) {
    if m == nil || m.QueueDepth == nil {
        return
    }
    m.QueueDepth.Add(ctx, delta, metric.WithAttributes(
        attribute.String("queue_name", queueName),
    ))
}
```

## Attribute Helpers

```go
// internal/metrics/attributes.go
package metrics

import "go.opentelemetry.io/otel/attribute"

// Common attribute keys
const (
    AttrTenantID   = "tenant_id"
    AttrOperation  = "operation"
    AttrStatus     = "status"
    AttrSuccess    = "success"
    AttrCacheType  = "cache_type"
    AttrQueueName  = "queue_name"
    AttrEntityType = "entity_type"
    AttrEntityID   = "entity_id"
)

// TenantAttr creates a tenant_id attribute.
func TenantAttr(tenantID string) attribute.KeyValue {
    return attribute.String(AttrTenantID, tenantID)
}

// OperationAttr creates an operation attribute.
func OperationAttr(operation string) attribute.KeyValue {
    return attribute.String(AttrOperation, operation)
}

// StatusAttr creates a status attribute.
func StatusAttr(status string) attribute.KeyValue {
    return attribute.String(AttrStatus, status)
}

// SuccessAttr creates a success attribute.
func SuccessAttr(success bool) attribute.KeyValue {
    return attribute.Bool(AttrSuccess, success)
}
```

## Fx Integration

```go
// cmd/serve.go or internal/di/metrics/module.go
package di

import (
    "go.uber.org/fx"

    "{{module}}/internal/config"
    "{{module}}/internal/metrics"
)

// MetricsModule provides metrics dependencies.
var MetricsModule = fx.Module("metrics",
    fx.Provide(NewMetrics),
)

// NewMetrics initializes the metrics package.
func NewMetrics(cfg *config.Configuration) (*metrics.Metrics, error) {
    return metrics.Initialize(cfg.ServiceName)
}
```

## Integration with Instrumented Services

### Service Layer Integration

```go
// internal/services/product/instrumented.go
package product

import (
    "context"
    "time"

    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/codes"

    productcore "{{module}}/internal/core/product"
    "{{module}}/internal/metrics"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace"
)

// InstrumentedService wraps a service with tracing, logging, and metrics.
type InstrumentedService struct {
    service Service
    logger  logger.Logger
    metrics *metrics.Metrics
}

// NewInstrumentedService creates an instrumented product service.
func NewInstrumentedService(
    service Service,
    logger logger.Logger,
    m *metrics.Metrics,
) *InstrumentedService {
    return &InstrumentedService{
        service: service,
        logger:  logger,
        metrics: m,
    }
}

// Create creates a product with full instrumentation.
func (s *InstrumentedService) Create(ctx context.Context, input *CreateInput) (*productcore.Product, error) {
    ctx, span := trace.Instrument(ctx, s.Create)
    defer span.End()

    span.SetAttributes(
        attribute.String("product.name", input.Name),
    )

    log := s.logger.With(logger.String("product_name", input.Name))
    log.Info(ctx, "creating product")

    start := time.Now()
    p, err := s.service.Create(ctx, input)
    duration := time.Since(start)

    if err != nil {
        log.Error(ctx, "failed to create product", logger.Error(err))
        span.RecordError(err)
        span.SetStatus(codes.Error, "failed to create product")

        // Record failure metric
        s.metrics.RecordProductOperation(ctx, "create", input.TenantID, false)
        return nil, err
    }

    log.Info(ctx, "product created", logger.String("product_id", p.ID))
    span.SetAttributes(attribute.String("product.id", p.ID))
    span.SetStatus(codes.Ok, "product created")

    // Record success metrics
    s.metrics.RecordProductCreated(ctx, p.TenantID)
    s.metrics.RecordProductOperation(ctx, "create", p.TenantID, true)

    return p, nil
}

// Update updates a product with full instrumentation.
func (s *InstrumentedService) Update(ctx context.Context, id string, input *UpdateInput) (*productcore.Product, error) {
    ctx, span := trace.Instrument(ctx, s.Update)
    defer span.End()

    span.SetAttributes(attribute.String("product.id", id))

    log := s.logger.With(logger.String("product_id", id))
    log.Info(ctx, "updating product")

    p, err := s.service.Update(ctx, id, input)

    if err != nil {
        log.Error(ctx, "failed to update product", logger.Error(err))
        span.RecordError(err)
        span.SetStatus(codes.Error, "failed to update product")
        s.metrics.RecordProductOperation(ctx, "update", "", false) // tenant might not be known
        return nil, err
    }

    log.Info(ctx, "product updated")
    span.SetStatus(codes.Ok, "product updated")

    s.metrics.RecordProductUpdated(ctx, p.TenantID)
    s.metrics.RecordProductOperation(ctx, "update", p.TenantID, true)

    return p, nil
}

// Delete deletes a product with full instrumentation.
func (s *InstrumentedService) Delete(ctx context.Context, id string) error {
    ctx, span := trace.Instrument(ctx, s.Delete)
    defer span.End()

    span.SetAttributes(attribute.String("product.id", id))

    log := s.logger.With(logger.String("product_id", id))
    log.Info(ctx, "deleting product")

    // Get product first to know tenant
    p, _ := s.service.GetByID(ctx, id)

    err := s.service.Delete(ctx, id)

    if err != nil {
        log.Error(ctx, "failed to delete product", logger.Error(err))
        span.RecordError(err)
        span.SetStatus(codes.Error, "failed to delete product")
        s.metrics.RecordProductOperation(ctx, "delete", "", false)
        return err
    }

    log.Info(ctx, "product deleted")
    span.SetStatus(codes.Ok, "product deleted")

    tenantID := ""
    if p != nil {
        tenantID = p.TenantID
    }
    s.metrics.RecordProductDeleted(ctx, tenantID)
    s.metrics.RecordProductOperation(ctx, "delete", tenantID, true)

    return nil
}
```

### Cache Layer Integration

```go
// internal/services/product/cached.go
package product

import (
    "context"
    "time"

    productcore "{{module}}/internal/core/product"
    "{{module}}/internal/metrics"
)

// CachedService wraps a service with caching and metrics.
type CachedService struct {
    service Service
    cache   Cache
    ttl     time.Duration
    metrics *metrics.Metrics
}

// GetByID gets a product with cache metrics.
func (s *CachedService) GetByID(ctx context.Context, id string) (*productcore.Product, error) {
    // Try cache first
    product, err := s.cache.Get(ctx, id)
    if err == nil && product != nil {
        s.metrics.RecordCacheHit(ctx, "product")
        return product, nil
    }

    // Cache miss
    s.metrics.RecordCacheMiss(ctx, "product")

    // Get from service
    product, err = s.service.GetByID(ctx, id)
    if err != nil {
        return nil, err
    }

    // Cache the result
    if product != nil {
        go func() {
            _ = s.cache.Set(context.Background(), product, s.ttl)
        }()
    }

    return product, nil
}
```

## Metric Types Reference

### Counters (Int64Counter, Float64Counter)

Use for values that only increase:
- Request counts
- Error counts
- Bytes transferred
- Revenue totals

```go
// Definition
counter, err := meter.Int64Counter(
    "orders.created.total",
    metric.WithDescription("Total orders created"),
    metric.WithUnit("{order}"),
)

// Recording
counter.Add(ctx, 1, metric.WithAttributes(attrs...))
```

### Histograms (Float64Histogram)

Use for distributions:
- Request latencies
- Response sizes
- Processing times

```go
// Definition with custom buckets
histogram, err := meter.Float64Histogram(
    "orders.processing.duration",
    metric.WithDescription("Order processing duration"),
    metric.WithUnit("s"),
    metric.WithExplicitBucketBoundaries(0.1, 0.5, 1, 2, 5, 10, 30, 60),
)

// Recording
histogram.Record(ctx, durationSeconds, metric.WithAttributes(attrs...))
```

### UpDownCounters (Int64UpDownCounter)

Use for values that can increase or decrease:
- Queue depths
- Active connections
- Cache sizes

```go
// Definition
gauge, err := meter.Int64UpDownCounter(
    "queue.depth",
    metric.WithDescription("Current queue depth"),
    metric.WithUnit("{item}"),
)

// Recording
gauge.Add(ctx, 1)   // Increment
gauge.Add(ctx, -1)  // Decrement
```

## Naming Conventions

### Metric Names

Follow the pattern: `{domain}.{operation}.{suffix}`

| Type | Pattern | Example |
|------|---------|---------|
| Counter | `{domain}.{action}.total` | `orders.created.total` |
| Histogram | `{domain}.{measurement}.{unit}` | `orders.processing.duration` |
| Gauge | `{domain}.{measurement}` | `queue.depth` |

### Attribute Names

- Use snake_case: `tenant_id`, `cache_type`
- Be specific: `order_status` not just `status`
- Keep cardinality low: avoid user IDs, timestamps

### Units

Use standard units from OpenTelemetry semantic conventions:
- Time: `s`, `ms`, `us`, `ns`
- Bytes: `By`, `KiBy`, `MiBy`
- Counts: `{request}`, `{error}`, `{item}`

## Testing Metrics

```go
// internal/metrics/metrics_test.go
package metrics_test

import (
    "context"
    "testing"

    "github.com/stretchr/testify/require"
    "go.opentelemetry.io/otel/sdk/metric"
    "go.opentelemetry.io/otel/sdk/metric/metricdata"

    appmetrics "{{module}}/internal/metrics"
)

func TestMetrics_RecordProductCreated(t *testing.T) {
    // Create a test meter provider
    reader := metric.NewManualReader()
    provider := metric.NewMeterProvider(metric.WithReader(reader))

    // Initialize metrics with test provider
    m, err := appmetrics.InitializeWithProvider("test-service", provider)
    require.NoError(t, err)

    ctx := context.Background()

    // Record metric
    m.RecordProductCreated(ctx, "tenant-1")
    m.RecordProductCreated(ctx, "tenant-1")
    m.RecordProductCreated(ctx, "tenant-2")

    // Collect metrics
    var rm metricdata.ResourceMetrics
    err = reader.Collect(ctx, &rm)
    require.NoError(t, err)

    // Find and verify the metric
    found := false
    for _, sm := range rm.ScopeMetrics {
        for _, m := range sm.Metrics {
            if m.Name == "products.created.total" {
                found = true
                // Verify data points
                sum := m.Data.(metricdata.Sum[int64])
                require.Len(t, sum.DataPoints, 2) // Two tenants
            }
        }
    }
    require.True(t, found, "metric not found")
}
```

## Quick Reference

### Initialization

```go
// At startup
metrics, err := metrics.Initialize("my-service")

// In service
m := metrics.Get()
m.RecordProductCreated(ctx, tenantID)
```

### Common Patterns

```go
// Count operation
m.Counter.Add(ctx, 1, metric.WithAttributes(
    attribute.String("tenant_id", tenantID),
    attribute.Bool("success", true),
))

// Record duration
m.Histogram.Record(ctx, duration.Seconds(), metric.WithAttributes(
    attribute.String("operation", "create"),
))

// Adjust gauge
m.Gauge.Add(ctx, 1)   // Item added
m.Gauge.Add(ctx, -1)  // Item removed
```
