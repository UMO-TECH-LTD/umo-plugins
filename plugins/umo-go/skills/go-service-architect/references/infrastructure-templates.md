# Infrastructure Templates

Complete, copy-paste ready templates for service infrastructure (Makefile, docker-compose, Atlas migrations, etc.).

## Table of Contents

1. [Go Module](#1-go-module)
2. [Makefile](#2-makefile)
3. [Docker Compose](#3-docker-compose)
4. [Dockerfile](#4-dockerfile)
5. [Atlas Migrations](#5-atlas-migrations)
6. [Proto Files](#6-proto-files)
7. [Gitignore](#7-gitignore)
8. [Placeholder Directories (.gitkeep)](#8-placeholder-directories-gitkeep)

---

## 1. Go Module

```go
// go.mod
module your-service

go 1.25.5

require (
    github.com/gin-gonic/gin v1.11.0
    github.com/google/uuid v1.6.0
    github.com/jackc/pgx/v5 v5.9.0
    github.com/prometheus/client_golang v1.23.2
    github.com/spf13/cobra v1.8.1
    gitlab.com/umo-tech-ltd-group/platform/devkit/common v0.31.1 // use latest released version
    go.uber.org/fx v1.24.0
    google.golang.org/grpc v1.80.0
    google.golang.org/protobuf v1.36.11
)
```

---

## 2. Makefile

```makefile
.PHONY: help build run test test-coverage lint fmt clean docker-build atlas-install atlas-diff atlas-apply atlas-status migrate-db up down logs setup proto proto-install

# Variables - CUSTOMIZE THESE
BINARY_NAME=myservice
BINARY_PATH=./bin/$(BINARY_NAME)
MAIN_PATH=./main.go
DOCKER_IMAGE=myservice:latest
PROTO_DIR=api/proto

# Atlas Variables
ATLAS_DIR=./atlas
ATLAS_ENV=local
DB_USER=postgres
DB_PASSWORD=postgres
DB_HOST=localhost
DB_PORT=5432
DB_NAME=myservice
DB_SSL_MODE=disable

help: ## Display this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

# ============================================================
# Development Commands
# ============================================================

up: ## Start all dependencies (docker-compose)
	@echo "Starting dependencies..."
	@docker-compose up -d
	@echo "Dependencies started. Waiting for PostgreSQL to be ready..."
	@sleep 3
	@echo "Dependencies are ready!"

down: ## Stop all dependencies (docker-compose)
	@echo "Stopping dependencies..."
	@docker-compose down
	@echo "Dependencies stopped"

logs: ## Show logs from dependencies
	@docker-compose logs -f

setup: up ## Setup project (start dependencies + run migrations)
	@echo "Setting up project..."
	@sleep 2
	@$(MAKE) migrate-db
	@echo "Project setup complete! You can now run: make run"

# ============================================================
# Build & Run Commands
# ============================================================

build: ## Build the service binary
	@echo "Building $(BINARY_NAME)..."
	@mkdir -p bin
	@go build -o $(BINARY_PATH) $(MAIN_PATH)
	@echo "Binary built: $(BINARY_PATH)"

run: ## Run the service
	@echo "Running $(BINARY_NAME)..."
	@go run $(MAIN_PATH) serve

run-http: ## Run only HTTP server
	@echo "Running HTTP server..."
	@go run $(MAIN_PATH) http

run-grpc: ## Run only gRPC server
	@echo "Running gRPC server..."
	@go run $(MAIN_PATH) grpc

# ============================================================
# Testing Commands
# ============================================================

test: ## Run all tests
	@echo "Running tests..."
	@go test -v ./...

test-coverage: ## Run tests with coverage report
	@echo "Running tests with coverage..."
	@go test -cover -coverprofile=coverage.out ./...
	@go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"

# ============================================================
# Code Quality Commands
# ============================================================

lint: ## Run linter
	@echo "Running linter..."
	@golangci-lint run

fmt: ## Format code
	@echo "Formatting code..."
	@gofmt -w .
	@echo "Code formatted"

clean: ## Clean build artifacts
	@echo "Cleaning..."
	@rm -rf bin/
	@rm -f coverage.out coverage.html
	@echo "Clean complete"

# ============================================================
# Docker Commands
# ============================================================

docker-build: ## Build Docker image
	@echo "Building Docker image..."
	@docker build -t $(DOCKER_IMAGE) .
	@echo "Docker image built: $(DOCKER_IMAGE)"

# ============================================================
# Go Module Commands
# ============================================================

mod-tidy: ## Run go mod tidy
	@echo "Running go mod tidy..."
	@go mod tidy
	@echo "Dependencies updated"

mod-download: ## Download dependencies
	@echo "Downloading dependencies..."
	@go mod download
	@echo "Dependencies downloaded"

# ============================================================
# Atlas Database Migration Commands
# ============================================================

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
	@go run $(MAIN_PATH) migrate-db

# ============================================================
# Proto Generation Commands
# ============================================================

proto-install: ## Install protobuf tools
	@echo "Installing protobuf tools..."
	@go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
	@go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
	@echo "Protobuf tools installed successfully!"
	@echo "Make sure $(shell go env GOPATH)/bin is in your PATH"
	@echo ""
	@echo "You also need 'protoc' installed:"
	@echo "  - macOS: brew install protobuf"
	@echo "  - Linux: apt install protobuf-compiler"

proto: ## Generate Go code from proto files
	@if ! command -v protoc &> /dev/null; then \
		echo "Error: 'protoc' command not found!"; \
		echo "Install it: macOS: brew install protobuf, Linux: apt install protobuf-compiler"; \
		exit 1; \
	fi
	@echo "Generating Go code from proto files..."
	@protoc \
		--proto_path=$(PROTO_DIR) \
		--go_out=. \
		--go_opt=module=your-service \
		--go-grpc_out=. \
		--go-grpc_opt=module=your-service \
		$(PROTO_DIR)/item/v1/*.proto
	@echo "Proto code generated successfully!"

proto-clean: ## Clean generated proto files
	@echo "Cleaning generated proto files..."
	@find $(PROTO_DIR) -name "*.pb.go" -delete
	@echo "Generated proto files cleaned"
```

---

## 3. Docker Compose

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

  # Optional: OpenTelemetry Collector for tracing
  # otel-collector:
  #   image: otel/opentelemetry-collector-contrib:latest
  #   container_name: myservice-otel
  #   command: ["--config=/etc/otel-collector-config.yaml"]
  #   volumes:
  #     - ./deployment/local/otel-collector-config.yaml:/etc/otel-collector-config.yaml
  #   ports:
  #     - "4317:4317"   # OTLP gRPC
  #     - "4318:4318"   # OTLP HTTP
  #   networks:
  #     - myservice-network

  # Optional: Jaeger for viewing traces
  # jaeger:
  #   image: jaegertracing/all-in-one:latest
  #   container_name: myservice-jaeger
  #   ports:
  #     - "16686:16686"  # Jaeger UI
  #     - "14268:14268"  # Collector HTTP
  #   networks:
  #     - myservice-network

  # Optional: Kafka for event publishing
  # See references/kafka-templates.md for producer/consumer patterns
  # zookeeper:
  #   image: confluentinc/cp-zookeeper:7.5.0
  #   container_name: myservice-zookeeper
  #   environment:
  #     ZOOKEEPER_CLIENT_PORT: 2181
  #     ZOOKEEPER_TICK_TIME: 2000
  #   networks:
  #     - myservice-network
  #
  # kafka:
  #   image: confluentinc/cp-kafka:7.5.0
  #   container_name: myservice-kafka
  #   depends_on:
  #     - zookeeper
  #   environment:
  #     KAFKA_BROKER_ID: 1
  #     KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
  #     KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
  #     KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
  #     KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
  #     KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
  #   ports:
  #     - "9092:9092"
  #   networks:
  #     - myservice-network

volumes:
  postgres_data:
    driver: local

networks:
  myservice-network:
    driver: bridge
```

---

## 4. Dockerfile

```dockerfile
# Dockerfile
# Build stage — version must match go.mod (see go-dockerfile-version-sync rule)
FROM public.ecr.aws/docker/library/golang:1.25.5-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git ca-certificates curl

# GitLab private module authentication (required for gitlab.com/* deps)
ARG GITLAB_USER=gitlab-ci-token
ARG GITLAB_TOKEN

RUN if [ -n "$GITLAB_TOKEN" ]; then \
    ENCODED_USER=$(echo "${GITLAB_USER}" | sed 's/@/%40/g') && \
    git config --global url."https://${ENCODED_USER}:${GITLAB_TOKEN}@gitlab.com/".insteadOf "https://gitlab.com/umo-tech-ltd-group/"; \
    fi

ENV GOPRIVATE=gitlab.com/*

# Install Atlas CLI for migrations
RUN curl -sSf https://atlasgo.sh | sh

# Copy go mod files first for better caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o /app/bin/myservice ./main.go

# Runtime stage — pin alpine to a specific version, use ECR prefix
FROM public.ecr.aws/docker/library/alpine:3.22

WORKDIR /app

# Install runtime dependencies and Atlas CLI
RUN apk add --no-cache ca-certificates tzdata curl && \
    curl -sSf https://atlasgo.sh | sh && \
    apk del curl

# Copy binary from builder
COPY --from=builder /app/bin/myservice /app/myservice

# Copy config and atlas files
COPY config/ /app/config/
COPY atlas/ /app/atlas/

# Non-root user for runtime security (Trivy DS-0002)
RUN addgroup -S app && adduser -S app -G app
RUN chown -R app:app /app
USER app

# Expose ports
EXPOSE 8080 50051

# Set entrypoint
ENTRYPOINT ["/app/myservice"]
CMD ["serve"]
```

---

## 5. Atlas Migrations

Atlas uses declarative schema management. For complete templates, see `references/atlas-migrations.md`.

### Directory Structure

```
atlas/
├── atlas.hcl           # Atlas configuration
├── schema.sql          # Declarative schema (source of truth)
└── migrations/         # Generated migration files
    ├── 20260130120000_initial.sql
    └── atlas.sum       # Checksum file
```

### Example Schema (schema.sql)

```sql
-- atlas/schema.sql
-- Service Database Schema

CREATE TYPE item_status AS ENUM (
    'ACTIVE',
    'INACTIVE',
    'ARCHIVED'
);

CREATE TABLE IF NOT EXISTS items (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    quantity INTEGER NOT NULL DEFAULT 0,
    status item_status NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_items_name ON items(name);
CREATE INDEX idx_items_status ON items(status);
CREATE INDEX idx_items_created_at ON items(created_at DESC);
```

### Example Configuration (atlas.hcl)

```hcl
// atlas/atlas.hcl
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
    dir = "file://migrations"
  }
  
  format {
    migrate {
      diff = "{{ sql . \"  \" }}"
    }
  }
}
```

### Quick Commands

```bash
# Install Atlas CLI
make atlas-install

# Generate migration after editing schema.sql
make atlas-diff NAME=add_users_table

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
4. Run `make migrate-db` to apply
5. Commit both `schema.sql` and new migration file

For complete documentation including Go integration with devkit/common, CLI command setup, and migration from golang-migrate, see `references/atlas-migrations.md`.

---

## 6. Proto Files

> **Note on Proto Files**: While this template includes proto files locally, we are migrating to a centralized proto repository. New services should plan for proto definitions to be managed externally and imported as dependencies.

### Service Proto

```protobuf
// api/proto/item/v1/item.proto
syntax = "proto3";

package item.v1;

option go_package = "your-service/api/proto/item/v1;itemv1";

import "google/protobuf/timestamp.proto";

// ItemService provides CRUD operations for items.
service ItemService {
  // CreateItem creates a new item.
  rpc CreateItem(CreateItemRequest) returns (CreateItemResponse);
  
  // GetItem retrieves an item by ID.
  rpc GetItem(GetItemRequest) returns (GetItemResponse);
  
  // ListItems retrieves all items.
  rpc ListItems(ListItemsRequest) returns (ListItemsResponse);
  
  // UpdateItem updates an existing item.
  rpc UpdateItem(UpdateItemRequest) returns (UpdateItemResponse);
  
  // DeleteItem deletes an item by ID.
  rpc DeleteItem(DeleteItemRequest) returns (DeleteItemResponse);
}

// Item represents an item in the system.
message Item {
  string id = 1;
  string name = 2;
  string description = 3;
  string price = 4;  // Decimal as string for precision
  int32 quantity = 5;
  string status = 6;
  google.protobuf.Timestamp created_at = 7;
  google.protobuf.Timestamp updated_at = 8;
}

message CreateItemRequest {
  string name = 1;
  string description = 2;
  string price = 3;
  int32 quantity = 4;
}

message CreateItemResponse {
  Item item = 1;
}

message GetItemRequest {
  string id = 1;
}

message GetItemResponse {
  Item item = 1;
}

message ListItemsRequest {
  int32 page_size = 1;
  string page_token = 2;
}

message ListItemsResponse {
  repeated Item items = 1;
  string next_page_token = 2;
}

message UpdateItemRequest {
  string id = 1;
  optional string name = 2;
  optional string description = 3;
  optional string price = 4;
  optional int32 quantity = 5;
}

message UpdateItemResponse {
  Item item = 1;
}

message DeleteItemRequest {
  string id = 1;
}

message DeleteItemResponse {}
```

---

## 7. Gitignore

```gitignore
# .gitignore

# Binaries
bin/
*.exe
*.exe~
*.dll
*.so
*.dylib

# Test binary, built with `go test -c`
*.test

# Output of the go coverage tool
*.out
coverage.html

# Go workspace file
go.work
go.work.sum

# Dependency directories
vendor/

# IDE
.idea/
.vscode/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Environment files
.env
.env.local
.env.*.local

# Logs
*.log
logs/

# Generated files
*.pb.go

# Temporary files
tmp/
temp/

# Build cache
.cache/
```

---

## 8. Placeholder Directories (.gitkeep)

Use `.gitkeep` files to preserve empty directory structure in Git. This helps new developers understand the project layout even when some directories are empty.

### Required .gitkeep Files

Create these `.gitkeep` files for new services to show the expected directory structure:

```bash
# Create placeholder directories
mkdir -p internal/clients
mkdir -p internal/publisher
mkdir -p test/integration
mkdir -p test/e2e

# Add .gitkeep files
touch internal/clients/.gitkeep
touch internal/publisher/.gitkeep
touch test/integration/.gitkeep
touch test/e2e/.gitkeep
```

### Directory Purpose Guide

| Directory | Purpose | .gitkeep when empty? |
|-----------|---------|---------------------|
| `internal/clients/` | External service gRPC clients | Yes |
| `internal/publisher/` | Kafka event publishers | Yes |
| `test/integration/` | Integration tests | Yes |
| `test/e2e/` | End-to-end tests | Yes |

### .gitkeep File Content

The `.gitkeep` file can optionally contain a brief description:

```
# internal/clients/.gitkeep
# External service clients directory
# Each client follows the 3-file pattern:
#   - client.go           (interface)
#   - default_client.go   (gRPC implementation)
#   - instrumented.go     (observability wrapper)
# See: references/clients-templates.md
```

```
# internal/publisher/.gitkeep
# Kafka event publishers directory
# Each publisher follows the 3-file pattern:
#   - publisher.go        (interface)
#   - kafka.go            (Kafka implementation)
#   - instrumented.go     (observability wrapper)
```

---

## 9. Test Infrastructure

### docker-compose.test.yml

Minimal stack for integration and E2E tests:

```yaml
# deployment/local/docker-compose.test.yml
version: '3.8'

services:
  service:
    build:
      context: ../..
      dockerfile: Dockerfile
    ports:
      - "50051:50051"
      - "8080:8080"
    environment:
      - SERVICE_NAME=myservice-test
      - LOG_LEVEL=debug
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=postgres
      - DB_PASSWORD=postgres
      - DB_NAME=testdb
      - DB_SSL_MODE=disable
      - REDIS_HOST=redis
      - REDIS_PORT=6379
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "grpc_health_probe", "-addr=:50051"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 10s

  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=testdb
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 2s
      timeout: 5s
      retries: 10

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 2s
      timeout: 5s
      retries: 10
```

### Test Makefile Targets

Add to Makefile:

```makefile
# Test targets
.PHONY: test-unit test-integration test-e2e test-all test-coverage

# Run unit tests
test-unit:
	@echo "Running unit tests..."
	go test -v -race ./internal/...

# Run integration tests (requires Docker)
test-integration:
	@echo "Running integration tests..."
	go test -v -tags=integration -timeout 5m ./test/integration/...

# Run E2E tests (requires Docker)
test-e2e:
	@echo "Running E2E tests..."
	go test -v -tags=e2e -timeout 10m ./test/e2e/...

# Run all tests
test-all: test-unit test-integration test-e2e

# Run tests with coverage
test-coverage:
	@echo "Running tests with coverage..."
	go test -v -race -coverprofile=coverage.out -covermode=atomic ./internal/...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report: coverage.html"

# Clean test artifacts
test-clean:
	@echo "Cleaning test artifacts..."
	rm -f coverage.out coverage.html
	docker compose -f deployment/local/docker-compose.test.yml -p test down -v --remove-orphans
```

### Test Build Tags

Use build tags for test isolation:

```go
// test/integration/product_test.go
//go:build integration

package integration

// Tests here only run with: go test -tags=integration ./...
```

```go
// test/e2e/workflow_test.go
//go:build e2e

package e2e

// Tests here only run with: go test -tags=e2e ./...
```

---

## 10. HTTP Middleware Chain (REQUIRED)

> **MANDATORY**: All HTTP services MUST include the complete middleware chain below. The `MetricsMiddleware` and `TracingMiddleware` are required for production observability.

### Complete Middleware Setup

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

// SetupMiddleware configures and returns the REQUIRED middleware chain for HTTP servers.
// Order matters - middleware is executed in the order listed.
func SetupMiddleware(log logger.Logger) []gin.HandlerFunc {
    return []gin.HandlerFunc{
        // 1. Recovery - handles panics (REQUIRED)
        commonhttp.RecoveryMiddleware(log),

        // 2. Tracing - creates OpenTelemetry spans (REQUIRED)
        tracehttp.TracingMiddleware(
            tracehttp.WithSkipper(tracehttp.SkipHealthChecks()),
            tracehttp.WithTraceIDHeader("X-Trace-Id"),
        ),

        // 3. Context enrichment - extracts request_id, tenant_id, user_id
        ContextEnrichmentMiddleware(),

        // 4. Logging - logs all requests (REQUIRED)
        commonhttp.LoggerMiddleware(log),

        // 5. Metrics - Prometheus HTTP metrics (REQUIRED)
        commonhttp.MetricsMiddleware(
            commonhttp.WithExcludePaths("/health", "/ready", "/metrics"),
        ),

        // 6. CORS - Cross-origin requests (configure as needed)
        commonhttp.CORSMiddleware(
            []string{"*"},
            []string{"GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"},
            []string{"Origin", "Content-Type", "Accept", "Authorization"},
        ),
    }
}

// ContextEnrichmentMiddleware enriches the request context with common values.
func ContextEnrichmentMiddleware() gin.HandlerFunc {
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

### Using Middleware in Gin Engine

```go
// internal/di/http/module.go
func NewGinEngine(cfg *config.Configuration, log logger.Logger) *gin.Engine {
    gin.SetMode(gin.ReleaseMode)
    engine := gin.New()

    // Apply REQUIRED middleware chain
    middleware := httphandlers.SetupMiddleware(log)
    engine.Use(middleware...)
    
    return engine
}
```

### Metrics Exposed

The `MetricsMiddleware` exposes these Prometheus metrics:

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `http_server_requests_total` | Counter | method, path, status | Total HTTP requests |
| `http_server_request_duration_seconds` | Histogram | method, path, status | Request duration |
| `http_server_requests_in_flight` | Gauge | method | Currently active requests |
| `http_server_request_size_bytes` | Histogram | method, path | Request body size |
| `http_server_response_size_bytes` | Histogram | method, path, status | Response body size |

### MetricsMiddleware Options

```go
// Exclude specific paths from metrics
commonhttp.WithExcludePaths("/health", "/ready", "/metrics")

// Custom path normalizer (for parameterized routes)
commonhttp.WithPathNormalizer(func(c *gin.Context) string {
    return c.FullPath() // Returns "/users/:id" instead of "/users/123"
})

// Group status codes (2xx, 4xx, 5xx instead of 200, 404, 500)
commonhttp.WithGroupedStatuses()

// Record request/response sizes
commonhttp.WithRecordSizes()

// Custom skipper function
commonhttp.WithSkipper(func(path string) bool {
    return strings.HasPrefix(path, "/internal/")
})
```

---

## Quick Start

After creating a new service using these templates:

```bash
# 1. Initialize Go module
go mod init your-service

# 2. Download dependencies
go mod tidy

# 3. Start PostgreSQL
make up

# 4. Install Atlas and run migrations
make atlas-install
make migrate-db

# 5. Generate proto files (if using gRPC)
make proto-install
make proto

# 6. Run the service
make run

# 7. Test endpoints
curl http://localhost:8080/health
curl http://localhost:8080/api/v1/items

# 8. Run tests
make test-unit
make test-integration  # Requires Docker
make test-e2e          # Requires Docker
```
