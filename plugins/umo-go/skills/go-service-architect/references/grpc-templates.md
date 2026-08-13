# gRPC Templates

Complete templates for gRPC server and client implementation using devkit/common.

## Table of Contents

1. [Proto File Templates](#1-proto-file-templates)
2. [gRPC Server Module](#2-grpc-server-module)
3. [gRPC Handlers](#3-grpc-handlers)
4. [gRPC Error Mapping](#4-grpc-error-mapping)
5. [gRPC Client Module](#5-grpc-client-module)
6. [gRPC Client Instrumentation](#6-grpc-client-instrumentation)
7. [Streaming Patterns](#7-streaming-patterns)
8. [Testing gRPC Endpoints](#8-testing-grpc-endpoints)

---

## 1. Proto File Templates

> **Note on Proto Files**: While this template includes proto files in `api/proto/`, we are migrating to a centralized proto repository. New services should plan for proto definitions to be managed externally and imported as dependencies.

### Directory Structure

```
api/
└── proto/
    └── item/
        └── v1/
            ├── item.proto       # Main service definition
            └── types.proto      # Shared message types (optional)
```

### Service Definition

```protobuf
// api/proto/item/v1/item.proto
syntax = "proto3";

package item.v1;

option go_package = "your-service/api/proto/item/v1;itemv1";

import "google/protobuf/timestamp.proto";
import "google/protobuf/empty.proto";

// ItemService provides CRUD operations for items.
service ItemService {
  // CreateItem creates a new item.
  rpc CreateItem(CreateItemRequest) returns (CreateItemResponse);
  
  // GetItem retrieves an item by ID.
  rpc GetItem(GetItemRequest) returns (GetItemResponse);
  
  // ListItems retrieves items with optional filtering.
  rpc ListItems(ListItemsRequest) returns (ListItemsResponse);
  
  // UpdateItem updates an existing item.
  rpc UpdateItem(UpdateItemRequest) returns (UpdateItemResponse);
  
  // DeleteItem deletes an item by ID.
  rpc DeleteItem(DeleteItemRequest) returns (google.protobuf.Empty);
  
  // WatchItems streams item changes (server streaming example).
  rpc WatchItems(WatchItemsRequest) returns (stream WatchItemsResponse);
  
  // BatchCreateItems creates multiple items (client streaming example).
  rpc BatchCreateItems(stream BatchCreateItemRequest) returns (BatchCreateItemsResponse);
}

// Item represents an item in the system.
message Item {
  string id = 1;
  string name = 2;
  string description = 3;
  string price = 4;  // Decimal as string to preserve precision
  int32 quantity = 5;
  ItemStatus status = 6;
  google.protobuf.Timestamp created_at = 7;
  google.protobuf.Timestamp updated_at = 8;
}

// ItemStatus represents the status of an item.
enum ItemStatus {
  ITEM_STATUS_UNSPECIFIED = 0;
  ITEM_STATUS_ACTIVE = 1;
  ITEM_STATUS_INACTIVE = 2;
  ITEM_STATUS_DELETED = 3;
}

// CreateItemRequest is the request message for CreateItem.
message CreateItemRequest {
  string name = 1;
  string description = 2;
  string price = 3;
  int32 quantity = 4;
}

// CreateItemResponse is the response message for CreateItem.
message CreateItemResponse {
  Item item = 1;
}

// GetItemRequest is the request message for GetItem.
message GetItemRequest {
  string id = 1;
}

// GetItemResponse is the response message for GetItem.
message GetItemResponse {
  Item item = 1;
}

// ListItemsRequest is the request message for ListItems.
message ListItemsRequest {
  // Maximum number of items to return.
  int32 page_size = 1;
  
  // Token for pagination.
  string page_token = 2;
  
  // Filter by status (optional).
  ItemStatus status = 3;
}

// ListItemsResponse is the response message for ListItems.
message ListItemsResponse {
  repeated Item items = 1;
  string next_page_token = 2;
  int32 total_count = 3;
}

// UpdateItemRequest is the request message for UpdateItem.
message UpdateItemRequest {
  string id = 1;
  string name = 2;
  string description = 3;
  string price = 4;
  int32 quantity = 5;
}

// UpdateItemResponse is the response message for UpdateItem.
message UpdateItemResponse {
  Item item = 1;
}

// DeleteItemRequest is the request message for DeleteItem.
message DeleteItemRequest {
  string id = 1;
}

// WatchItemsRequest is the request for streaming item updates.
message WatchItemsRequest {
  // Filter by status (optional).
  ItemStatus status = 1;
}

// WatchItemsResponse is a streaming response with item changes.
message WatchItemsResponse {
  Item item = 1;
  ChangeType change_type = 2;
}

// ChangeType indicates the type of change.
enum ChangeType {
  CHANGE_TYPE_UNSPECIFIED = 0;
  CHANGE_TYPE_CREATED = 1;
  CHANGE_TYPE_UPDATED = 2;
  CHANGE_TYPE_DELETED = 3;
}

// BatchCreateItemRequest is a single item in a batch create stream.
message BatchCreateItemRequest {
  string name = 1;
  string description = 2;
  string price = 3;
  int32 quantity = 4;
}

// BatchCreateItemsResponse is the response for batch creation.
message BatchCreateItemsResponse {
  repeated Item items = 1;
  int32 success_count = 2;
  int32 failed_count = 3;
}
```

### Generate Go Code

Add to `Makefile`:

```makefile
.PHONY: proto
proto:
	@echo "Generating protobuf code..."
	protoc --go_out=. --go_opt=paths=source_relative \
		--go-grpc_out=. --go-grpc_opt=paths=source_relative \
		api/proto/item/v1/*.proto
```

Or using `buf`:

```yaml
# buf.gen.yaml
version: v1
plugins:
  - plugin: go
    out: .
    opt: paths=source_relative
  - plugin: go-grpc
    out: .
    opt: paths=source_relative
```

```bash
buf generate
```

---

## 2. gRPC Server Module

Complete gRPC DI module with all devkit/common interceptors.

> **Important**: When running both HTTP and gRPC servers, the domain services (e.g., `ItemService`) should be provided by ONE module only (typically the HTTP module or a shared service module). The gRPC module should NOT provide its own service instance to avoid duplicate provider errors in Fx.

```go
// internal/di/grpc/module.go
package grpc

import (
    "context"
    "net"

    "go.uber.org/fx"
    "google.golang.org/grpc"
    "google.golang.org/grpc/health"
    grpc_health_v1 "google.golang.org/grpc/health/grpc_health_v1"
    "google.golang.org/grpc/reflection"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/grpcerr"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/grpcserver"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    tracegrpc "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace/grpc"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"

    pb "your-service/api/proto/item/v1"
    "your-service/internal/config"
    grpchandlers "your-service/internal/handlers/grpc"
)

// Module provides the gRPC server as an Fx module.
// Note: This module depends on the item service being provided by another module
// (typically the HTTP module or a shared service module).
var Module = fx.Module("grpc",
    // Provide gRPC handlers (uses existing item service from DI container)
    fx.Provide(grpchandlers.NewHandlers),

    // Provide gRPC server with interceptors
    fx.Provide(NewGRPCServer),

    // Register gRPC services with server
    fx.Invoke(RegisterGRPCServices),

    // Register lifecycle hooks for startup
    fx.Invoke(RegisterGRPCLifecycle),

    // Register shutdown hook with proper priority
    platformfx.ProvideShutdownHook(NewGRPCShutdownHook),
)

// GRPCServerResult holds the gRPC server and related components.
type GRPCServerResult struct {
    fx.Out
    Server       *grpc.Server
    HealthServer *health.Server
}

// NewGRPCServer creates a new gRPC server with full observability interceptors.
func NewGRPCServer(cfg *config.Configuration, log logger.Logger) (GRPCServerResult, error) {
    // Create skipper for health checks and reflection
    skipper := grpcserver.CombineSkippers(
        grpcserver.SkipHealthChecks(),
        grpcserver.SkipReflection(),
    )

    // Build unary interceptor chain (order matters - outermost first)
    unaryInterceptors := []grpc.UnaryServerInterceptor{
        // 1. Tracing - creates server span, extracts trace context from metadata
        //    This MUST be first to capture the full request lifecycle
        tracegrpc.UnaryServerInterceptor(
            tracegrpc.WithServerSkipper(tracegrpc.SkipHealthChecks()),
        ),

        // 2. Request ID - extracts from X-Request-Id metadata or generates new UUID
        //    Stored in context for downstream use
        grpcserver.RequestIDUnaryInterceptor(),

        // 3. Logging - logs requests with method, duration, status code
        //    Auto-includes trace_id, span_id from context
        grpcserver.LoggingUnaryInterceptor(
            grpcserver.WithLoggingLogger(log),
            grpcserver.WithLoggingSkipper(skipper),
        ),

        // 4. Metrics - Prometheus metrics (request count, duration histogram)
        //    Labels: grpc_method, grpc_code
        grpcserver.MetricsUnaryInterceptor(
            grpcserver.WithMetricsSkipper(skipper),
        ),

        // 5. Recovery - recovers from panics and converts to Internal error
        //    Logs panic with stack trace
        grpcserver.RecoveryUnaryInterceptor(
            grpcserver.WithRecoveryLogger(log),
            grpcserver.WithRecoveryPrintStack(true),
        ),

        // 6. Error Mapping - converts domain errors to gRPC status codes
        //    Uses grpcerr.Error interface for custom mappings
        grpcerr.MappingUnaryInterceptor(),

        // 7. Validation - validates requests implementing Validator interface
        //    Returns InvalidArgument for validation failures
        grpcserver.ValidationUnaryInterceptor(),
    }

    // Build stream interceptor chain (same order as unary)
    streamInterceptors := []grpc.StreamServerInterceptor{
        tracegrpc.StreamServerInterceptor(
            tracegrpc.WithServerSkipper(tracegrpc.SkipHealthChecks()),
        ),
        grpcserver.RequestIDStreamInterceptor(),
        grpcserver.LoggingStreamInterceptor(
            grpcserver.WithLoggingLogger(log),
            grpcserver.WithLoggingSkipper(skipper),
        ),
        grpcserver.MetricsStreamInterceptor(
            grpcserver.WithMetricsSkipper(skipper),
        ),
        grpcserver.RecoveryStreamInterceptor(
            grpcserver.WithRecoveryLogger(log),
        ),
        grpcerr.MappingStreamInterceptor(),
        grpcserver.ValidationStreamInterceptor(),
    }

    // Build gRPC server using devkit/common builder
    builder := grpcserver.NewBuilder(cfg.GRPC).
        WithHealthCheck(false).  // We register health manually
        WithReflection(false).   // We enable reflection based on config
        WithUnaryInterceptors(unaryInterceptors...).
        WithStreamInterceptors(streamInterceptors...)

    server, err := builder.Build()
    if err != nil {
        return GRPCServerResult{}, err
    }

    return GRPCServerResult{
        Server:       server,
        HealthServer: health.NewServer(),
    }, nil
}

// RegisterGRPCServices registers all gRPC services with the server.
func RegisterGRPCServices(
    server *grpc.Server,
    healthServer *health.Server,
    handlers *grpchandlers.Handlers,
    cfg *config.Configuration,
) {
    // Register domain services
    pb.RegisterItemServiceServer(server, handlers)

    // Register health service
    grpc_health_v1.RegisterHealthServer(server, healthServer)

    // Set initial health status
    healthServer.SetServingStatus("", grpc_health_v1.HealthCheckResponse_SERVING)
    healthServer.SetServingStatus("item.v1.ItemService", grpc_health_v1.HealthCheckResponse_SERVING)

    // Enable reflection for development/debugging
    if cfg.GRPC.Reflection {
        reflection.Register(server)
    }
}

// RegisterGRPCLifecycle registers lifecycle hooks for the gRPC server.
func RegisterGRPCLifecycle(
    lc fx.Lifecycle,
    server *grpc.Server,
    cfg *config.Configuration,
    log logger.Logger,
) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            log.Info(ctx, "Starting gRPC server",
                logger.String("addr", cfg.GRPC.Addr),
                logger.Bool("reflection", cfg.GRPC.Reflection),
                logger.Bool("health_check", cfg.GRPC.HealthCheck),
            )

            lis, err := net.Listen("tcp", cfg.GRPC.Addr)
            if err != nil {
                return err
            }

            go func() {
                if err := server.Serve(lis); err != nil {
                    log.Error(ctx, "gRPC server stopped", logger.Err(err))
                }
            }()

            return nil
        },
    })
}

// NewGRPCShutdownHook creates a shutdown hook for the gRPC server.
func NewGRPCShutdownHook(
    server *grpc.Server,
    healthServer *health.Server,
    log logger.Logger,
) platformfx.ShutdownHook {
    return platformfx.ServerHook("grpc-server", func(ctx context.Context) error {
        log.Info(ctx, "Shutting down gRPC server")

        // Set health status to NOT_SERVING before shutdown
        healthServer.SetServingStatus("", grpc_health_v1.HealthCheckResponse_NOT_SERVING)
        healthServer.SetServingStatus("item.v1.ItemService", grpc_health_v1.HealthCheckResponse_NOT_SERVING)

        // Graceful shutdown with timeout
        stopped := make(chan struct{})
        go func() {
            server.GracefulStop()
            close(stopped)
        }()

        select {
        case <-stopped:
            log.Info(ctx, "gRPC server shutdown complete")
            return nil
        case <-ctx.Done():
            log.Warn(ctx, "gRPC server graceful shutdown timeout, forcing stop")
            server.Stop()
            return ctx.Err()
        }
    })
}
```

---

## 3. gRPC Handlers

Complete handler implementation with proper error mapping and conversion.

```go
// internal/handlers/grpc/handlers.go
package grpc

import (
    "context"

    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"
    "google.golang.org/protobuf/types/known/emptypb"
    "google.golang.org/protobuf/types/known/timestamppb"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"

    pb "your-service/api/proto/item/v1"
    "your-service/internal/core/item"
    itemservice "your-service/internal/services/item"
)

// Handlers implements the gRPC ItemService.
type Handlers struct {
    pb.UnimplementedItemServiceServer
    service *itemservice.Service
    log     logger.Logger
}

// NewHandlers creates a new gRPC handlers instance.
func NewHandlers(service *itemservice.Service, log logger.Logger) *Handlers {
    return &Handlers{
        service: service,
        log:     log.Named("grpc.handlers"),
    }
}

// CreateItem creates a new item.
func (h *Handlers) CreateItem(ctx context.Context, req *pb.CreateItemRequest) (*pb.CreateItemResponse, error) {
    // Parse price from string
    price, err := parsePrice(req.Price)
    if err != nil {
        return nil, status.Errorf(codes.InvalidArgument, "invalid price: %v", err)
    }

    // Call service
    result, err := h.service.Create(ctx, req.Name, req.Description, price, int(req.Quantity))
    if err != nil {
        return nil, mapError(err)
    }

    return &pb.CreateItemResponse{
        Item: itemToProto(result),
    }, nil
}

// GetItem retrieves an item by ID.
func (h *Handlers) GetItem(ctx context.Context, req *pb.GetItemRequest) (*pb.GetItemResponse, error) {
    result, err := h.service.GetByID(ctx, req.Id)
    if err != nil {
        return nil, mapError(err)
    }

    return &pb.GetItemResponse{
        Item: itemToProto(result),
    }, nil
}

// ListItems retrieves items with pagination.
func (h *Handlers) ListItems(ctx context.Context, req *pb.ListItemsRequest) (*pb.ListItemsResponse, error) {
    // Parse pagination
    pageSize := int(req.PageSize)
    if pageSize <= 0 {
        pageSize = 20 // Default page size
    }
    if pageSize > 100 {
        pageSize = 100 // Max page size
    }

    offset := 0
    if req.PageToken != "" {
        // Decode page token (simple offset-based pagination)
        // In production, use a proper token encoding
        offset = decodePageToken(req.PageToken)
    }

    // Call service
    results, total, err := h.service.List(ctx, pageSize, offset)
    if err != nil {
        return nil, mapError(err)
    }

    // Build response
    items := make([]*pb.Item, len(results))
    for i, r := range results {
        items[i] = itemToProto(r)
    }

    var nextPageToken string
    if offset+len(results) < total {
        nextPageToken = encodePageToken(offset + len(results))
    }

    return &pb.ListItemsResponse{
        Items:         items,
        NextPageToken: nextPageToken,
        TotalCount:    int32(total),
    }, nil
}

// UpdateItem updates an existing item.
func (h *Handlers) UpdateItem(ctx context.Context, req *pb.UpdateItemRequest) (*pb.UpdateItemResponse, error) {
    // Parse price
    price, err := parsePrice(req.Price)
    if err != nil {
        return nil, status.Errorf(codes.InvalidArgument, "invalid price: %v", err)
    }

    result, err := h.service.Update(ctx, req.Id, req.Name, req.Description, price, int(req.Quantity))
    if err != nil {
        return nil, mapError(err)
    }

    return &pb.UpdateItemResponse{
        Item: itemToProto(result),
    }, nil
}

// DeleteItem deletes an item by ID.
func (h *Handlers) DeleteItem(ctx context.Context, req *pb.DeleteItemRequest) (*emptypb.Empty, error) {
    err := h.service.Delete(ctx, req.Id)
    if err != nil {
        return nil, mapError(err)
    }

    return &emptypb.Empty{}, nil
}

// ==================== Helper Functions ====================

import (
    "encoding/base64"
    "strconv"

    "github.com/shopspring/decimal"
)

// parsePrice parses a price string to decimal.
func parsePrice(s string) (decimal.Decimal, error) {
    return decimal.NewFromString(s)
}

// encodePageToken encodes an offset into a page token.
func encodePageToken(offset int) string {
    return base64.StdEncoding.EncodeToString([]byte(strconv.Itoa(offset)))
}

// decodePageToken decodes a page token into an offset.
func decodePageToken(token string) int {
    if token == "" {
        return 0
    }
    data, err := base64.StdEncoding.DecodeString(token)
    if err != nil {
        return 0
    }
    offset, err := strconv.Atoi(string(data))
    if err != nil {
        return 0
    }
    return offset
}

// ==================== Conversion Functions ====================

// itemToProto converts a domain item to a protobuf item.
func itemToProto(i *item.Item) *pb.Item {
    return &pb.Item{
        Id:          i.ID,
        Name:        i.Name,
        Description: i.Description,
        Price:       i.Price.String(),
        Quantity:    int32(i.Quantity),
        Status:      statusToProto(i.Status),
        CreatedAt:   timestamppb.New(i.CreatedAt),
        UpdatedAt:   timestamppb.New(i.UpdatedAt),
    }
}

// statusToProto converts domain status to proto enum.
func statusToProto(s item.Status) pb.ItemStatus {
    switch s {
    case item.StatusActive:
        return pb.ItemStatus_ITEM_STATUS_ACTIVE
    case item.StatusInactive:
        return pb.ItemStatus_ITEM_STATUS_INACTIVE
    case item.StatusDeleted:
        return pb.ItemStatus_ITEM_STATUS_DELETED
    default:
        return pb.ItemStatus_ITEM_STATUS_UNSPECIFIED
    }
}

// protoToStatus converts proto enum to domain status.
func protoToStatus(s pb.ItemStatus) item.Status {
    switch s {
    case pb.ItemStatus_ITEM_STATUS_ACTIVE:
        return item.StatusActive
    case pb.ItemStatus_ITEM_STATUS_INACTIVE:
        return item.StatusInactive
    case pb.ItemStatus_ITEM_STATUS_DELETED:
        return item.StatusDeleted
    default:
        return item.StatusActive
    }
}
```

---

## 4. gRPC Error Mapping

Error mapping utilities for converting domain errors to gRPC status codes.

```go
// internal/handlers/grpc/errors.go
package grpc

import (
    "errors"

    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"

    "your-service/internal/core/item"
)

// mapError converts domain errors to gRPC status errors.
// The grpcerr.MappingUnaryInterceptor handles grpcerr.Error types automatically,
// but for domain errors, we need explicit mapping.
func mapError(err error) error {
    if err == nil {
        return nil
    }

    // Check for specific domain errors
    switch {
    case errors.Is(err, item.ErrNotFound):
        return status.Error(codes.NotFound, err.Error())

    case errors.Is(err, item.ErrAlreadyExists):
        return status.Error(codes.AlreadyExists, err.Error())

    case errors.Is(err, item.ErrInvalidID),
        errors.Is(err, item.ErrInvalidName),
        errors.Is(err, item.ErrInvalidPrice),
        errors.Is(err, item.ErrInvalidQuantity),
        errors.Is(err, item.ErrInvalidStatus):
        return status.Error(codes.InvalidArgument, err.Error())

    case errors.Is(err, item.ErrInactiveItem):
        return status.Error(codes.FailedPrecondition, err.Error())

    default:
        // Don't expose internal errors to clients
        return status.Error(codes.Internal, "internal error")
    }
}

// mapErrorWithDetails converts domain errors with additional details.
func mapErrorWithDetails(err error, details ...interface{}) error {
    st := status.New(codes.Internal, "internal error")

    switch {
    case errors.Is(err, item.ErrNotFound):
        st = status.New(codes.NotFound, err.Error())
    case errors.Is(err, item.ErrAlreadyExists):
        st = status.New(codes.AlreadyExists, err.Error())
    }

    // Add details if needed (requires proto message details)
    // st, _ = st.WithDetails(details...)

    return st.Err()
}
```

### Using grpcerr.Error for Automatic Mapping

For automatic error mapping via the interceptor, implement `grpcerr.Error`:

```go
// internal/core/item/errors.go
package item

import (
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/grpcerr"
)

// DomainError implements grpcerr.Error for automatic mapping.
type DomainError struct {
    code    grpcerr.Code
    message string
}

func (e *DomainError) Error() string {
    return e.message
}

func (e *DomainError) GRPCStatus() *status.Status {
    return status.New(e.code.ToGRPCCode(), e.message)
}

// Predefined domain errors with gRPC mapping
var (
    ErrNotFound = &DomainError{
        code:    grpcerr.CodeNotFound,
        message: "item not found",
    }
    ErrAlreadyExists = &DomainError{
        code:    grpcerr.CodeAlreadyExists,
        message: "item already exists",
    }
    ErrInvalidID = &DomainError{
        code:    grpcerr.CodeInvalidArgument,
        message: "invalid item ID",
    }
)
```

---

## 5. gRPC Client Module

For calling other gRPC services with proper instrumentation.

```go
// internal/di/grpcclient/module.go
package grpcclient

import (
    "context"

    "go.uber.org/fx"
    "google.golang.org/grpc"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/grpcclient"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    tracegrpc "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace/grpc"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"

    userpb "external-service/api/proto/user/v1"
    "your-service/internal/config"
)

// Module provides gRPC client connections.
var Module = fx.Module("grpc-client",
    fx.Provide(NewUserServiceClient),
    platformfx.ProvideShutdownHook(NewUserServiceClientShutdownHook),
)

// UserServiceClientResult holds the client connection.
type UserServiceClientResult struct {
    fx.Out
    Conn   *grpc.ClientConn `name:"user-service-conn"`
    Client userpb.UserServiceClient
}

// NewUserServiceClient creates a gRPC client for the user service.
func NewUserServiceClient(cfg *config.Configuration, log logger.Logger) (UserServiceClientResult, error) {
    ctx := context.Background()

    // Build client interceptors (order matters - outermost first)
    unaryInterceptors := []grpc.UnaryClientInterceptor{
        // 1. Tracing - propagates trace context to downstream service
        tracegrpc.UnaryClientInterceptor(),
        // 2. Request ID propagation - passes X-Request-Id to downstream
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

    // Build gRPC client connection using devkit/common builder
    // Retry is configured through the config, not as an interceptor
    builder := grpcclient.NewBuilder(cfg.UserService).
        WithUnaryInterceptors(unaryInterceptors...).
        WithStreamInterceptors(streamInterceptors...)

    // TLS is controlled by config.Insecure flag
    // If Insecure is false, the builder uses system CA certs or custom TLS config

    conn, err := builder.Build(ctx)
    if err != nil {
        return UserServiceClientResult{}, err
    }

    log.Info(ctx, "Connected to user service",
        logger.String("target", cfg.UserService.Target),
    )

    return UserServiceClientResult{
        Conn:   conn,
        Client: userpb.NewUserServiceClient(conn),
    }, nil
}

// NewUserServiceClientShutdownHook closes the gRPC connection on shutdown.
func NewUserServiceClientShutdownHook(
    conn *grpc.ClientConn `name:"user-service-conn"`,
    log logger.Logger,
) platformfx.ShutdownHook {
    return platformfx.ClientHook("user-service-client", func(ctx context.Context) error {
        log.Info(ctx, "Closing user service gRPC connection")
        return conn.Close()
    })
}
```

### Client Configuration

Add to your configuration struct:

```go
// internal/config/configuration.go
type Configuration struct {
    // ... other fields ...
    
    // External service clients
    UserService grpcclient.Config `mapstructure:"user_service"`
}
```

```yaml
# config/configuration.yaml
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
```

---

## 6. gRPC Client Instrumentation

Wrapper for external gRPC clients with automatic tracing.

```go
// internal/clients/userservice/client.go
package userservice

import (
    "context"
    "time"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace"

    pb "external-service/api/proto/user/v1"
)

// Client wraps the user service gRPC client with instrumentation.
type Client struct {
    client pb.UserServiceClient
    log    logger.Logger
    tracer trace.Tracer
}

// NewClient creates a new instrumented user service client.
func NewClient(client pb.UserServiceClient, log logger.Logger, provider trace.Provider) *Client {
    return &Client{
        client: client,
        log:    log.Named("clients.userservice"),
        tracer: provider.Tracer("userservice.client"),
    }
}

// GetUser retrieves a user by ID with automatic tracing.
func (c *Client) GetUser(ctx context.Context, userID string) (*User, error) {
    start := time.Now()

    // Create span for this client call
    ctx, span := c.tracer.Start(ctx, "userservice.GetUser",
        trace.WithSpanKind(trace.SpanKindClient),
        trace.WithAttributes(
            trace.String("user.id", userID),
            trace.String("rpc.service", "user.v1.UserService"),
            trace.String("rpc.method", "GetUser"),
        ),
    )
    defer span.End()

    c.log.Debug(ctx, "calling user service",
        logger.String("method", "GetUser"),
        logger.String("user_id", userID),
    )

    // Make the gRPC call
    resp, err := c.client.GetUser(ctx, &pb.GetUserRequest{Id: userID})

    duration := time.Since(start)
    span.SetAttributes(trace.Float64("duration_seconds", duration.Seconds()))

    if err != nil {
        span.RecordError(err)
        span.SetStatus(trace.StatusError, "failed to get user")
        c.log.Error(ctx, "user service call failed",
            logger.String("method", "GetUser"),
            logger.Err(err),
            logger.Duration("duration", duration),
        )
        return nil, err
    }

    span.SetStatus(trace.StatusOK, "user retrieved")
    c.log.Debug(ctx, "user service call succeeded",
        logger.String("method", "GetUser"),
        logger.Duration("duration", duration),
    )

    return protoToUser(resp.User), nil
}

// User represents a user from the external service.
type User struct {
    ID    string
    Email string
    Name  string
}

func protoToUser(u *pb.User) *User {
    return &User{
        ID:    u.Id,
        Email: u.Email,
        Name:  u.Name,
    }
}
```

---

## 7. Streaming Patterns

### Server Streaming

```go
// internal/handlers/grpc/handlers.go

// WatchItems implements server-side streaming for item changes.
func (h *Handlers) WatchItems(req *pb.WatchItemsRequest, stream pb.ItemService_WatchItemsServer) error {
    ctx := stream.Context()

    h.log.Info(ctx, "starting item watch stream")

    // Create a channel to receive item changes
    changes := make(chan *itemChange, 100)

    // Subscribe to item changes (implementation depends on your event system)
    unsubscribe := h.service.SubscribeToChanges(ctx, changes)
    defer unsubscribe()

    for {
        select {
        case <-ctx.Done():
            h.log.Info(ctx, "item watch stream ended", logger.Err(ctx.Err()))
            return ctx.Err()

        case change, ok := <-changes:
            if !ok {
                return nil
            }

            // Send the change to the client
            if err := stream.Send(&pb.WatchItemsResponse{
                Item:       itemToProto(change.Item),
                ChangeType: changeTypeToProto(change.Type),
            }); err != nil {
                h.log.Error(ctx, "failed to send item change", logger.Err(err))
                return err
            }
        }
    }
}

type itemChange struct {
    Item *item.Item
    Type string // "created", "updated", "deleted"
}

func changeTypeToProto(t string) pb.ChangeType {
    switch t {
    case "created":
        return pb.ChangeType_CHANGE_TYPE_CREATED
    case "updated":
        return pb.ChangeType_CHANGE_TYPE_UPDATED
    case "deleted":
        return pb.ChangeType_CHANGE_TYPE_DELETED
    default:
        return pb.ChangeType_CHANGE_TYPE_UNSPECIFIED
    }
}
```

### Client Streaming

```go
// BatchCreateItems implements client-side streaming for batch item creation.
func (h *Handlers) BatchCreateItems(stream pb.ItemService_BatchCreateItemsServer) error {
    ctx := stream.Context()

    h.log.Info(ctx, "starting batch create stream")

    var items []*item.Item
    var failedCount int

    for {
        req, err := stream.Recv()
        if err == io.EOF {
            // Client finished sending
            break
        }
        if err != nil {
            h.log.Error(ctx, "failed to receive item", logger.Err(err))
            return err
        }

        // Parse and create item
        price, err := parsePrice(req.Price)
        if err != nil {
            failedCount++
            h.log.Warn(ctx, "invalid item price, skipping",
                logger.String("name", req.Name),
                logger.Err(err),
            )
            continue
        }

        created, err := h.service.Create(ctx, req.Name, req.Description, price, int(req.Quantity))
        if err != nil {
            failedCount++
            h.log.Warn(ctx, "failed to create item, skipping",
                logger.String("name", req.Name),
                logger.Err(err),
            )
            continue
        }

        items = append(items, created)
    }

    // Send response with all created items
    protoItems := make([]*pb.Item, len(items))
    for i, it := range items {
        protoItems[i] = itemToProto(it)
    }

    h.log.Info(ctx, "batch create completed",
        logger.Int("success_count", len(items)),
        logger.Int("failed_count", failedCount),
    )

    return stream.SendAndClose(&pb.BatchCreateItemsResponse{
        Items:        protoItems,
        SuccessCount: int32(len(items)),
        FailedCount:  int32(failedCount),
    })
}
```

---

## 8. Testing gRPC Endpoints

### Using grpcurl

```bash
# List services (requires reflection enabled)
grpcurl -plaintext localhost:50051 list

# List methods for a service
grpcurl -plaintext localhost:50051 list item.v1.ItemService

# Health check
grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check

# Create item
grpcurl -plaintext -d '{
  "name": "Test Item",
  "description": "A test item",
  "price": "19.99",
  "quantity": 10
}' localhost:50051 item.v1.ItemService/CreateItem

# Get item
grpcurl -plaintext -d '{"id": "item-123"}' \
  localhost:50051 item.v1.ItemService/GetItem

# List items
grpcurl -plaintext -d '{"page_size": 10}' \
  localhost:50051 item.v1.ItemService/ListItems

# Update item
grpcurl -plaintext -d '{
  "id": "item-123",
  "name": "Updated Item",
  "description": "Updated description",
  "price": "29.99",
  "quantity": 5
}' localhost:50051 item.v1.ItemService/UpdateItem

# Delete item
grpcurl -plaintext -d '{"id": "item-123"}' \
  localhost:50051 item.v1.ItemService/DeleteItem

# With request headers (for tracing)
grpcurl -plaintext \
  -H "x-request-id: test-123" \
  -H "x-tenant-id: tenant-abc" \
  -d '{"id": "item-123"}' \
  localhost:50051 item.v1.ItemService/GetItem
```

### Unit Testing Handlers

```go
// internal/handlers/grpc/handlers_test.go
package grpc

import (
    "context"
    "testing"

    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/mock"
    "github.com/stretchr/testify/require"

    pb "your-service/api/proto/item/v1"
    "your-service/internal/core/item"
)

// MockItemService is a mock implementation of the item service.
type MockItemService struct {
    mock.Mock
}

func (m *MockItemService) GetByID(ctx context.Context, id string) (*item.Item, error) {
    args := m.Called(ctx, id)
    if args.Get(0) == nil {
        return nil, args.Error(1)
    }
    return args.Get(0).(*item.Item), args.Error(1)
}

// ... other mock methods

func TestHandlers_GetItem(t *testing.T) {
    tests := []struct {
        name    string
        req     *pb.GetItemRequest
        setup   func(*MockItemService)
        want    *pb.GetItemResponse
        wantErr bool
    }{
        {
            name: "success",
            req:  &pb.GetItemRequest{Id: "item-123"},
            setup: func(m *MockItemService) {
                m.On("GetByID", mock.Anything, "item-123").Return(&item.Item{
                    ID:   "item-123",
                    Name: "Test Item",
                }, nil)
            },
            want: &pb.GetItemResponse{
                Item: &pb.Item{
                    Id:   "item-123",
                    Name: "Test Item",
                },
            },
        },
        {
            name: "not found",
            req:  &pb.GetItemRequest{Id: "not-found"},
            setup: func(m *MockItemService) {
                m.On("GetByID", mock.Anything, "not-found").Return(nil, item.ErrNotFound)
            },
            wantErr: true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            mockService := &MockItemService{}
            tt.setup(mockService)

            h := &Handlers{service: mockService}

            got, err := h.GetItem(context.Background(), tt.req)

            if tt.wantErr {
                require.Error(t, err)
                return
            }

            require.NoError(t, err)
            assert.Equal(t, tt.want.Item.Id, got.Item.Id)
            assert.Equal(t, tt.want.Item.Name, got.Item.Name)
        })
    }
}
```

### Integration Testing with bufconn

```go
// internal/handlers/grpc/handlers_integration_test.go
package grpc_test

import (
    "context"
    "net"
    "testing"

    "github.com/stretchr/testify/require"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
    "google.golang.org/grpc/test/bufconn"

    pb "your-service/api/proto/item/v1"
)

const bufSize = 1024 * 1024

var lis *bufconn.Listener

func init() {
    lis = bufconn.Listen(bufSize)

    // Set up test server with handlers
    s := grpc.NewServer()
    // Register your handlers here
    // pb.RegisterItemServiceServer(s, handlers)

    go func() {
        if err := s.Serve(lis); err != nil {
            panic(err)
        }
    }()
}

func bufDialer(context.Context, string) (net.Conn, error) {
    return lis.Dial()
}

func TestItemService_Integration(t *testing.T) {
    ctx := context.Background()

    conn, err := grpc.NewClient("passthrough:///bufnet",
        grpc.WithContextDialer(bufDialer),
        grpc.WithTransportCredentials(insecure.NewCredentials()),
    )
    require.NoError(t, err)
    defer conn.Close()

    client := pb.NewItemServiceClient(conn)

    // Test CreateItem
    createResp, err := client.CreateItem(ctx, &pb.CreateItemRequest{
        Name:        "Test Item",
        Description: "Test Description",
        Price:       "19.99",
        Quantity:    10,
    })
    require.NoError(t, err)
    require.NotEmpty(t, createResp.Item.Id)

    // Test GetItem
    getResp, err := client.GetItem(ctx, &pb.GetItemRequest{
        Id: createResp.Item.Id,
    })
    require.NoError(t, err)
    require.Equal(t, "Test Item", getResp.Item.Name)
}
```
