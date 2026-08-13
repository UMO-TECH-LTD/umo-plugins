# Ent ORM with Atlas Migrations

This document describes patterns for using Ent ORM with Atlas migrations, the preferred database approach for production services.

## Overview

**Ent** provides type-safe database operations with generated Go code. It eliminates manual SQL writing while providing compile-time safety and a fluent query API.

**Atlas** handles schema migrations declaratively. The `schema.sql` file serves as the source of truth, and Atlas generates versioned migration files.

**Why Ent + Atlas:**
- Type-safe queries with compile-time checks
- Generated CRUD operations reduce boilerplate
- Automatic OpenTelemetry instrumentation via otelsql
- Database metrics out of the box
- Declarative schema management
- Versioned migrations with rollback support

## Directory Structure

```
internal/repo/postgres/
├── ent/
│   ├── schema/                   # Entity definitions (you write these)
│   │   ├── {{entity}}.go         # Entity schema
│   │   └── types.go              # Shared types for JSON fields
│   ├── client.go                 # Generated client
│   ├── {{entity}}.go             # Generated entity type
│   ├── {{entity}}_create.go      # Generated create builder
│   ├── {{entity}}_update.go      # Generated update builder
│   ├── {{entity}}_query.go       # Generated query builder
│   ├── {{entity}}_delete.go      # Generated delete builder
│   ├── predicate/                # Generated predicates
│   ├── migrate/                  # Generated migration support
│   └── tx.go                     # Generated transaction support
├── repo.go                       # Repository implementation
├── {{entity}}.go                 # Entity-specific repository methods
├── mappers.go                    # Domain ↔ Ent type conversion
└── generate.go                   # go:generate directive

atlas/
├── atlas.hcl                     # Atlas configuration
├── schema.sql                    # Source schema (you write this)
└── migrations/                   # Generated migration files
    ├── 20260101120000_initial.sql
    └── atlas.sum                 # Migration checksum
```

## Schema Definition Patterns

### Basic Entity Schema

```go
// internal/repo/postgres/ent/schema/product.go
package schema

import (
    "time"

    "entgo.io/ent"
    "entgo.io/ent/dialect/entsql"
    "entgo.io/ent/schema"
    "entgo.io/ent/schema/field"
    "entgo.io/ent/schema/index"
)

// Product holds the schema definition for the Product entity.
type Product struct {
    ent.Schema
}

// Annotations of the Product.
func (Product) Annotations() []schema.Annotation {
    return []schema.Annotation{
        entsql.WithComments(true),
        // Enable upsert behavior
        &entsql.Annotation{
            Options: "ON CONFLICT (id) DO UPDATE",
        },
    }
}

// Fields of the Product.
func (Product) Fields() []ent.Field {
    return []ent.Field{
        field.String("id").
            Unique().
            Immutable().
            NotEmpty().
            Comment("Unique product identifier"),
        field.String("tenant_id").
            NotEmpty().
            Comment("Tenant this product belongs to"),
        field.String("name").
            NotEmpty().
            MaxLen(255).
            Comment("Product name"),
        field.Text("description").
            Optional().
            Comment("Product description"),
        field.Float("price").
            Positive().
            Comment("Product price"),
        field.Int("quantity").
            NonNegative().
            Default(0).
            Comment("Available quantity"),
        field.Enum("status").
            Values("ACTIVE", "INACTIVE", "DELETED").
            Default("ACTIVE").
            Comment("Product status"),
        field.JSON("attributes", map[string]any{}).
            Optional().
            Comment("Additional product attributes"),
        field.Time("created_at").
            Default(time.Now).
            Immutable().
            Comment("Creation timestamp"),
        field.Time("updated_at").
            Default(time.Now).
            UpdateDefault(time.Now).
            Comment("Last update timestamp"),
    }
}

// Indexes of the Product.
func (Product) Indexes() []ent.Index {
    return []ent.Index{
        index.Fields("tenant_id"),
        index.Fields("status"),
        index.Fields("tenant_id", "status"),
        index.Fields("created_at").Annotations(entsql.Desc()),
    }
}

// Edges of the Product (relationships).
func (Product) Edges() []ent.Edge {
    return nil // Add relationships here if needed
}
```

### JSON Field Types

Define custom types for JSON fields in a separate file:

```go
// internal/repo/postgres/ent/schema/types.go
package schema

// Attributes represents dynamic key-value attributes stored as JSON.
type Attributes map[string]any

// OrderItem represents an item in an order (for JSON arrays).
type OrderItem struct {
    ProductID string  `json:"product_id"`
    Quantity  int     `json:"quantity"`
    Price     float64 `json:"price"`
}

// Address represents a shipping/billing address.
type Address struct {
    Street  string `json:"street"`
    City    string `json:"city"`
    Country string `json:"country"`
    ZipCode string `json:"zip_code"`
}
```

### Entity with Relationships (Edges)

```go
// internal/repo/postgres/ent/schema/order.go
package schema

import (
    "entgo.io/ent"
    "entgo.io/ent/schema/edge"
    "entgo.io/ent/schema/field"
)

type Order struct {
    ent.Schema
}

func (Order) Fields() []ent.Field {
    return []ent.Field{
        field.String("id").Unique().Immutable(),
        field.String("customer_id").NotEmpty(),
        field.Float("total").Positive(),
        field.Time("created_at").Default(time.Now).Immutable(),
    }
}

func (Order) Edges() []ent.Edge {
    return []ent.Edge{
        // One order has many order items
        edge.To("items", OrderItem.Type),
        // One order belongs to one customer
        edge.From("customer", Customer.Type).
            Ref("orders").
            Unique().
            Required(),
    }
}
```

## Code Generation

### Generate Directive

```go
// internal/repo/postgres/generate.go
package postgres

//go:generate go run -mod=mod entgo.io/ent/cmd/ent generate ./ent/schema
```

### Generate Commands

```bash
# Generate Ent code from schemas
cd internal/repo/postgres && go generate ./...

# Or directly
go run -mod=mod entgo.io/ent/cmd/ent generate ./internal/repo/postgres/ent/schema

# Initialize a new entity schema
go run -mod=mod entgo.io/ent/cmd/ent new Product
```

## Client Initialization with Observability

### Fx Provider Pattern

```go
// cmd/serve.go or internal/di/postgres/module.go
package postgres

import (
    "context"
    "database/sql"
    "fmt"

    "entgo.io/ent/dialect"
    entsql "entgo.io/ent/dialect/sql"
    "github.com/XSAM/otelsql"
    "go.opentelemetry.io/otel/attribute"
    semconv "go.opentelemetry.io/otel/semconv/v1.4.0"
    "go.uber.org/fx"

    "{{module}}/internal/config"
    "{{module}}/internal/repo/postgres/ent"
)

// Module provides PostgreSQL/Ent dependencies.
var Module = fx.Module("postgres",
    fx.Provide(NewEntClient),
    fx.Provide(NewRepo),
)

// NewEntClient creates an Ent client with OpenTelemetry instrumentation.
func NewEntClient(cfg *config.Configuration, lc fx.Lifecycle) (*ent.Client, error) {
    // Open database connection with otelsql wrapper for automatic tracing
    db, err := otelsql.Open(dialect.Postgres, cfg.Postgres.DSN(),
        otelsql.WithAttributes(
            semconv.DBSystemPostgreSQL,
            attribute.String("db.name", cfg.Postgres.Database),
        ),
    )
    if err != nil {
        return nil, fmt.Errorf("failed to open postgres connection: %w", err)
    }

    // Configure connection pool
    db.SetMaxOpenConns(cfg.Postgres.MaxConns)
    db.SetMaxIdleConns(cfg.Postgres.MinConns)
    db.SetConnMaxLifetime(cfg.Postgres.MaxConnLifetime)
    db.SetConnMaxIdleTime(cfg.Postgres.MaxConnIdleTime)

    // Register database stats for Prometheus metrics
    if _, err := otelsql.RegisterDBStatsMetrics(db, otelsql.WithAttributes(
        semconv.DBSystemPostgreSQL,
        attribute.String("db.name", cfg.Postgres.Database),
    )); err != nil {
        _ = db.Close()
        return nil, fmt.Errorf("failed to register db stats metrics: %w", err)
    }

    // Create Ent client with the instrumented driver
    drv := entsql.OpenDB(dialect.Postgres, db)
    client := ent.NewClient(ent.Driver(drv))

    // Register lifecycle hooks
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            // Verify connection on startup
            if err := db.PingContext(ctx); err != nil {
                return fmt.Errorf("failed to ping database: %w", err)
            }
            return nil
        },
        OnStop: func(ctx context.Context) error {
            if err := client.Close(); err != nil {
                return fmt.Errorf("failed to close ent client: %w", err)
            }
            return db.Close()
        },
    })

    return client, nil
}
```

## Repository Implementation

### Base Repository

```go
// internal/repo/postgres/repo.go
package postgres

import (
    "{{module}}/internal/repo/postgres/ent"
)

// Repo provides PostgreSQL repository operations.
type Repo struct {
    client *ent.Client
}

// NewRepo creates a new PostgreSQL repository.
func NewRepo(client *ent.Client) *Repo {
    return &Repo{
        client: client,
    }
}

// Client returns the Ent client for transaction support.
func (r *Repo) Client() *ent.Client {
    return r.client
}
```

### Entity Repository Methods

```go
// internal/repo/postgres/products.go
package postgres

import (
    "context"
    "fmt"

    "{{module}}/internal/core/product"
    "{{module}}/internal/repo/postgres/ent"
    entproduct "{{module}}/internal/repo/postgres/ent/product"
)

// SaveProduct saves a product (upsert pattern).
func (r *Repo) SaveProduct(ctx context.Context, p *product.Product) error {
    // Check if product exists
    existing, err := r.client.Product.
        Query().
        Where(entproduct.IDEQ(p.ID)).
        Only(ctx)
    if err != nil && !ent.IsNotFound(err) {
        return fmt.Errorf("failed to check existing product: %w", err)
    }

    if existing != nil {
        // Update existing product
        return r.client.Product.
            UpdateOneID(p.ID).
            SetName(p.Name).
            SetDescription(p.Description).
            SetPrice(p.Price).
            SetQuantity(p.Quantity).
            SetStatus(entproduct.Status(p.Status)).
            SetAttributes(attributesToSchema(p.Attributes)).
            Exec(ctx)
    }

    // Create new product
    return r.client.Product.
        Create().
        SetID(p.ID).
        SetTenantID(p.TenantID).
        SetName(p.Name).
        SetDescription(p.Description).
        SetPrice(p.Price).
        SetQuantity(p.Quantity).
        SetStatus(entproduct.Status(p.Status)).
        SetAttributes(attributesToSchema(p.Attributes)).
        SetCreatedAt(p.CreatedAt).
        Exec(ctx)
}

// GetProduct retrieves a product by ID.
func (r *Repo) GetProduct(ctx context.Context, id string) (*product.Product, error) {
    p, err := r.client.Product.
        Query().
        Where(entproduct.IDEQ(id)).
        Only(ctx)
    if err != nil {
        if ent.IsNotFound(err) {
            return nil, nil // Return nil for not found
        }
        return nil, fmt.Errorf("failed to get product: %w", err)
    }

    return toCoreProduct(p), nil
}

// GetProductsByTenant retrieves products for a tenant with pagination.
func (r *Repo) GetProductsByTenant(
    ctx context.Context,
    tenantID string,
    limit, offset int,
) ([]*product.Product, error) {
    products, err := r.client.Product.
        Query().
        Where(
            entproduct.TenantIDEQ(tenantID),
            entproduct.StatusNEQ(entproduct.StatusDELETED),
        ).
        Order(ent.Desc(entproduct.FieldCreatedAt)).
        Limit(limit).
        Offset(offset).
        All(ctx)
    if err != nil {
        return nil, fmt.Errorf("failed to list products: %w", err)
    }

    result := make([]*product.Product, len(products))
    for i, p := range products {
        result[i] = toCoreProduct(p)
    }
    return result, nil
}

// DeleteProduct soft-deletes a product.
func (r *Repo) DeleteProduct(ctx context.Context, id string) error {
    return r.client.Product.
        UpdateOneID(id).
        SetStatus(entproduct.StatusDELETED).
        Exec(ctx)
}
```

### Type Conversion (Mappers)

```go
// internal/repo/postgres/mappers.go
package postgres

import (
    "{{module}}/internal/core/product"
    "{{module}}/internal/repo/postgres/ent"
    entproduct "{{module}}/internal/repo/postgres/ent/product"
    "{{module}}/internal/repo/postgres/ent/schema"
)

// toCoreProduct converts Ent Product to domain Product.
func toCoreProduct(e *ent.Product) *product.Product {
    return &product.Product{
        ID:          e.ID,
        TenantID:    e.TenantID,
        Name:        e.Name,
        Description: e.Description,
        Price:       e.Price,
        Quantity:    e.Quantity,
        Status:      product.Status(e.Status),
        Attributes:  schemaToAttributes(e.Attributes),
        CreatedAt:   e.CreatedAt,
        UpdatedAt:   e.UpdatedAt,
    }
}

// attributesToSchema converts domain attributes to Ent schema type.
func attributesToSchema(attrs product.Attributes) schema.Attributes {
    if attrs == nil {
        return make(schema.Attributes)
    }
    return schema.Attributes(attrs)
}

// schemaToAttributes converts Ent schema attributes to domain type.
func schemaToAttributes(attrs schema.Attributes) product.Attributes {
    if attrs == nil {
        return make(product.Attributes)
    }
    return product.Attributes(attrs)
}
```

## Transaction Support

### Using Transactions

```go
// internal/repo/postgres/transactions.go
package postgres

import (
    "context"
    "fmt"

    "{{module}}/internal/repo/postgres/ent"
)

// WithTx executes a function within a database transaction.
func (r *Repo) WithTx(ctx context.Context, fn func(tx *ent.Tx) error) error {
    tx, err := r.client.Tx(ctx)
    if err != nil {
        return fmt.Errorf("failed to start transaction: %w", err)
    }

    defer func() {
        if v := recover(); v != nil {
            _ = tx.Rollback()
            panic(v)
        }
    }()

    if err := fn(tx); err != nil {
        if rerr := tx.Rollback(); rerr != nil {
            return fmt.Errorf("rolling back transaction: %w (original error: %v)", rerr, err)
        }
        return err
    }

    if err := tx.Commit(); err != nil {
        return fmt.Errorf("committing transaction: %w", err)
    }

    return nil
}

// Example usage in service layer:
// err := repo.WithTx(ctx, func(tx *ent.Tx) error {
//     // All operations use tx.Product, tx.Order, etc.
//     if err := tx.Product.Create()...; err != nil {
//         return err
//     }
//     if err := tx.Order.Create()...; err != nil {
//         return err
//     }
//     return nil
// })
```

## Atlas Migration Workflow

### Atlas Configuration

```hcl
# atlas/atlas.hcl
variable "user" {
  type    = string
  default = getenv("DB_USER", "postgres")
}

variable "password" {
  type    = string
  default = getenv("DB_PASSWORD", "postgres")
}

variable "host" {
  type    = string
  default = getenv("DB_HOST", "localhost")
}

variable "port" {
  type    = string
  default = getenv("DB_PORT", "5432")
}

variable "db_name" {
  type    = string
  default = getenv("DB_NAME", "myservice")
}

variable "ssl_mode" {
  type    = string
  default = getenv("DB_SSL_MODE", "disable")
}

env "local" {
  src = "file://schema.sql"
  url = "postgres://${var.user}:${var.password}@${var.host}:${var.port}/${var.db_name}?sslmode=${var.ssl_mode}"
  dev = "docker://postgres/15/dev?search_path=public"
  migration {
    dir = "file://migrations"
  }
  format {
    migrate {
      diff = "{{ sql . \"  \" }}"
    }
  }
}
```

### Schema Definition (Source of Truth)

```sql
-- atlas/schema.sql
-- This is the source of truth for the database schema.
-- Atlas uses this to generate migrations.

-- Product status enum
CREATE TYPE product_status AS ENUM ('ACTIVE', 'INACTIVE', 'DELETED');

-- Products table
CREATE TABLE products (
    id VARCHAR(255) PRIMARY KEY,
    tenant_id VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 0,
    status product_status NOT NULL DEFAULT 'ACTIVE',
    attributes JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_products_tenant_id ON products(tenant_id);
CREATE INDEX idx_products_status ON products(status);
CREATE INDEX idx_products_tenant_status ON products(tenant_id, status);
CREATE INDEX idx_products_created_at ON products(created_at DESC);
```

### Migration Commands

```bash
# Generate a new migration by comparing schema.sql with database
atlas migrate diff migration_name --env local

# Apply pending migrations
atlas migrate apply --env local

# Show migration status
atlas migrate status --env local

# Validate migrations
atlas migrate validate --env local

# Hash migrations (after manual edits)
atlas migrate hash --env local
```

### Makefile Targets

```makefile
# Database and migration targets
.PHONY: atlas-install atlas-diff atlas-apply atlas-status migrate-db

atlas-install:
	@echo "Installing Atlas CLI..."
	curl -sSf https://atlasgo.sh | sh

atlas-diff:
	@if [ -z "$(NAME)" ]; then echo "Usage: make atlas-diff NAME=migration_name"; exit 1; fi
	cd atlas && atlas migrate diff $(NAME) --env local

atlas-apply:
	cd atlas && atlas migrate apply --env local

atlas-status:
	cd atlas && atlas migrate status --env local

# Run migrations via Go CLI (recommended for production)
migrate-db:
	go run main.go migrate-db
```

## Error Handling Patterns

### Checking for Not Found

```go
import "{{module}}/internal/repo/postgres/ent"

func (r *Repo) GetProduct(ctx context.Context, id string) (*product.Product, error) {
    p, err := r.client.Product.Query().Where(entproduct.IDEQ(id)).Only(ctx)
    if err != nil {
        if ent.IsNotFound(err) {
            return nil, nil // or return a domain-specific ErrNotFound
        }
        return nil, fmt.Errorf("failed to get product: %w", err)
    }
    return toCoreProduct(p), nil
}
```

### Checking for Constraint Violations

```go
import "{{module}}/internal/repo/postgres/ent"

func (r *Repo) CreateProduct(ctx context.Context, p *product.Product) error {
    err := r.client.Product.Create().
        SetID(p.ID).
        // ... other fields
        Exec(ctx)
    if err != nil {
        if ent.IsConstraintError(err) {
            return product.ErrAlreadyExists
        }
        return fmt.Errorf("failed to create product: %w", err)
    }
    return nil
}
```

## Observability Integration

### Tracing with devkit/common

The otelsql wrapper provides automatic tracing. For additional instrumentation:

```go
// internal/repo/postgres/instrumentation.go
package postgres

import (
    "context"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace"
    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/codes"
)

// InstrumentedRepo wraps Repo with tracing and logging.
type InstrumentedRepo struct {
    repo   *Repo
    logger logger.Logger
}

func NewInstrumentedRepo(repo *Repo, logger logger.Logger) *InstrumentedRepo {
    return &InstrumentedRepo{repo: repo, logger: logger}
}

func (r *InstrumentedRepo) GetProduct(ctx context.Context, id string) (*product.Product, error) {
    ctx, span := trace.Instrument(ctx, r.GetProduct)
    defer span.End()

    span.SetAttributes(attribute.String("product.id", id))

    p, err := r.repo.GetProduct(ctx, id)
    if err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, "failed to get product")
        r.logger.Error(ctx, "failed to get product",
            logger.String("product_id", id),
            logger.Error(err),
        )
        return nil, err
    }

    if p == nil {
        span.SetStatus(codes.Ok, "product not found")
        return nil, nil
    }

    span.SetStatus(codes.Ok, "product retrieved")
    return p, nil
}
```

## Quick Reference

### Common Ent Operations

```go
// Create
client.Product.Create().SetID("123").SetName("Widget").Exec(ctx)

// Query single
client.Product.Query().Where(product.IDEQ("123")).Only(ctx)

// Query multiple with filters
client.Product.Query().
    Where(
        product.TenantIDEQ("tenant-1"),
        product.StatusIn(product.StatusACTIVE, product.StatusINACTIVE),
    ).
    Order(ent.Desc(product.FieldCreatedAt)).
    Limit(10).
    Offset(0).
    All(ctx)

// Update
client.Product.UpdateOneID("123").SetName("New Name").Exec(ctx)

// Delete (hard delete)
client.Product.DeleteOneID("123").Exec(ctx)

// Count
client.Product.Query().Where(product.TenantIDEQ("tenant-1")).Count(ctx)

// Exists
client.Product.Query().Where(product.IDEQ("123")).Exist(ctx)
```

### Field Types

| Go Type | Ent Field | PostgreSQL Type |
|---------|-----------|-----------------|
| `string` | `field.String()` | `VARCHAR` / `TEXT` |
| `int` | `field.Int()` | `INTEGER` |
| `int64` | `field.Int64()` | `BIGINT` |
| `float64` | `field.Float()` | `DOUBLE PRECISION` |
| `bool` | `field.Bool()` | `BOOLEAN` |
| `time.Time` | `field.Time()` | `TIMESTAMP` |
| `[]byte` | `field.Bytes()` | `BYTEA` |
| `uuid.UUID` | `field.UUID()` | `UUID` |
| `enum` | `field.Enum()` | `ENUM` / `VARCHAR` |
| `map[string]any` | `field.JSON()` | `JSONB` |

### Field Modifiers

```go
field.String("name").
    Unique().           // Unique constraint
    NotEmpty().         // NOT NULL + non-empty validation
    Optional().         // Nullable field
    Immutable().        // Cannot be updated
    Default("value").   // Default value
    MaxLen(255).        // Maximum length
    Comment("...").     // Database column comment
    Nillable().         // Pointer type in Go
    Sensitive()         // Exclude from serialization
```
