# Atlas Database Migrations

Complete, production-ready templates for Atlas database migrations using declarative schema management and the devkit/common Atlas package.

## Table of Contents

1. [Overview](#1-overview)
2. [Directory Structure](#2-directory-structure)
3. [Atlas Configuration (atlas.hcl)](#3-atlas-configuration-atlashcl)
4. [Declarative Schema (schema.sql)](#4-declarative-schema-schemasql)
5. [Go Integration (devkit/common)](#5-go-integration-devkitcommon)
6. [CLI Command (cmd/migratedb)](#6-cli-command-cmdmigratedb)
7. [Makefile/Taskfile Targets](#7-makefiletaskfile-targets)
8. [Docker Integration](#8-docker-integration)
9. [Configuration](#9-configuration)
10. [Migration from golang-migrate](#10-migration-from-golang-migrate)

---

## 1. Overview

Atlas is a modern database migration tool that uses **declarative schema management**:

- **Single source of truth**: Define your desired schema in `schema.sql`
- **Automatic migration generation**: Atlas diffs current vs desired state
- **Go SDK integration**: Run migrations programmatically via devkit/common
- **Schema validation**: Detect drift between code and database

### Key Benefits

| Feature | Description |
|---------|-------------|
| Declarative | Define desired state, Atlas generates migrations |
| Diffing | Automatic migration generation from schema changes |
| Go SDK | Programmatic migration execution |
| Validation | Schema drift detection |
| Versioned | Migration history with checksums |

---

## 2. Directory Structure

```
service/
├── atlas/
│   ├── atlas.hcl           # Atlas configuration
│   ├── schema.sql          # Declarative schema (source of truth)
│   └── migrations/         # Generated migration files
│       ├── 20260130120000_initial.sql
│       ├── 20260130130000_add_users.sql
│       └── atlas.sum       # Checksum file for integrity
├── cmd/
│   └── migratedb/
│       └── cmd.go          # CLI command for running migrations
└── internal/
    └── config/
        └── configuration.go  # AtlasConfig embedded
```

---

## 3. Atlas Configuration (atlas.hcl)

```hcl
// atlas/atlas.hcl

// Database connection variables (passed at runtime)
variable "user" {
  type    = string
  default = "postgres"
}

variable "password" {
  type    = string
  default = "postgres"
}

variable "host" {
  type    = string
  default = "localhost"
}

variable "port" {
  type    = string
  default = "5432"
}

variable "db_name" {
  type    = string
  default = "myservice"
}

variable "ssl_mode" {
  type    = string
  default = "disable"
}

variable "ssl_rootcert" {
  type    = string
  default = ""
}

// Conditional SSL root cert parameter
locals {
  ssl_rootcert_param = var.ssl_rootcert != "" ? "&sslrootcert=${var.ssl_rootcert}" : ""
}

// Local development environment
env "local" {
  // Source schema - single source of truth
  src = "file://schema.sql"
  
  // Database URL with variables
  url = "postgres://${var.user}:${var.password}@${var.host}:${var.port}/${var.db_name}?sslmode=${var.ssl_mode}${local.ssl_rootcert_param}"
  
  // Dev database for diffing (same as url for local)
  dev = "postgres://${var.user}:${var.password}@${var.host}:${var.port}/${var.db_name}?sslmode=${var.ssl_mode}${local.ssl_rootcert_param}"
  
  // Migration directory
  migration {
    dir              = "file://migrations"
    revisions_schema = "public"
  }
  
  // SQL formatting
  format {
    migrate {
      diff = "{{ sql . \"  \" }}"
    }
  }
}

// Production environment (example)
env "production" {
  src = "file://schema.sql"
  url = "postgres://${var.user}:${var.password}@${var.host}:${var.port}/${var.db_name}?sslmode=${var.ssl_mode}${local.ssl_rootcert_param}"
  
  migration {
    dir              = "file://migrations"
    revisions_schema = "public"
  }
}
```

---

## 4. Declarative Schema (schema.sql)

Define your desired database schema. This is the **single source of truth**.

```sql
-- atlas/schema.sql
-- MyService Database Schema

-- ============================================================
-- Enum Types
-- ============================================================

CREATE TYPE item_status AS ENUM (
    'ACTIVE',
    'INACTIVE',
    'ARCHIVED'
);

CREATE TYPE user_role AS ENUM (
    'ADMIN',
    'USER',
    'GUEST'
);

-- ============================================================
-- Tables
-- ============================================================

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(255) PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    role user_role NOT NULL DEFAULT 'USER',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Items table
CREATE TABLE IF NOT EXISTS items (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    quantity INTEGER NOT NULL DEFAULT 0,
    status item_status NOT NULL DEFAULT 'ACTIVE',
    owner_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_items_owner FOREIGN KEY (owner_id) 
        REFERENCES users(id) ON DELETE CASCADE
);

-- ============================================================
-- Indexes
-- ============================================================

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);

CREATE INDEX idx_items_name ON items(name);
CREATE INDEX idx_items_status ON items(status);
CREATE INDEX idx_items_owner_id ON items(owner_id);
CREATE INDEX idx_items_created_at ON items(created_at DESC);
```

### Schema Best Practices

1. **Always use `IF NOT EXISTS`** for tables
2. **Define foreign key constraints** with appropriate ON DELETE behavior
3. **Create indexes** for frequently queried columns
4. **Use ENUMs** for fixed sets of values
5. **Include timestamps** (created_at, updated_at) on all tables
6. **Always set `revisions_schema = "public"` in every `migration {}` block** -- without this, Atlas creates a separate `atlas_schema_revisions` schema next to `public`. When the Kubernetes init container restarts, Atlas tries to recreate it and fails with `relation already exists`, causing an infinite crash loop. Storing revisions inside `public` is idempotent and safe

---

## 5. Go Integration (devkit/common)

Use `gitlab.com/umo-tech-ltd-group/platform/devkit/common/postgres/atlas` package for programmatic migration execution.

### Configuration Struct

```go
// internal/config/configuration.go
package config

import (
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/config"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/postgres"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/postgres/atlas"
)

type Configuration struct {
    ServiceName string          `mapstructure:"service_name"`
    Postgres    postgres.Config `mapstructure:"postgres"`
    Atlas       atlas.Config    `mapstructure:"atlas"`
    // ... other config
}

func Load() (*Configuration, config.Meta, error) {
    cfg, meta, err := config.Load[Configuration](
        config.WithEnvPrefix("MYSERVICE"),
        config.WithConfigName("configuration"),
        config.WithConfigPaths("./config", "."),
        config.WithRequired("postgres.host", "postgres.database"),
        config.WithRedactKeys("postgres.password"),
    )
    if err != nil {
        return nil, config.Meta{}, err
    }
    
    // Apply defaults for Atlas config
    if cfg.Atlas.AtlasDir == "" {
        cfg.Atlas = atlas.DefaultConfig()
    }
    
    return cfg, meta, nil
}
```

### YAML Configuration

```yaml
# config/configuration.yaml
service_name: myservice

postgres:
  host: localhost
  port: 5432
  database: myservice
  user: postgres
  password: postgres
  ssl_mode: disable
  max_conns: 25
  min_conns: 5

atlas:
  atlas_dir: ./atlas
  migrations_dir: migrations
  config_file: atlas.hcl
  env: local
```

---

## 6. CLI Command (cmd/migratedb)

Create a CLI command for running migrations using devkit/common.

```go
// cmd/migratedb/cmd.go
package migratedb

import (
    "context"
    "fmt"
    "time"

    "github.com/spf13/cobra"

    "your-service/internal/config"
    
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    zaplogger "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger/zap"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/postgres/atlas"
)

// Command returns the migrate-db cobra command.
var Command = &cobra.Command{
    Use:   "migrate-db",
    Short: "Run database migrations using Atlas",
    Long:  `Applies pending database migrations using the Atlas migration tool.`,
    RunE:  runMigrations,
}

func runMigrations(cmd *cobra.Command, args []string) error {
    // Load configuration
    cfg, _, err := config.Load()
    if err != nil {
        return fmt.Errorf("failed to load config: %w", err)
    }

    // Create logger
    log, err := logger.New(cfg.Logger, zaplogger.WithOTelTracing())
    if err != nil {
        return fmt.Errorf("failed to create logger: %w", err)
    }
    defer func() { _ = log.Sync() }()

    // Create migrator
    migrator := atlas.NewMigrator()
    defer func() { _ = migrator.Close() }()

    // Create context with timeout
    ctx, cancel := context.WithTimeout(cmd.Context(), 2*time.Minute)
    defer cancel()

    log.Info(ctx, "starting Atlas migrations",
        logger.String("atlas_dir", cfg.Atlas.AtlasDir),
        logger.String("env", cfg.Atlas.Env),
    )

    // Create DB config for Atlas
    dbCfg := atlas.NewDBConfigFromPostgres(
        cfg.Postgres.Host,
        cfg.Postgres.Port,
        cfg.Postgres.User,
        cfg.Postgres.Password,
        cfg.Postgres.Database,
        cfg.Postgres.SSLMode,
    )

    // Run migrations
    if err := migrator.RunMigrations(ctx, dbCfg, cfg.Atlas); err != nil {
        log.Error(ctx, "failed to run migrations", logger.Err(err))
        return fmt.Errorf("migration failed: %w", err)
    }

    log.Info(ctx, "migrations completed successfully")
    return nil
}
```

### Register in Root Command

```go
// cmd/root.go
package cmd

import (
    "github.com/spf13/cobra"
    
    "your-service/cmd/migratedb"
)

var rootCmd = &cobra.Command{
    Use:   "myservice",
    Short: "MyService application",
}

func init() {
    rootCmd.AddCommand(migratedb.Command)
    // ... other commands
}

func Execute() error {
    return rootCmd.Execute()
}
```

---

## 7. Makefile/Taskfile Targets

### Makefile Targets

```makefile
# Variables
ATLAS_DIR=./atlas
ATLAS_ENV=local
DB_USER=postgres
DB_PASSWORD=postgres
DB_HOST=localhost
DB_PORT=5432
DB_NAME=myservice
DB_SSL_MODE=disable

# ============================================================
# Atlas Migration Commands
# ============================================================

.PHONY: atlas-install atlas-diff atlas-apply atlas-status migrate-db

atlas-install: ## Install Atlas CLI
	@echo "Installing Atlas CLI..."
	@curl -sSf https://atlasgo.sh | sh
	@echo "Atlas installed successfully!"
	@atlas version

atlas-diff: ## Generate new migration from schema changes (usage: make atlas-diff NAME=migration_name)
	@if [ -z "$(NAME)" ]; then \
		echo "Error: NAME is required. Usage: make atlas-diff NAME=add_users_table"; \
		exit 1; \
	fi
	@echo "Generating migration $(NAME)..."
	@cd $(ATLAS_DIR) && atlas migrate diff $(NAME) \
		--env $(ATLAS_ENV) \
		--format '{{ sql . "  " }}' \
		--var host=$(DB_HOST) \
		--var port=$(DB_PORT) \
		--var user=$(DB_USER) \
		--var password=$(DB_PASSWORD) \
		--var db_name=$(DB_NAME) \
		--var ssl_mode=$(DB_SSL_MODE)
	@echo "Migration generated in $(ATLAS_DIR)/migrations/"

atlas-apply: ## Apply migrations using Atlas CLI
	@echo "Applying migrations..."
	@cd $(ATLAS_DIR) && atlas migrate apply \
		--env $(ATLAS_ENV) \
		--var host=$(DB_HOST) \
		--var port=$(DB_PORT) \
		--var user=$(DB_USER) \
		--var password=$(DB_PASSWORD) \
		--var db_name=$(DB_NAME) \
		--var ssl_mode=$(DB_SSL_MODE)
	@echo "Migrations applied"

atlas-status: ## Show migration status
	@echo "Migration status:"
	@cd $(ATLAS_DIR) && atlas migrate status \
		--env $(ATLAS_ENV) \
		--var host=$(DB_HOST) \
		--var port=$(DB_PORT) \
		--var user=$(DB_USER) \
		--var password=$(DB_PASSWORD) \
		--var db_name=$(DB_NAME) \
		--var ssl_mode=$(DB_SSL_MODE)

migrate-db: ## Run migrations via Go CLI (recommended for production)
	@echo "Running migrations via Go CLI..."
	@go run ./main.go migrate-db
```

### Taskfile (Alternative)

```yaml
# Taskfile.yaml
version: '3'

vars:
  ATLAS_DIR: ./atlas
  ATLAS_ENV: local
  DB_USER: postgres
  DB_PASSWORD: postgres
  DB_HOST: localhost
  DB_PORT: 5432
  DB_NAME: myservice
  DB_SSL_MODE: disable

tasks:
  atlas-install:
    desc: Install Atlas CLI
    cmds:
      - curl -sSf https://atlasgo.sh | sh
      - atlas version

  atlas-diff:
    desc: Generate new migration from schema changes
    dir: "{{.ATLAS_DIR}}"
    vars:
      NAME: '{{.name}}'
    preconditions:
      - sh: '[ -n "{{.NAME}}" ]'
        msg: "Migration name is required. Usage: task atlas-diff name=<migration_name>"
    cmds:
      - >
        atlas migrate diff {{.NAME}} 
        --env {{.ATLAS_ENV}} 
        --format '{{ "{{" }} sql . "  " {{ "}}" }}' 
        --var host={{.DB_HOST}} 
        --var port={{.DB_PORT}} 
        --var user={{.DB_USER}} 
        --var password={{.DB_PASSWORD}} 
        --var db_name={{.DB_NAME}} 
        --var ssl_mode={{.DB_SSL_MODE}}

  atlas-apply:
    desc: Apply migrations using Atlas CLI
    dir: "{{.ATLAS_DIR}}"
    cmds:
      - >
        atlas migrate apply 
        --env {{.ATLAS_ENV}} 
        --var host={{.DB_HOST}} 
        --var port={{.DB_PORT}} 
        --var user={{.DB_USER}} 
        --var password={{.DB_PASSWORD}} 
        --var db_name={{.DB_NAME}} 
        --var ssl_mode={{.DB_SSL_MODE}}

  migrate-db:
    desc: Run migrations via Go CLI
    cmds:
      - go run ./main.go migrate-db
```

---

## 8. Docker Integration

### Dockerfile with Atlas CLI

```dockerfile
# Dockerfile
# Build stage
FROM golang:1.25.5-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git ca-certificates curl

# Install Atlas CLI
RUN curl -sSf https://atlasgo.sh | sh

# Copy go mod files first for better caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o /app/bin/myservice ./main.go

# Runtime stage
FROM alpine:3.19

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache ca-certificates tzdata

# Install Atlas CLI for migrations
RUN apk add --no-cache curl && \
    curl -sSf https://atlasgo.sh | sh && \
    apk del curl

# Copy binary from builder
COPY --from=builder /app/bin/myservice /app/myservice

# Copy config and atlas files
COPY config/ /app/config/
COPY atlas/ /app/atlas/

# Expose ports
EXPOSE 8080 50051

# Set entrypoint
ENTRYPOINT ["/app/myservice"]
CMD ["serve"]
```

### Entrypoint Script (Optional)

```bash
#!/bin/sh
# deployment/local/entrypoint.sh

set -e

# Run migrations before starting the service
echo "Running database migrations..."
./myservice migrate-db

# Start the main service
echo "Starting service..."
exec ./myservice "$@"
```

### Docker Compose for Local Development

```yaml
# docker-compose.yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: myservice-postgres
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: myservice
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - myservice-network

volumes:
  postgres_data:
    driver: local

networks:
  myservice-network:
    driver: bridge
```

---

## 9. Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MYSERVICE_ATLAS_ATLAS_DIR` | Path to Atlas directory | `./atlas` |
| `MYSERVICE_ATLAS_MIGRATIONS_DIR` | Migrations subdirectory | `migrations` |
| `MYSERVICE_ATLAS_CONFIG_FILE` | Atlas config filename | `atlas.hcl` |
| `MYSERVICE_ATLAS_ENV` | Atlas environment | `local` |
| `MYSERVICE_POSTGRES_HOST` | Database host | `localhost` |
| `MYSERVICE_POSTGRES_PORT` | Database port | `5432` |
| `MYSERVICE_POSTGRES_DATABASE` | Database name | - |
| `MYSERVICE_POSTGRES_USER` | Database user | - |
| `MYSERVICE_POSTGRES_PASSWORD` | Database password | - |

---

## 10. Migration from golang-migrate

If your service currently uses golang-migrate, follow these steps to migrate to Atlas:

### Step 1: Create Atlas Directory

```bash
mkdir -p atlas/migrations
```

### Step 2: Generate Schema from Existing Database

```bash
# Inspect current database schema
atlas schema inspect \
  -u "postgres://postgres:postgres@localhost:5432/myservice?sslmode=disable" \
  --format '{{ sql . "  " }}' \
  > atlas/schema.sql
```

### Step 3: Create Atlas Configuration

Create `atlas/atlas.hcl` using the template in [Section 3](#3-atlas-configuration-atlashcl).

### Step 4: Initialize Atlas Migrations

```bash
# Create initial migration that represents current state
cd atlas
atlas migrate diff initial \
  --env local \
  --var host=localhost \
  --var port=5432 \
  --var user=postgres \
  --var password=postgres \
  --var db_name=myservice \
  --var ssl_mode=disable
```

### Step 5: Create Migration CLI Command

Create `cmd/migratedb/cmd.go` using the template in [Section 6](#6-cli-command-cmdmigratedb).

### Step 6: Update Makefile

Replace golang-migrate targets with Atlas targets from [Section 7](#7-makefiletaskfile-targets).

**Remove these targets:**
```makefile
# REMOVE these golang-migrate targets
migrate-install:
migrate-up:
migrate-down:
migrate-create:
migrate-force:
migrate-version:
```

**Add Atlas targets:**
```makefile
# ADD Atlas targets (see Section 7)
atlas-install:
atlas-diff:
atlas-apply:
atlas-status:
migrate-db:
```

### Step 7: Update Dockerfile

Add Atlas CLI installation to your Dockerfile (see [Section 8](#8-docker-integration)).

### Step 8: Update Configuration

Add `atlas.Config` to your Configuration struct:

```go
import "gitlab.com/umo-tech-ltd-group/platform/devkit/common/postgres/atlas"

type Configuration struct {
    // ... existing fields
    Atlas atlas.Config `mapstructure:"atlas"`
}
```

Add Atlas config to `config/configuration.yaml`:

```yaml
atlas:
  atlas_dir: ./atlas
  migrations_dir: migrations
  config_file: atlas.hcl
  env: local
```

### Step 9: Remove Old Migrations Directory

After verifying Atlas migrations work correctly:

```bash
# Backup first
mv migrations migrations.bak

# After testing, remove
rm -rf migrations.bak
```

### Migration Checklist

- [ ] Created `atlas/` directory structure
- [ ] Generated `schema.sql` from existing database
- [ ] Created `atlas.hcl` configuration
- [ ] Created initial migration
- [ ] Added `cmd/migratedb/cmd.go`
- [ ] Updated Makefile with Atlas targets
- [ ] Added `atlas.Config` to Configuration
- [ ] Updated YAML config
- [ ] Updated Dockerfile with Atlas CLI
- [ ] Tested migration execution
- [ ] Removed old `migrations/` directory

---

## Quick Reference

### Common Commands

```bash
# Install Atlas CLI
make atlas-install

# Generate migration after schema.sql changes
make atlas-diff NAME=add_orders_table

# Apply migrations (CLI)
make atlas-apply

# Apply migrations (Go - recommended for production)
make migrate-db

# Check migration status
make atlas-status
```

### Workflow

1. Edit `atlas/schema.sql` to add/modify tables
2. Run `make atlas-diff NAME=description` to generate migration
3. Review generated migration in `atlas/migrations/`
4. Run `make migrate-db` to apply (or `make atlas-apply` for CLI)
5. Commit both `schema.sql` and new migration file
