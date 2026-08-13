---
name: go-atlas-migrations
description: Atlas declarative database migrations for Go services using devkit/common/postgres/atlas. Use when adding or changing a schema, writing cmd/migrate, running or reviewing migrations, or debugging migration drift in a Go service.
---

# Atlas Database Migrations

Standard for all Go services in this repository. Uses **declarative schema management** with Atlas and the **devkit/common Atlas Go SDK** for programmatic migration execution.

---

## 1. Directory Structure

Every Go service with a database follows this layout:

```
service/
├── atlas/
│   ├── atlas.hcl           # Atlas configuration (connection variables, environments)
│   ├── schema.sql          # Declarative schema -- SINGLE SOURCE OF TRUTH
│   └── migrations/         # Generated migration files (never edit applied ones)
│       ├── YYYYMMDDHHMMSS_name.sql
│       └── atlas.sum       # Checksum file for integrity
├── cmd/
│   ├── migrate.go          # migrate-db CLI command using devkit/common
│   ├── serve.go            # Main service command
│   └── root.go             # Cobra root command
└── deploy/
    └── service.yaml        # migration: true triggers migrate-db before pod start
```

---

## 2. Programmatic Migration (Required for Deployment)

The deployment system reads `migration: true` from `deploy/service.yaml` and invokes the service binary with the `migrate-db` command **before** starting the main pod. This means every Go service must implement a working `migrate-db` command.

### Implementation

Use `devkit/common/postgres/atlas` directly. Do NOT create custom Atlas client wrappers.

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
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/postgres/atlas"

    "your-service/internal/config"
)

var migrateCmd = &cobra.Command{
    Use:   "migrate-db",
    Short: "Run database migrations",
    RunE: func(cmd *cobra.Command, args []string) error {
        return runMigrations()
    },
}

func runMigrations() error {
    cfg, _, err := config.Load()
    if err != nil {
        return fmt.Errorf("failed to load config: %w", err)
    }

    // Logger setup (keep environment-aware level).
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
    defer func() { _ = log.Sync() }()

    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
    defer cancel()

    log.Info(ctx, "Starting database migrations",
        logger.String("environment", cfg.Environment),
        logger.String("database", cfg.Postgres.Database),
        logger.String("host", cfg.Postgres.Host),
    )

    migrator := atlas.NewMigrator(atlas.WithLogger(log))
    defer func() { _ = migrator.Close() }()

    atlasCfg := atlas.DefaultConfig()
    dbCfg := atlas.NewDBConfigFromPostgres(
        cfg.Postgres.Host,
        cfg.Postgres.Port,
        cfg.Postgres.User,
        cfg.Postgres.Password,
        cfg.Postgres.Database,
        cfg.Postgres.SSLMode,
    )

    if err := migrator.RunMigrations(ctx, dbCfg, atlasCfg); err != nil {
        log.Error(ctx, "Migration failed", logger.Err(err))
        return fmt.Errorf("migration failed: %w", err)
    }

    log.Info(ctx, "Migrations completed successfully")
    return nil
}
```

### Key devkit/common types

| Function | Purpose |
|----------|---------|
| `atlas.NewMigrator(opts ...Option)` | Creates lazily-initialized migrator; use `atlas.WithLogger(log)` for structured logging; call `Close()` when done |
| `atlas.DefaultConfig()` | Returns `Config{AtlasDir: "./atlas", MigrationsDir: "migrations", ConfigFile: "atlas.hcl", Env: "local"}` |
| `atlas.NewDBConfigFromPostgres(host, port, user, password, database, sslMode)` | Converts service Postgres config to `DBConfig` |
| `migrator.RunMigrations(ctx, dbCfg, atlasCfg)` | Applies all pending migrations |
| `migrator.MigrateStatus(ctx, atlasCfg, dbCfg)` | Returns current migration status |

---

## 3. atlas.hcl Configuration

Variable names **must** match what the devkit migrator passes:

```hcl
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

env "local" {
  src = "file://schema.sql"
  url = "postgres://${var.user}:${var.password}@${var.host}:${var.port}/${var.db_name}?sslmode=${var.ssl_mode}"
  dev = "postgres://${var.user}:${var.password}@${var.host}:${var.port}/${var.db_name}?sslmode=${var.ssl_mode}"

  migration {
    dir              = "file://migrations"
    revisions_schema = "public"
  }

  format {
    migrate {
      diff = "{{ sql . \"  \" }}"
    }
  }
}

env "production" {
  src = "file://schema.sql"
  url = "postgres://${var.user}:${var.password}@${var.host}:${var.port}/${var.db_name}?sslmode=${var.ssl_mode}"

  migration {
    dir              = "file://migrations"
    revisions_schema = "public"
  }
}
```

---

## 4. Schema Workflow

1. Edit `atlas/schema.sql` (the single source of truth)
2. Generate migration: `make atlas-diff NAME=add_column`
3. Review generated SQL in `atlas/migrations/`
4. Apply locally: `make atlas-apply` (CLI) or `make migrate-db` (Go SDK)
5. Commit both `schema.sql` and the new migration file

---

## 5. Dockerfile Requirements

The runtime image must include:

1. **Atlas CLI** -- for the `migrate-db` command to invoke Atlas under the hood
2. **atlas/ directory** -- copied from the build context
3. **ca-certificates** -- for SSL database connections
4. **Non-root user** -- standard security hardening

```dockerfile
# Runtime stage
FROM public.ecr.aws/docker/library/alpine:3.20
WORKDIR /app

RUN apk add --no-cache ca-certificates tzdata

# Atlas CLI
RUN apk add --no-cache curl && \
    curl -sSf https://atlasgo.sh | sh && \
    apk del curl

# Non-root user
RUN addgroup -S app && adduser -S app -G app

COPY --from=builder /app/bin/myservice /app/myservice
COPY config/ /app/config/
COPY atlas/ /app/atlas/

RUN chown -R app:app /app
USER app

ENTRYPOINT ["/app/myservice"]
CMD ["serve"]
```

---

## 6. Rules

- **Never edit applied migrations** -- create new ones instead
- **Always use devkit/common/postgres/atlas** -- do not write custom Atlas client wrappers
- **Never run migrations on service startup** -- migrations are a separate CLI command (`migrate-db`), invoked by the deployment system before the main pod starts
- **Always review generated SQL** before applying
- **Use meaningful migration names** -- `make atlas-diff NAME=add_priority_to_tickets`
- **Test migrations locally** before committing
- **Variable names in atlas.hcl must match devkit** -- `user`, `password`, `host`, `port`, `db_name`, `ssl_mode`
- **Always set `revisions_schema = "public"` in every `migration {}` block** -- without this, Atlas creates a separate `atlas_schema_revisions` schema next to `public`. When the init container restarts it tries to recreate the schema and fails with `relation already exists`, causing an infinite crash loop. Storing the revision table inside `public` is idempotent and safe

---

## 7. Makefile Targets

```makefile
atlas-install: ## Install Atlas CLI
    @curl -sSf https://atlasgo.sh | sh

atlas-diff: ## Generate migration (usage: make atlas-diff NAME=migration_name)
    @cd atlas && atlas migrate diff $(NAME) --env local \
        --var host=$(DB_HOST) --var port=$(DB_PORT) \
        --var user=$(DB_USER) --var password=$(DB_PASSWORD) \
        --var db_name=$(DB_NAME) --var ssl_mode=$(DB_SSL_MODE)

atlas-apply: ## Apply migrations via Atlas CLI
    @cd atlas && atlas migrate apply --env local \
        --var host=$(DB_HOST) --var port=$(DB_PORT) \
        --var user=$(DB_USER) --var password=$(DB_PASSWORD) \
        --var db_name=$(DB_NAME) --var ssl_mode=$(DB_SSL_MODE)

atlas-status: ## Show migration status
    @cd atlas && atlas migrate status --env local \
        --var host=$(DB_HOST) --var port=$(DB_PORT) \
        --var user=$(DB_USER) --var password=$(DB_PASSWORD) \
        --var db_name=$(DB_NAME) --var ssl_mode=$(DB_SSL_MODE)

migrate-db: ## Run migrations via Go SDK (used by deployment)
    @go run ./main.go migrate-db
```
