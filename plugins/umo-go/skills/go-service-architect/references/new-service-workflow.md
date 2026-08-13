# New Service Creation Workflow

Complete step-by-step guide for creating a new Go microservice from scratch.

## Phase 1: Requirements Gathering

Before writing code, gather these requirements:

### Questions to Ask

1. **Service Purpose**: What is the service responsible for?
2. **Domain Entities**: What are the main entities?
3. **Operations**: What CRUD and business operations are needed?
4. **Dependencies**: What external services does it need to call?
5. **Storage**: PostgreSQL, Redis, or both?
6. **Transport**: gRPC only, or gRPC + HTTP/Connect?
7. **Events**: Does it need Kafka publishing/consuming?

### Example Requirements Document

```markdown
# User Service Requirements

## Purpose
Manages user accounts, authentication, and user profiles.

## Domain Entities
- User (main entity)
  - id, email, name, role, status, created_at, updated_at
- Role (value object): ADMIN, USER, VIEWER
- Status (value object): PENDING, ACTIVE, INACTIVE, DELETED

## Operations
- CreateUser(email, name, role) -> User
- GetUser(id) -> User
- GetUserByEmail(email) -> User
- ListUsers(filters) -> []User
- UpdateUser(id, updates) -> User
- DeleteUser(id)
- ActivateUser(id)
- DeactivateUser(id)
- ChangeUserRole(id, newRole)

## Storage
- PostgreSQL for persistent data
- Redis for caching (optional)

## Transport
- gRPC for service-to-service
- No HTTP needed
```

## Phase 2: Project Setup

### Step 1: Create Directory Structure

```bash
mkdir -p my-new-service
cd my-new-service

# Create directory structure
mkdir -p cmd
mkdir -p config
mkdir -p internal/config
mkdir -p internal/di/http
mkdir -p internal/di/grpc
mkdir -p internal/di/postgres
mkdir -p internal/core/item
mkdir -p internal/services/item
mkdir -p internal/repo/postgres/item
mkdir -p internal/handlers/http
mkdir -p internal/handlers/grpc
mkdir -p api/proto/item/v1
mkdir -p migrations
mkdir -p test/integration
mkdir -p test/e2e
```

### Step 2: Initialize Go Module

```bash
go mod init your-service-module-path
```

### Step 3: Create Core Files Using Templates

Copy the following templates from the skill's reference files:

**From `references/bootstrap-templates.md`:**
- `main.go` - Entry point
- `cmd/root.go` - Root command
- `cmd/serve.go` - Serve command (bootstrap with Fx)
- `internal/config/configuration.go` - Configuration loader
- `internal/di/http/module.go` - HTTP DI module
- `internal/di/grpc/module.go` - gRPC DI module
- `internal/di/postgres/module.go` - PostgreSQL DI module
- `internal/handlers/http/middleware.go` - HTTP middleware
- `internal/handlers/http/router.go` - HTTP router

**From `references/infrastructure-templates.md`:**
- `Makefile` - Build and run commands
- `docker-compose.yaml` - Local development dependencies
- `config/configuration.yaml` - Default configuration
- `.gitignore` - Git ignore rules

### Step 4: Customize Configuration

Update in `internal/config/config.go`:
- Set `config.WithEnvironmentFile("ENVIRONMENT", "./configs")` to load YAML per environment
- Update the `default` tag on `ServiceName` to your service name
- Add/remove config sections as needed (see `references/bootstrap-templates.md` §4)
- Create `configs/local.yaml` with environment-specific values

### Step 5: Update Makefile Variables

Edit `Makefile`:
```makefile
# Update these variables
BINARY_NAME=my-new-service
DB_URL=postgres://postgres:postgres@localhost:5432/my_new_service?sslmode=disable
```

### Step 6: Update docker-compose.yaml

Edit `docker-compose.yaml`:
- Change database name and container names to match your service

## Phase 3: Domain Implementation

### Step 1: Create Domain Entities

```bash
mkdir -p internal/core/user
```

Create files:
- `internal/core/user/user.go` - Main entity
- `internal/core/user/role.go` - Role value object
- `internal/core/user/status.go` - Status value object
- `internal/core/user/errors.go` - Domain errors

### Domain Entity Rules

1. **NO external imports** - Only standard library
2. **Pure functions** - No side effects in methods
3. **Self-validating** - Entities validate their own invariants
4. **Meaningful methods** - `IsActive()`, `CanPerform()`, etc.

### Example Entity

```go
// internal/core/user/user.go
package user

import "time"

type User struct {
    ID        string
    Email     string
    Name      string
    Role      Role
    Status    Status
    CreatedAt time.Time
    UpdatedAt time.Time
}

// IsActive returns true if the user is active.
func (u *User) IsActive() bool {
    return u.Status == StatusActive
}

// CanBeDeleted returns true if the user can be deleted.
func (u *User) CanBeDeleted() bool {
    return u.Status != StatusDeleted
}

// CanBeActivated returns true if the user can be activated.
func (u *User) CanBeActivated() bool {
    return u.Status != StatusDeleted
}
```

## Phase 4: Service Layer

### Step 1: Create Service Directory

```bash
mkdir -p internal/services/users
```

### Step 2: Define Service Interface

Create `internal/services/users/service.go`:

```go
package users

import (
    "context"
    "your-service/internal/core/user"
)

type Service interface {
    CreateUser(ctx context.Context, email, name string, role user.Role) (*user.User, error)
    GetUser(ctx context.Context, id string) (*user.User, error)
    ListUsers(ctx context.Context) ([]*user.User, error)
    // ... other operations
}
```

### Step 3: Implement Default Service

Create `internal/services/users/default_service.go`:

1. Define service-specific Repo interface (dependency inversion)
2. Create struct with repo dependency
3. Implement all Service interface methods
4. Add proper error handling and validation

### Step 4: Add Instrumentation

Create `internal/services/users/instrumentation.go`:

1. Create wrapper struct
2. Wrap each method with:
   - Span creation
   - Logging
   - Metrics recording
   - Error handling

## Phase 5: Repository Layer

### Step 1: Define Ent Schema

Create/update `internal/repo/postgres/ent/schema/user.go`:

```go
package schema

import (
    "time"
    "entgo.io/ent"
    "entgo.io/ent/schema/field"
)

type User struct {
    ent.Schema
}

func (User) Fields() []ent.Field {
    return []ent.Field{
        field.String("id").Unique().Immutable(),
        field.String("email").Unique(),
        field.String("name"),
        field.String("role"),
        field.String("status"),
        field.Time("created_at").Default(time.Now).Immutable(),
        field.Time("updated_at").Default(time.Now).UpdateDefault(time.Now),
    }
}
```

### Step 2: Generate Ent Code

```bash
task generate:ent
# or
go run -mod=mod entgo.io/ent/cmd/ent generate --feature sql/upsert ./internal/repo/postgres/ent/schema
```

### Step 3: Implement Repository

Update `internal/repo/postgres/repo.go`:
- Add CRUD methods
- Map between Ent entities and domain entities
- Use proper error handling

### Step 4: Update Root Repository

Update `internal/repo/root.go`:
- Delegate to postgres repo methods
- Add any Redis caching if needed

## Phase 6: Transport Layer

> **Proto-api migration**: New services should define proto files in the centralized `proto-api` repository, not locally. Generated Go/TS stubs are consumed as dependencies. See the `proto-api-migration` skill and the `proto-authoring` skill in the proto-api repo for the full workflow. The local `api/protobuf/` approach shown below is for legacy reference only.

### Step 1: Define Protobuf Schema

Create/update `api/protobuf/v1/service.proto`:

```protobuf
syntax = "proto3";

package user.v1;
option go_package = "your-service/internal/proto/gen/v1;userv1";

service UserService {
    rpc CreateUser(CreateUserRequest) returns (CreateUserResponse);
    rpc GetUser(GetUserRequest) returns (GetUserResponse);
    // ...
}

message User {
    string id = 1;
    string email = 2;
    string name = 3;
    Role role = 4;
    Status status = 5;
}

enum Role {
    ROLE_UNSPECIFIED = 0;
    ROLE_ADMIN = 1;
    ROLE_USER = 2;
    ROLE_VIEWER = 3;
}
```

### Step 2: Generate Protobuf Code

```bash
task generate:proto
# or
buf generate
```

### Step 3: Implement gRPC Handler

Update `internal/handlers/grpc/handler.go` and `users.go`:
- Implement all RPC methods
- Map proto requests/responses to domain types
- Map domain errors to gRPC status codes

## Phase 7: Dependency Injection (DI Modules)

Services are wired using Fx DI modules in `internal/di/`. Each infrastructure component has its own module.

### HTTP Module - `internal/di/http/module.go`

```go
var Module = fx.Module("http",
    // Provide Gin engine
    fx.Provide(NewGinEngine),

    // Provide domain services
    fx.Provide(NewItemService),

    // Provide HTTP handlers
    fx.Provide(httphandlers.NewHandlers),

    // Provide HTTP server
    fx.Provide(NewHTTPServer),

    // Register lifecycle hooks
    fx.Invoke(RegisterHTTPLifecycle),

    // Register shutdown hook
    platformfx.ProvideShutdownHook(NewHTTPShutdownHook),
)

// NewItemService creates a new item service with instrumentation.
func NewItemService(repo item.Repository, log logger.Logger, provider trace.Provider) *itemservice.Service {
    return itemservice.NewService(repo, log, provider)
}
```

### Bootstrap in cmd/serve.go

```go
app := fx.New(
    loggerfx.WithFxLoggerFromConfig(cfg.Logger),
    platformfx.Module(cfg.Platform),         // ALWAYS FIRST
    loggerfx.ModuleWithOptions(cfg.Logger,
        zaplogger.WithOTelTracing(),
        zaplogger.WithContextValues(),
    ),
    tracefx.Module(cfg.Trace),
    fx.Provide(func() *config.Configuration { return cfg }),
    postgres.Module,  // Database
    httpdi.Module,    // HTTP server
    grpcdi.Module,    // gRPC server
    fx.Invoke(registerServiceLifecycle),
)
```

## Phase 8: Testing

### Unit Tests

Create `internal/services/users/default_service_test.go`:

```go
func TestCreateUser_Success(t *testing.T) {
    mockRepo := new(MockRepo)
    service := users.NewDefaultService(mockRepo)
    
    mockRepo.On("GetUserByEmail", mock.Anything, "test@example.com").Return(nil, nil)
    mockRepo.On("SaveUser", mock.Anything, mock.AnythingOfType("*user.User")).Return(nil)
    
    result, err := service.CreateUser(context.Background(), "test@example.com", "Test", user.RoleUser)
    
    assert.NoError(t, err)
    assert.NotNil(t, result)
    mockRepo.AssertExpectations(t)
}
```

### Integration Tests

Create `test/integration/users_test.go` with testcontainers.

## Phase 9: Final Verification

### Build Check

```bash
make mod-tidy
go build ./...
go test ./...
```

### Compliance Checklist

- [ ] Bootstrap uses `platformfx.Module()` first
- [ ] Logger uses `loggerfx.ModuleWithOptions()` with OTel integration
- [ ] Domain entities have NO external dependencies
- [ ] Services depend on interfaces, not implementations
- [ ] All services have instrumentation wrappers using `trace.Instrument`
- [ ] Shutdown hooks registered via `platformfx.ProvideShutdownHook`
- [ ] gRPC uses devkit/common interceptor chain
- [ ] HTTP uses devkit/common middleware
- [ ] Configuration uses `config.Load[T]` with validation
- [ ] Trivy scan passes: `trivy fs --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed .` → 0 findings
- [ ] Unit tests pass
- [ ] Linter passes: `make lint`

### Run Locally

```bash
# 1. Start dependencies (PostgreSQL)
make up

# 2. Install Atlas CLI (first time only)
make atlas-install

# 3. Run database migrations
make migrate-db

# 4. Run the service
make run

# 5. Test endpoints
curl http://localhost:8080/health
curl http://localhost:8080/api/v1/items

# 6. Test gRPC
grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check

# 7. Stop dependencies
make down
```

### Quick Setup (All Steps)

```bash
# Install Atlas CLI (first time only)
make atlas-install

# Start PostgreSQL and run migrations
make up
make migrate-db

# Run the service
make run
```
