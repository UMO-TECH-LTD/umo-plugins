# Service Refactoring Guide

Step-by-step guide for refactoring existing Go services to follow the Hexagonal Architecture standard.

## Pre-Refactoring Assessment

### Current State Analysis

Before refactoring, analyze the existing service:

1. **Identify Violations**
   - Database queries in handlers?
   - Business logic in handlers?
   - External service calls in handlers?
   - Lack of interfaces?
   - No observability?

2. **Map Domain Boundaries**
   - What are the main entities?
   - What operations exist?
   - What external services are called?

3. **Dependency Audit**
   - What DI framework is used (if any)?
   - How is configuration loaded?
   - How is logging done?

### Common Anti-Patterns to Fix

| Anti-Pattern | Solution |
|--------------|----------|
| DB in handler | Move to repository |
| Business logic in handler | Move to service |
| Concrete dependencies | Use interfaces |
| Scattered logging | Use instrumentation wrapper |
| Manual tracing | Use `trace.Instrument()` |
| Hardcoded config | Environment variables |

## Refactoring Steps

### Step 1: Extract Domain Entities

**Goal**: Create pure domain layer with no external dependencies.

1. Create `internal/core/<domain>/` directory
2. Move/create entity structs
3. Remove ALL external imports
4. Add entity methods (validation, state checks)
5. Create domain errors

**Before**:
```go
// internal/handlers/user_handler.go
type User struct {
    gorm.Model
    Email    string `gorm:"uniqueIndex"`
    Name     string
    Role     string
}

func (h *Handler) CreateUser(ctx context.Context, req *pb.CreateUserRequest) {
    user := &User{Email: req.Email, Name: req.Name}
    h.db.Create(user)
    // ...
}
```

**After**:
```go
// internal/core/user/user.go
package user

import "time"

type User struct {
    ID        string
    Email     string
    Name      string
    Role      Role
    CreatedAt time.Time
    UpdatedAt time.Time
}

// NO gorm, NO external imports
```

### Step 2: Define Service Interfaces

**Goal**: Create clear contracts between layers.

1. Create `internal/services/<domain>/service.go`
2. Define interface with all operations
3. Define service-specific Repo interface (dependency inversion)

**Example**:
```go
// internal/services/users/service.go
package users

type Service interface {
    CreateUser(ctx context.Context, email, name string, role user.Role) (*user.User, error)
    GetUser(ctx context.Context, id string) (*user.User, error)
    // ...
}

// internal/services/users/default_service.go
// Service-specific repo interface - only what this service needs
type Repo interface {
    SaveUser(ctx context.Context, u *user.User) error
    GetUser(ctx context.Context, id string) (*user.User, error)
    // ...
}
```

### Step 3: Extract Business Logic to Services

**Goal**: Move business logic from handlers to services.

1. Create `internal/services/<domain>/default_service.go`
2. Move business logic from handlers
3. Inject repository interface
4. Add proper error handling with wrapping

**Before** (handler with business logic):
```go
func (h *Handler) CreateUser(ctx context.Context, req *pb.CreateUserRequest) (*pb.CreateUserResponse, error) {
    // Business logic mixed with handler
    if req.Role != "admin" && req.Role != "user" {
        return nil, status.Error(codes.InvalidArgument, "invalid role")
    }
    
    var existing User
    if h.db.Where("email = ?", req.Email).First(&existing).Error == nil {
        return nil, status.Error(codes.AlreadyExists, "user exists")
    }
    
    user := &User{
        Email: req.Email,
        Name:  req.Name,
        Role:  req.Role,
    }
    h.db.Create(user)
    
    return &pb.CreateUserResponse{User: toProto(user)}, nil
}
```

**After** (clean separation):
```go
// internal/services/users/default_service.go
func (s *DefaultService) CreateUser(ctx context.Context, email, name string, role user.Role) (*user.User, error) {
    if !role.IsValid() {
        return nil, user.ErrInvalidRole
    }
    
    existing, err := s.repo.GetUserByEmail(ctx, email)
    if err != nil {
        return nil, fmt.Errorf("failed to check existing: %w", err)
    }
    if existing != nil {
        return nil, user.ErrAlreadyExists
    }
    
    u := &user.User{
        ID:        uuid.New().String(),
        Email:     email,
        Name:      name,
        Role:      role,
        Status:    user.StatusPending,
        CreatedAt: time.Now().UTC(),
        UpdatedAt: time.Now().UTC(),
    }
    
    if err := s.repo.SaveUser(ctx, u); err != nil {
        return nil, fmt.Errorf("failed to save: %w", err)
    }
    
    return u, nil
}

// internal/handlers/grpc/users.go
func (h *Handler) CreateUser(ctx context.Context, req *pb.CreateUserRequest) (*pb.CreateUserResponse, error) {
    role := protomap.ProtoToRole(req.Role)
    
    u, err := h.usersService.CreateUser(ctx, req.Email, req.Name, role)
    if err != nil {
        return nil, mapError(err)
    }
    
    return &pb.CreateUserResponse{User: protomap.UserToProto(u)}, nil
}
```

### Step 4: Add Instrumentation Wrappers

**Goal**: Add observability without polluting business logic.

1. Create `internal/services/<domain>/instrumentation.go`
2. Wrap each method with tracing, logging, metrics
3. Replace direct service usage with instrumented version

**Pattern**:
```go
// internal/services/users/instrumentation.go
import (
    "context"
    "time"

    "go.opentelemetry.io/otel/attribute"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace"
)

type InstrumentedService struct {
    s   *DefaultService
    log logger.Logger
}

func NewInstrumentedService(s *DefaultService, log logger.Logger) *InstrumentedService {
    return &InstrumentedService{s: s, log: log.Named("users")}
}

func (i *InstrumentedService) CreateUser(ctx context.Context, email, name string, role user.Role) (*user.User, error) {
    start := time.Now()
    ctx, span := trace.Instrument(ctx, i.s.CreateUser)
    defer span.End()

    i.log.Debug(ctx, "creating user", "email", email)

    result, err := i.s.CreateUser(ctx, email, name, role)

    // Metrics
    duration := time.Since(start).Seconds()
    m := metrics.Get()
    if m != nil {
        m.IncOperations(ctx, attribute.String("operation", "create_user"))
        m.RecordDuration(ctx, duration, attribute.String("operation", "create_user"))
        if err != nil {
            m.IncErrors(ctx, attribute.String("operation", "create_user"))
        }
    }

    if err != nil {
        i.log.Error(ctx, "failed to create user", "error", err)
        span.RecordError(err)
        span.SetStatus(trace.StatusError, "failed")
        return nil, err
    }

    i.log.Info(ctx, "user created", "id", result.ID)
    span.SetStatus(trace.StatusOK, "success")
    return result, nil
}
```

### Step 5: Implement Repository Pattern

**Goal**: Abstract data persistence behind interfaces.

1. Create/update `internal/repo/repo.go` with interface
2. Create `internal/repo/postgres/repo.go` implementation
3. Create `internal/repo/root.go` composition
4. Add instrumentation wrapper

**Migrate from GORM to Ent** (if needed):
1. Create Ent schema in `internal/repo/postgres/ent/schema/`
2. Generate Ent code: `task generate:ent`
3. Implement repository using Ent client
4. Map Ent entities to domain entities

### Step 6: Update Handlers

**Goal**: Make handlers thin - only transport concerns.

Handlers should:
- Parse requests
- Call services
- Map errors to transport codes
- Format responses

**Error Mapping**:
```go
func mapError(err error) error {
    switch {
    case errors.Is(err, user.ErrNotFound):
        return status.Error(codes.NotFound, err.Error())
    case errors.Is(err, user.ErrAlreadyExists):
        return status.Error(codes.AlreadyExists, err.Error())
    case errors.Is(err, user.ErrInvalidRole):
        return status.Error(codes.InvalidArgument, err.Error())
    default:
        return status.Error(codes.Internal, "internal error")
    }
}
```

### Step 7: Migrate to Uber Fx with platformfx

**Goal**: Proper dependency injection with lifecycle management using devkit/common.

1. Create `cmd/serve.go` following the bootstrap template (see `references/bootstrap-templates.md`)
2. Use `platformfx.Module` as the first Fx module (provides `shutdown.Manager`)
3. Register shutdown hooks via `platformfx.ProvideShutdownHook` with priority levels
4. Remove manual initialization and old `ServiceBuilder` patterns

**platformfx + Shutdown Hooks Pattern**:
```go
import (
    "go.uber.org/fx"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/shutdown"
)

// In your DI module — register shutdown hooks with priority:
var Module = fx.Module("postgres",
    fx.Provide(func(cfg *config.Config) (*ent.Client, error) {
        return ent.Open(dialect.Postgres, cfg.Postgres.DSN())
    }),
    platformfx.ProvideShutdownHook(func(client *ent.Client) shutdown.Hook {
        return shutdown.Hook{
            Name:     "postgres",
            Priority: shutdown.PriorityDatabase, // 60
            Fn:       func(ctx context.Context) error { return client.Close() },
        }
    }),
    fx.Provide(postgres.NewRepo),
    fx.Provide(repo.NewRootRepo),
    fx.Provide(func(r *repo.RootRepo) repo.Repo {
        return repo.NewInstrumentedRepo(r)
    }),
)
```

**Shutdown Priority Levels** (lower = shut down first):
- `PriorityServer` (10) — HTTP/gRPC servers, Temporal workers
- `PriorityMessaging` (30) — NATS, Kafka consumers
- `PriorityCache` (50) — Redis connections
- `PriorityDatabase` (60) — PostgreSQL, Ent clients
- `PriorityTracing` (80) — OTel, Sentry flush

### Step 8: Update Configuration

**Goal**: Typed configuration with `config.Load[T]()` and environment-specific YAML files.

1. Move to `internal/config/config.go` using `config.Load[Config]()` (see `references/bootstrap-templates.md` §4)
2. Add `mapstructure` tags on every field and `default` tags for library defaults
3. Use `config.WithEnvironmentFile("ENVIRONMENT", "./configs")` to load YAML per environment
4. Create `configs/local.yaml`, `configs/staging.yaml`, etc. with environment-specific values
5. Embed devkit config types directly: `logger.Config`, `trace.Config`, `sentry.Config`, `platformfx.Config`
6. Add post-load propagation: `ServiceName`/`Environment` → Logger, Trace, Sentry sub-configs
7. Remove any direct `viper` imports — use only `config.Load[T]()` with options

## Verification Checklist

After refactoring, verify:

### Architecture
- [ ] Domain entities have NO external imports
- [ ] Services depend on interfaces only
- [ ] Handlers are thin (transport only)
- [ ] Repository pattern implemented

### Observability
- [ ] All services have instrumentation wrappers
- [ ] Tracing uses `trace.Instrument()` / `trace.InstrumentNamed()` (NOT `trace.Start`)
- [ ] Span status uses `trace.StatusError` / `trace.StatusOK` (NOT `codes.Error/Ok`)
- [ ] Metrics recorded for operations
- [ ] Structured logging via `logger.Logger` interface (NOT `xctx.Logger(ctx)`)

### Configuration
- [ ] Config uses `config.Load[T]()` — no direct `viper` imports
- [ ] YAML config files in `configs/` directory per environment
- [ ] `mapstructure` + `default` tags on config struct fields
- [ ] Sensible defaults via struct tags and `defaults()` map

### Lifecycle
- [ ] Graceful shutdown implemented
- [ ] All resources cleaned up
- [ ] Health check working

### Testing
- [ ] Unit tests with mocks
- [ ] Tests pass: `go test ./...`
- [ ] Linter passes: `golangci-lint run`

## Common Issues and Solutions

### Issue: Circular Imports

**Problem**: Service imports handler or vice versa.

**Solution**: Use interfaces and dependency inversion. Services define their own Repo interface, don't import the repo package interface.

### Issue: Leaky Abstractions

**Problem**: Ent types appearing in service layer.

**Solution**: Map to domain types at repository boundary.

### Issue: Missing Context Propagation

**Problem**: Lost trace context in service calls.

**Solution**: Always pass `ctx` through all layers.

### Issue: Inconsistent Error Handling

**Problem**: Some errors logged, some not, inconsistent wrapping.

**Solution**: Use instrumentation wrapper for all error handling.
