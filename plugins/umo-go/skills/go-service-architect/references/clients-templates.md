# External Service Clients Templates

Complete templates for calling external gRPC services using the 3-file pattern with devkit/common.

## Table of Contents

1. [Directory Structure](#1-directory-structure)
2. [Client Interface](#2-client-interface)
3. [Default Client Implementation](#3-default-client-implementation)
4. [Instrumented Client Wrapper](#4-instrumented-client-wrapper)
5. [Configuration](#5-configuration)
6. [Fx Module Wiring](#6-fx-module-wiring)
7. [Complete Example](#7-complete-example)

---

## 1. Directory Structure

Each external service client follows the 3-file pattern:

```
internal/
└── clients/
    └── <service-name>/
        ├── client.go           # Interface definition (port)
        ├── default_client.go   # gRPC implementation using devkit/common/grpcclient
        └── instrumented.go     # Tracing + logging wrapper using devkit/common
```

**Pattern benefits:**
- **Separation of concerns**: Interface defines contract, implementation handles connection, wrapper adds observability
- **Testability**: Mock the interface easily in tests
- **Automatic instrumentation**: All calls get tracing and logging without changing business logic
- **Dependency inversion**: Services depend on interface, not implementation

---

## 2. Client Interface

The interface defines the contract for the external service. Keep it focused on what your service needs.

```go
// internal/clients/userservice/client.go
package userservice

import (
    "context"
    "time"
)

// Client defines the interface for the user service client.
// This interface should only contain methods your service actually needs,
// not necessarily all methods the external service provides.
type Client interface {
    // GetUser retrieves a user by ID.
    GetUser(ctx context.Context, id string) (*User, error)

    // GetUserByEmail retrieves a user by email address.
    GetUserByEmail(ctx context.Context, email string) (*User, error)

    // CreateUser creates a new user.
    CreateUser(ctx context.Context, req *CreateUserRequest) (*User, error)

    // Close closes the client connection.
    Close() error
}

// User represents a user from the external service.
// Define your own types rather than importing proto types directly.
type User struct {
    ID        string
    Email     string
    Name      string
    Role      string
    CreatedAt time.Time
    UpdatedAt time.Time
}

// CreateUserRequest contains the data for creating a new user.
type CreateUserRequest struct {
    Email string
    Name  string
    Role  string
}
```

**Key principles:**
- Define only the methods your service needs
- Use your own domain types, not proto types
- Include `Close()` method for cleanup

---

## 3. Default Client Implementation

The default client handles the actual gRPC connection and protocol translation.

```go
// internal/clients/userservice/default_client.go
package userservice

import (
    "context"
    "time"

    "google.golang.org/grpc"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/grpcclient"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    tracegrpc "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace/grpc"

    userpb "external-service/api/proto/user/v1"
)

// DefaultClient is the default gRPC implementation of Client.
type DefaultClient struct {
    conn   *grpc.ClientConn
    client userpb.UserServiceClient
}

// NewDefaultClient creates a new gRPC client for the user service.
func NewDefaultClient(cfg *ClientConfig, log logger.Logger) (*DefaultClient, error) {
    ctx := context.Background()

    // Build client interceptors (order matters - outermost first)
    unaryInterceptors := []grpc.UnaryClientInterceptor{
        // 1. Tracing - propagates trace context to downstream service
        tracegrpc.UnaryClientInterceptor(),
        // 2. Request ID - passes X-Request-Id header to downstream
        grpcclient.RequestIDUnaryInterceptor(),
        // 3. Logging - logs outgoing calls with method, duration, status
        grpcclient.LoggingUnaryInterceptor(
            grpcclient.WithLoggingLogger(log),
        ),
        // 4. Metrics - client-side Prometheus metrics
        grpcclient.MetricsUnaryInterceptor(),
    }

    streamInterceptors := []grpc.StreamClientInterceptor{
        tracegrpc.StreamClientInterceptor(),
        grpcclient.RequestIDStreamInterceptor(),
        grpcclient.LoggingStreamInterceptor(
            grpcclient.WithLoggingLogger(log),
        ),
        grpcclient.MetricsStreamInterceptor(),
    }

    // Build gRPC connection using devkit/common builder
    builder := grpcclient.NewBuilder(cfg.GRPCConfig).
        WithUnaryInterceptors(unaryInterceptors...).
        WithStreamInterceptors(streamInterceptors...)

    conn, err := builder.Build(ctx)
    if err != nil {
        return nil, err
    }

    return &DefaultClient{
        conn:   conn,
        client: userpb.NewUserServiceClient(conn),
    }, nil
}

// GetUser retrieves a user by ID.
func (c *DefaultClient) GetUser(ctx context.Context, id string) (*User, error) {
    resp, err := c.client.GetUser(ctx, &userpb.GetUserRequest{Id: id})
    if err != nil {
        return nil, err
    }
    return protoToUser(resp.User), nil
}

// GetUserByEmail retrieves a user by email.
func (c *DefaultClient) GetUserByEmail(ctx context.Context, email string) (*User, error) {
    resp, err := c.client.GetUserByEmail(ctx, &userpb.GetUserByEmailRequest{Email: email})
    if err != nil {
        return nil, err
    }
    return protoToUser(resp.User), nil
}

// CreateUser creates a new user.
func (c *DefaultClient) CreateUser(ctx context.Context, req *CreateUserRequest) (*User, error) {
    resp, err := c.client.CreateUser(ctx, &userpb.CreateUserRequest{
        Email: req.Email,
        Name:  req.Name,
        Role:  req.Role,
    })
    if err != nil {
        return nil, err
    }
    return protoToUser(resp.User), nil
}

// Close closes the gRPC connection.
func (c *DefaultClient) Close() error {
    return c.conn.Close()
}

// ==================== Conversion Functions ====================

// protoToUser converts a proto User to the domain User type.
func protoToUser(u *userpb.User) *User {
    if u == nil {
        return nil
    }
    return &User{
        ID:        u.Id,
        Email:     u.Email,
        Name:      u.Name,
        Role:      u.Role,
        CreatedAt: u.CreatedAt.AsTime(),
        UpdatedAt: u.UpdatedAt.AsTime(),
    }
}
```

---

## 4. Instrumented Client Wrapper

The instrumented wrapper adds tracing and logging around every client call.

```go
// internal/clients/userservice/instrumented.go
package userservice

import (
    "context"
    "time"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace"
)

// InstrumentedClient wraps a Client with tracing and logging.
type InstrumentedClient struct {
    inner Client
    log   logger.Logger
}

// NewInstrumentedClient creates a new instrumented client wrapper.
func NewInstrumentedClient(inner Client, log logger.Logger) *InstrumentedClient {
    return &InstrumentedClient{
        inner: inner,
        log:   log.Named("clients.userservice"),
    }
}

// GetUser retrieves a user by ID with instrumentation.
func (c *InstrumentedClient) GetUser(ctx context.Context, id string) (*User, error) {
    start := time.Now()

    // Create span for this client call
    ctx, span := trace.Instrument(ctx, c.inner.GetUser)
    defer span.End()

    // Add business-specific attributes
    span.SetAttributes(
        trace.String("user.id", id),
        trace.String("rpc.service", "user.v1.UserService"),
        trace.String("rpc.method", "GetUser"),
    )

    c.log.Debug(ctx, "calling user service",
        logger.String("method", "GetUser"),
        logger.String("user_id", id),
    )

    // Make the call
    result, err := c.inner.GetUser(ctx, id)

    duration := time.Since(start)
    span.SetAttributes(trace.Float64("duration_seconds", duration.Seconds()))

    if err != nil {
        span.RecordError(err)
        span.SetStatus(trace.StatusError, "failed to get user")
        c.log.Error(ctx, "user service call failed",
            logger.String("method", "GetUser"),
            logger.String("user_id", id),
            logger.Err(err),
            logger.Duration("duration", duration),
        )
        return nil, err
    }

    span.SetStatus(trace.StatusOK, "user retrieved")
    c.log.Debug(ctx, "user service call succeeded",
        logger.String("method", "GetUser"),
        logger.String("user_id", id),
        logger.Duration("duration", duration),
    )

    return result, nil
}

// GetUserByEmail retrieves a user by email with instrumentation.
func (c *InstrumentedClient) GetUserByEmail(ctx context.Context, email string) (*User, error) {
    start := time.Now()

    ctx, span := trace.Instrument(ctx, c.inner.GetUserByEmail)
    defer span.End()

    span.SetAttributes(
        trace.String("user.email", email),
        trace.String("rpc.service", "user.v1.UserService"),
        trace.String("rpc.method", "GetUserByEmail"),
    )

    c.log.Debug(ctx, "calling user service",
        logger.String("method", "GetUserByEmail"),
        logger.String("email", email),
    )

    result, err := c.inner.GetUserByEmail(ctx, email)

    duration := time.Since(start)
    span.SetAttributes(trace.Float64("duration_seconds", duration.Seconds()))

    if err != nil {
        span.RecordError(err)
        span.SetStatus(trace.StatusError, "failed to get user by email")
        c.log.Error(ctx, "user service call failed",
            logger.String("method", "GetUserByEmail"),
            logger.String("email", email),
            logger.Err(err),
            logger.Duration("duration", duration),
        )
        return nil, err
    }

    span.SetStatus(trace.StatusOK, "user retrieved")
    return result, nil
}

// CreateUser creates a new user with instrumentation.
func (c *InstrumentedClient) CreateUser(ctx context.Context, req *CreateUserRequest) (*User, error) {
    start := time.Now()

    ctx, span := trace.Instrument(ctx, c.inner.CreateUser)
    defer span.End()

    span.SetAttributes(
        trace.String("user.email", req.Email),
        trace.String("rpc.service", "user.v1.UserService"),
        trace.String("rpc.method", "CreateUser"),
    )

    c.log.Info(ctx, "creating user via user service",
        logger.String("email", req.Email),
        logger.String("name", req.Name),
    )

    result, err := c.inner.CreateUser(ctx, req)

    duration := time.Since(start)
    span.SetAttributes(trace.Float64("duration_seconds", duration.Seconds()))

    if err != nil {
        span.RecordError(err)
        span.SetStatus(trace.StatusError, "failed to create user")
        c.log.Error(ctx, "user service call failed",
            logger.String("method", "CreateUser"),
            logger.String("email", req.Email),
            logger.Err(err),
            logger.Duration("duration", duration),
        )
        return nil, err
    }

    span.SetStatus(trace.StatusOK, "user created")
    c.log.Info(ctx, "user created successfully",
        logger.String("user_id", result.ID),
        logger.Duration("duration", duration),
    )

    return result, nil
}

// Close closes the underlying client connection.
func (c *InstrumentedClient) Close() error {
    return c.inner.Close()
}
```

---

## 5. Configuration

### Inter-Service gRPC Env Var Naming Convention

All inter-service gRPC connection details live in the **shared** `services/.env` and follow a strict naming convention. Do **not** invent service-private env var names (e.g. `MY_AUTH_HOST`) for cross-service connections — always consume the shared names so the deploy ConfigMap stays the single source of truth.

| Pattern | Description | Example |
|---------|-------------|---------|
| `SAAS_{SERVICE}_GRPC_HOST` | Host/IP for a SaaS internal service | `SAAS_AUTH_GRPC_HOST=15.0.1.28` |
| `SAAS_{SERVICE}_GRPC_PORT` | gRPC port | `SAAS_AUTH_GRPC_PORT=5000` |
| `SAAS_{SERVICE}_GRPC_SSL` | Enable TLS (optional, `true`/`false`) | `SAAS_RATES_GRPC_SSL=true` |
| `WALLET_{SERVICE}_GRPC_HOST` | Host for wallet-namespace services | `WALLET_AUTH_GRPC_HOST=15.0.2.4` |
| `WALLET_{SERVICE}_GRPC_PORT` | gRPC port for wallet services | `WALLET_AUTH_GRPC_PORT=5000` |

`{SERVICE}` is the uppercased, underscore-separated service name (e.g. `AUTH`, `PAYMENT_CORE`, `KYC_COMPLIANCE`).

**Auto-mapping does not cover these names.** Devkit's `config.Load[T]` auto-maps `mapstructure:"clients.auth.host"` to the env var `CLIENTS_AUTH_HOST` (dots replaced by underscores, uppercased). `SAAS_AUTH_GRPC_HOST` will never match that path automatically — you must bridge the gap explicitly. Two patterns are in use:

---

#### Pattern A — Recommended for new services: `WithEnvBindings`

Declare a `ClientTarget` struct with `host`/`port`/`ssl` fields and bind each one to the corresponding `SAAS_*` env var inside `config.Load[T]`:

```go
// internal/config/configuration.go

// ClientTarget is a host+port+ssl tuple. Build a grpcclient.Config from it after Load.
type ClientTarget struct {
    Host string `mapstructure:"host" default:"localhost"`
    Port string `mapstructure:"port" default:"50051"`
    SSL  bool   `mapstructure:"ssl"  default:"false"`
}

// Target returns the gRPC dial target.
func (t ClientTarget) Target() string {
    return fmt.Sprintf("%s:%s", t.Host, t.Port)
}

type ClientsConfig struct {
    Auth        ClientTarget `mapstructure:"auth"`
    PaymentCore ClientTarget `mapstructure:"payment_core"`
}

type Configuration struct {
    // ...
    Clients ClientsConfig `mapstructure:"clients"`
}
```

```go
// internal/config/load.go

cfg, _, err := config.Load[Configuration](
    config.WithEnvironmentFile("ENVIRONMENT", "./configs"),
    config.WithDefaults(defaults()),
    config.WithEnvBindings(map[string]string{
        // Map SAAS_*_GRPC_HOST/PORT/SSL → viper config keys.
        "clients.auth.host":         "SAAS_AUTH_GRPC_HOST",
        "clients.auth.port":         "SAAS_AUTH_GRPC_PORT",
        "clients.auth.ssl":          "SAAS_AUTH_GRPC_SSL",
        "clients.payment_core.host": "SAAS_PAYMENT_CORE_GRPC_HOST",
        "clients.payment_core.port": "SAAS_PAYMENT_CORE_GRPC_PORT",
        // wallet services
        "clients.wallet_auth.host":  "WALLET_AUTH_GRPC_HOST",
        "clients.wallet_auth.port":  "WALLET_AUTH_GRPC_PORT",
    }),
)
```

```go
// Build grpcclient.Config from the loaded target after Load returns.
func newGRPCClientConfig(t ClientTarget) grpcclient.Config {
    return grpcclient.Config{
        Target:             t.Target(),
        Insecure:           !t.SSL,
        ConnectTimeout:     10 * time.Second,
        DefaultCallTimeout: 30 * time.Second,
    }
}
```

Local defaults go in the YAML config file (loaded before env vars, so they act as fallbacks):

```yaml
# configs/local.yaml
clients:
  auth:
    host: "15.0.1.28"
    port: "5000"
    ssl: false
  payment_core:
    host: "15.0.1.16"
    port: "50051"
    ssl: false
```

---

#### Pattern B — Current reality in many services: `os.Getenv` composition before `Load`

Read the split env vars with `os.Getenv` before calling `config.Load[T]`, compose them into a single `host:port` string, then apply the result to the config struct. This is the pattern used by `services/core` for its FeatureScript client:

```go
// Reference: services/core/internal/config/config.go composeFeatureScriptAddrFromSplitEnv

// composeSAASClientAddr reads SAAS_{SVC}_GRPC_HOST and SAAS_{SVC}_GRPC_PORT,
// constructs "host:port", and sets a service-private env var that viper
// auto-maps to clients.<svc>.target via mapstructure.
func composeSAASClientAddr(svcEnvPrefix, configTarget, defaultPort string) {
    host := os.Getenv("SAAS_" + svcEnvPrefix + "_GRPC_HOST")
    if host == "" {
        return
    }
    port := os.Getenv("SAAS_" + svcEnvPrefix + "_GRPC_PORT")
    if port == "" {
        port = defaultPort
    }
    _ = os.Setenv(configTarget, fmt.Sprintf("%s:%s", host, port))
}

// Call this before config.Load[T]:
composeSAASClientAddr("AUTH", "CLIENTS_AUTH_TARGET", "5000")
composeSAASClientAddr("PAYMENT_CORE", "CLIENTS_PAYMENT_CORE_TARGET", "50051")
```

Alternatively, apply the composed address to the struct after `Load` returns (as `core` does with `cfg.FeatureScript.WithServerAddr(...)`):

```go
cfg, _, err := config.Load[Configuration](...)
if err != nil { ... }

if host := os.Getenv("SAAS_AUTH_GRPC_HOST"); host != "" {
    port := os.Getenv("SAAS_AUTH_GRPC_PORT")
    if port == "" { port = "5000" }
    cfg.Clients.Auth.Target = fmt.Sprintf("%s:%s", host, port)
}
```

Pattern B is the current status quo in most existing services. **Prefer Pattern A for new services** — it keeps all env bindings declared in one place and avoids `os.Getenv` scattered through `Load`.

---

### Client Configuration Struct

```go
// internal/clients/userservice/config.go (optional, can be in main config)
package userservice

import (
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/grpcclient"
)

// ClientConfig holds configuration for the user service client.
type ClientConfig struct {
    GRPCConfig grpcclient.Config `mapstructure:",squash"`
}
```

### Add to Main Configuration

```go
// internal/config/configuration.go
type Configuration struct {
    // ... other fields ...

    // External service clients
    Clients ClientsConfig `mapstructure:"clients"`
}

// ClientsConfig holds configuration for all external service clients.
type ClientsConfig struct {
    UserService    grpcclient.Config `mapstructure:"user_service"`
    PaymentService grpcclient.Config `mapstructure:"payment_service"`
    // Add more clients as needed
}
```

### Configuration YAML

```yaml
# config/configuration.yaml
clients:
  user_service:
    target: "user-service:50051"
    insecure: true  # For development; use TLS in production
    connect_timeout: 10s
    default_call_timeout: 30s
    retry:
      enabled: true
      max_attempts: 3
      initial_backoff: 100ms
      max_backoff: 1s
      backoff_multiplier: 2.0
      retryable_status_codes: ["UNAVAILABLE", "RESOURCE_EXHAUSTED"]

  payment_service:
    target: "payment-service:50051"
    insecure: false
    tls:
      cert_file: "/etc/ssl/certs/client.crt"
      key_file: "/etc/ssl/private/client.key"
      ca_file: "/etc/ssl/certs/ca.crt"
    connect_timeout: 5s
    default_call_timeout: 60s
```

---

## 6. Fx Module Wiring

### Option A: Dedicated Client Module

```go
// internal/di/clients/module.go
package clients

import (
    "context"

    "go.uber.org/fx"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"

    "your-service/internal/clients/userservice"
    "your-service/internal/config"
)

// Module provides all external service clients.
var Module = fx.Module("clients",
    fx.Provide(NewUserServiceClient),
    platformfx.ProvideShutdownHook(NewUserServiceShutdownHook),
)

// UserServiceClientResult holds the user service client components.
type UserServiceClientResult struct {
    fx.Out
    DefaultClient *userservice.DefaultClient
    Client        userservice.Client  // Instrumented version
}

// NewUserServiceClient creates the user service client with instrumentation.
func NewUserServiceClient(cfg *config.Configuration, log logger.Logger) (UserServiceClientResult, error) {
    // Create the default (concrete) client
    defaultClient, err := userservice.NewDefaultClient(&userservice.ClientConfig{
        GRPCConfig: cfg.Clients.UserService,
    }, log)
    if err != nil {
        return UserServiceClientResult{}, err
    }

    // Wrap with instrumentation
    instrumentedClient := userservice.NewInstrumentedClient(defaultClient, log)

    log.Info(context.Background(), "user service client initialized",
        logger.String("target", cfg.Clients.UserService.Target),
    )

    return UserServiceClientResult{
        DefaultClient: defaultClient,
        Client:        instrumentedClient,
    }, nil
}

// NewUserServiceShutdownHook closes the user service client on shutdown.
func NewUserServiceShutdownHook(client *userservice.DefaultClient, log logger.Logger) platformfx.ShutdownHook {
    return platformfx.ClientHook("user-service-client", func(ctx context.Context) error {
        log.Info(ctx, "closing user service client")
        return client.Close()
    })
}
```

### Option B: Inline in Service Module

When you have fewer clients, you can wire them directly where needed:

```go
// internal/di/http/module.go (or wherever the client is needed)
package http

import (
    "go.uber.org/fx"
    
    "your-service/internal/clients/userservice"
)

var Module = fx.Module("http",
    // ... other providers ...

    // Wire user service client
    fx.Provide(func(cfg *config.Configuration, log logger.Logger) (*userservice.DefaultClient, error) {
        return userservice.NewDefaultClient(&userservice.ClientConfig{
            GRPCConfig: cfg.Clients.UserService,
        }, log)
    }),
    fx.Provide(func(c *userservice.DefaultClient, log logger.Logger) userservice.Client {
        return userservice.NewInstrumentedClient(c, log)
    }),
)
```

### Using the Client in Services

```go
// internal/services/order/service.go
package order

import (
    "context"

    "your-service/internal/clients/userservice"
    "your-service/internal/core/order"
)

type Service struct {
    repo       order.Repository
    userClient userservice.Client  // Injected via Fx
}

func NewService(repo order.Repository, userClient userservice.Client) *Service {
    return &Service{
        repo:       repo,
        userClient: userClient,
    }
}

func (s *Service) CreateOrder(ctx context.Context, userID string, items []order.Item) (*order.Order, error) {
    // Verify user exists via external service
    user, err := s.userClient.GetUser(ctx, userID)
    if err != nil {
        return nil, fmt.Errorf("failed to verify user: %w", err)
    }

    // Create order with verified user info
    o := order.New(userID, user.Email, items)
    
    if err := s.repo.Save(ctx, o); err != nil {
        return nil, err
    }

    return o, nil
}
```

---

## 7. Complete Example

Here's the complete file structure for a service with one external client:

```
internal/
├── clients/
│   └── userservice/
│       ├── client.go           # Interface + domain types
│       ├── default_client.go   # gRPC implementation
│       └── instrumented.go     # Observability wrapper
├── config/
│   └── configuration.go        # Includes ClientsConfig
├── di/
│   └── clients/
│       └── module.go           # Fx module for clients
└── services/
    └── order/
        └── service.go          # Uses userservice.Client
```

### Adding a New Client Checklist

1. **Create client directory**: `internal/clients/<service-name>/`
2. **Create interface** (`client.go`):
   - Define `Client` interface with needed methods
   - Define domain types (don't import protos)
3. **Create implementation** (`default_client.go`):
   - Use `grpcclient.NewBuilder()` with interceptors
   - Add proto-to-domain conversion functions
4. **Create instrumented wrapper** (`instrumented.go`):
   - Use `trace.Instrument()` for each method
   - Add logging with `logger.Logger`
5. **Add configuration**:
   - Add to `ClientsConfig` in `internal/config/configuration.go`
   - Add to `config/configuration.yaml`
6. **Wire in Fx module**:
   - Provide `DefaultClient`
   - Provide `Client` interface (instrumented wrapper)
   - Add shutdown hook with `platformfx.ProvideShutdownHook`

### Testing Clients

```go
// internal/clients/userservice/mock_client.go
package userservice

import (
    "context"

    "github.com/stretchr/testify/mock"
)

// MockClient is a mock implementation of Client for testing.
type MockClient struct {
    mock.Mock
}

func (m *MockClient) GetUser(ctx context.Context, id string) (*User, error) {
    args := m.Called(ctx, id)
    if args.Get(0) == nil {
        return nil, args.Error(1)
    }
    return args.Get(0).(*User), args.Error(1)
}

func (m *MockClient) GetUserByEmail(ctx context.Context, email string) (*User, error) {
    args := m.Called(ctx, email)
    if args.Get(0) == nil {
        return nil, args.Error(1)
    }
    return args.Get(0).(*User), args.Error(1)
}

func (m *MockClient) CreateUser(ctx context.Context, req *CreateUserRequest) (*User, error) {
    args := m.Called(ctx, req)
    if args.Get(0) == nil {
        return nil, args.Error(1)
    }
    return args.Get(0).(*User), args.Error(1)
}

func (m *MockClient) Close() error {
    return m.Called().Error(0)
}
```

Usage in tests:

```go
func TestOrderService_CreateOrder(t *testing.T) {
    mockUserClient := &userservice.MockClient{}
    mockUserClient.On("GetUser", mock.Anything, "user-123").Return(&userservice.User{
        ID:    "user-123",
        Email: "test@example.com",
    }, nil)

    service := order.NewService(mockRepo, mockUserClient)

    result, err := service.CreateOrder(ctx, "user-123", items)

    require.NoError(t, err)
    mockUserClient.AssertExpectations(t)
}
```
