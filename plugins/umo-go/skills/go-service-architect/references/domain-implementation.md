# Domain Implementation Guide

How to implement a new domain/feature within an existing service.

## Overview

Adding a new domain (e.g., "orders" to an existing "users" service) follows these steps:

1. Domain Layer - Entities, value objects, errors
2. Service Layer - Interface, implementation, instrumentation
3. Repository Layer - Schema, queries, mapping
4. Handler Layer - gRPC methods, proto mapping
5. DI Wiring - Connect everything

## Step-by-Step Implementation

### Step 1: Create Domain Entities

Create directory and files:

```
internal/core/order/
├── order.go       # Main entity
├── item.go        # Order item entity
├── status.go      # Status value object
└── errors.go      # Domain errors
```

#### Main Entity

```go
// internal/core/order/order.go
package order

import "time"

// Order represents an order in the system.
type Order struct {
    ID         string
    UserID     string
    Items      []Item
    TotalPrice int64  // In cents
    Status     Status
    CreatedAt  time.Time
    UpdatedAt  time.Time
}

// IsDraft returns true if the order is in draft status.
func (o *Order) IsDraft() bool {
    return o.Status == StatusDraft
}

// IsFinal returns true if the order is in a final state.
func (o *Order) IsFinal() bool {
    return o.Status == StatusCompleted || o.Status == StatusCancelled
}

// CanBeModified returns true if items can be added to the order.
func (o *Order) CanBeModified() bool {
    return o.Status == StatusDraft
}

// CanBeCancelled returns true if the order can be cancelled.
func (o *Order) CanBeCancelled() bool {
    return !o.IsFinal()
}

// HasItems returns true if the order has at least one item.
func (o *Order) HasItems() bool {
    return len(o.Items) > 0
}

// CalculateTotal computes the total price from items.
func (o *Order) CalculateTotal() int64 {
    var total int64
    for _, item := range o.Items {
        total += item.Price * int64(item.Quantity)
    }
    return total
}
```

#### Value Objects

```go
// internal/core/order/item.go
package order

// Item represents an item in an order.
type Item struct {
    ProductID string
    Name      string
    Price     int64 // In cents
    Quantity  int
}

// internal/core/order/status.go
package order

type Status string

const (
    StatusDraft     Status = "DRAFT"
    StatusPending   Status = "PENDING"
    StatusProcessing Status = "PROCESSING"
    StatusCompleted Status = "COMPLETED"
    StatusCancelled Status = "CANCELLED"
)

func (s Status) IsValid() bool {
    switch s {
    case StatusDraft, StatusPending, StatusProcessing, StatusCompleted, StatusCancelled:
        return true
    default:
        return false
    }
}
```

#### Domain Errors

```go
// internal/core/order/errors.go
package order

import "errors"

var (
    ErrNotFound          = errors.New("order not found")
    ErrCannotModifyOrder = errors.New("cannot modify order in current state")
    ErrInvalidTransition = errors.New("invalid status transition")
    ErrEmptyOrder        = errors.New("order has no items")
    ErrInvalidQuantity   = errors.New("quantity must be positive")
)
```

### Step 2: Create Service Layer

Create service directory:

```
internal/services/orders/
├── service.go       # Interface DEFINITION (not alias)
├── default.go       # Implementation
├── default_test.go  # Unit tests
└── instrumented.go  # Observability wrapper
```

#### Service Interface

> **Pattern**: Define the interface DIRECTLY in `service.go`. Do NOT use type aliases like `type Service = domain.UseCase`. This ensures the service layer owns its contract.

```go
// internal/services/orders/service.go
package orders

import (
    "context"
    "your-service/internal/core/order"
)

// Service defines the order service operations.
// NOTE: Define the interface here directly, not as an alias to a domain type.
type Service interface {
    // CreateOrder creates a new draft order.
    CreateOrder(ctx context.Context, userID string) (*order.Order, error)
    
    // GetOrder retrieves an order by ID.
    GetOrder(ctx context.Context, id string) (*order.Order, error)
    
    // ListUserOrders retrieves all orders for a user.
    ListUserOrders(ctx context.Context, userID string) ([]*order.Order, error)
    
    // AddItem adds an item to an order.
    AddItem(ctx context.Context, orderID string, item order.Item) (*order.Order, error)
    
    // SubmitOrder submits an order for processing.
    SubmitOrder(ctx context.Context, id string) (*order.Order, error)
    
    // CancelOrder cancels an order.
    CancelOrder(ctx context.Context, id string) error
}
```

#### Service Implementation

```go
// internal/services/orders/default.go
package orders

import (
    "context"
    "fmt"
    "time"
    
    "github.com/google/uuid"
    
    "your-service/internal/core/order"
)

// Repo defines repository operations needed by this service.
type Repo interface {
    SaveOrder(ctx context.Context, o *order.Order) error
    GetOrder(ctx context.Context, id string) (*order.Order, error)
    ListUserOrders(ctx context.Context, userID string) ([]*order.Order, error)
    DeleteOrder(ctx context.Context, id string) error
}

// DefaultService implements the Service interface.
type DefaultService struct {
    repo Repo
}

// NewDefaultService creates a new DefaultService.
func NewDefaultService(repo Repo) *DefaultService {
    return &DefaultService{repo: repo}
}

// CreateOrder creates a new draft order.
func (s *DefaultService) CreateOrder(ctx context.Context, userID string) (*order.Order, error) {
    o := &order.Order{
        ID:        uuid.New().String(),
        UserID:    userID,
        Items:     []order.Item{},
        Status:    order.StatusDraft,
        CreatedAt: time.Now().UTC(),
        UpdatedAt: time.Now().UTC(),
    }
    
    if err := s.repo.SaveOrder(ctx, o); err != nil {
        return nil, fmt.Errorf("failed to save order: %w", err)
    }
    
    return o, nil
}

// GetOrder retrieves an order by ID.
func (s *DefaultService) GetOrder(ctx context.Context, id string) (*order.Order, error) {
    o, err := s.repo.GetOrder(ctx, id)
    if err != nil {
        return nil, fmt.Errorf("failed to get order: %w", err)
    }
    if o == nil {
        return nil, order.ErrNotFound
    }
    return o, nil
}

// ListUserOrders retrieves all orders for a user.
func (s *DefaultService) ListUserOrders(ctx context.Context, userID string) ([]*order.Order, error) {
    return s.repo.ListUserOrders(ctx, userID)
}

// AddItem adds an item to an order.
func (s *DefaultService) AddItem(ctx context.Context, orderID string, item order.Item) (*order.Order, error) {
    o, err := s.repo.GetOrder(ctx, orderID)
    if err != nil {
        return nil, fmt.Errorf("failed to get order: %w", err)
    }
    if o == nil {
        return nil, order.ErrNotFound
    }
    
    // Business logic in service layer
    if !o.CanBeModified() {
        return nil, order.ErrCannotModifyOrder
    }
    
    o.Items = append(o.Items, item)
    o.TotalPrice = o.CalculateTotal()
    o.UpdatedAt = time.Now().UTC()
    
    if err := s.repo.SaveOrder(ctx, o); err != nil {
        return nil, fmt.Errorf("failed to save order: %w", err)
    }
    
    return o, nil
}

// SubmitOrder submits an order for processing.
func (s *DefaultService) SubmitOrder(ctx context.Context, id string) (*order.Order, error) {
    o, err := s.repo.GetOrder(ctx, id)
    if err != nil {
        return nil, fmt.Errorf("failed to get order: %w", err)
    }
    if o == nil {
        return nil, order.ErrNotFound
    }
    
    // Business logic in service layer
    if !o.IsDraft() {
        return nil, order.ErrInvalidTransition
    }
    if !o.HasItems() {
        return nil, order.ErrEmptyOrder
    }
    
    o.Status = order.StatusPending
    o.UpdatedAt = time.Now().UTC()
    
    if err := s.repo.SaveOrder(ctx, o); err != nil {
        return nil, fmt.Errorf("failed to save order: %w", err)
    }
    
    return o, nil
}

// CancelOrder cancels an order.
func (s *DefaultService) CancelOrder(ctx context.Context, id string) error {
    o, err := s.repo.GetOrder(ctx, id)
    if err != nil {
        return fmt.Errorf("failed to get order: %w", err)
    }
    if o == nil {
        return order.ErrNotFound
    }
    
    // Business logic in service layer
    if !o.CanBeCancelled() {
        return order.ErrInvalidTransition
    }
    
    o.Status = order.StatusCancelled
    o.UpdatedAt = time.Now().UTC()
    
    return s.repo.SaveOrder(ctx, o)
}
```

#### Instrumentation Wrapper (devkit/common)

> **REQUIRED PATTERN**: All instrumented wrappers MUST use `trace.Instrument(ctx, method)` for automatic span creation. Do NOT use `trace.Start(ctx, "manual.name")` - it is error-prone, lacks code location attributes, and is considered deprecated for service/repository instrumentation.
>
> **Benefits of `trace.Instrument`:**
> - Automatic span naming from method signature (no typos)
> - Code location attributes added automatically (`code.function`, `code.filepath`)
> - Type-safe method reference
> - Consistent naming across all services

```go
// internal/services/orders/instrumented.go
package orders

import (
    "context"
    "time"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace"

    "your-service/internal/core/order"
)

// InstrumentedService wraps DefaultService with automatic tracing and logging.
type InstrumentedService struct {
    inner *DefaultService
    log   logger.Logger
}

// NewInstrumentedService creates a new instrumented wrapper.
func NewInstrumentedService(s *DefaultService, log logger.Logger) *InstrumentedService {
    return &InstrumentedService{
        inner: s,
        log:   log.Named("orders.service"),
    }
}

// CreateOrder creates an order with automatic tracing and logging.
func (s *InstrumentedService) CreateOrder(ctx context.Context, userID string) (*order.Order, error) {
    start := time.Now()

    // Use trace.Instrument for automatic span creation from method reference
    ctx, span := trace.Instrument(ctx, s.inner.CreateOrder)
    defer span.End()

    // Add business-specific attributes
    span.SetAttributes(
        trace.String("order.user_id", userID),
    )

    // Log with auto-enriched context (trace_id, span_id, tenant_id, request_id)
    s.log.Info(ctx, "creating order",
        logger.String("user_id", userID),
    )

    // Call inner service
    result, err := s.inner.CreateOrder(ctx, userID)

    // Record duration
    duration := time.Since(start).Seconds()
    span.SetAttributes(trace.Float64("duration_seconds", duration))

    if err != nil {
        span.RecordError(err)
        span.SetStatus(trace.StatusError, "failed to create order")
        s.log.Error(ctx, "failed to create order",
            logger.Err(err),
            logger.Duration("duration", time.Since(start)),
        )
        return nil, err
    }

    span.SetStatus(trace.StatusOK, "order created")
    s.log.Info(ctx, "order created successfully",
        logger.String("order_id", result.ID),
        logger.Duration("duration", time.Since(start)),
    )

    return result, nil
}

// GetOrder retrieves an order with automatic tracing and logging.
func (s *InstrumentedService) GetOrder(ctx context.Context, id string) (*order.Order, error) {
    ctx, span := trace.Instrument(ctx, s.inner.GetOrder)
    defer span.End()

    span.SetAttributes(trace.String("order.id", id))
    s.log.Debug(ctx, "getting order", logger.String("id", id))

    result, err := s.inner.GetOrder(ctx, id)
    if err != nil {
        span.RecordError(err)
        span.SetStatus(trace.StatusError, "failed to get order")
        s.log.Error(ctx, "failed to get order", logger.String("id", id), logger.Err(err))
        return nil, err
    }

    span.SetStatus(trace.StatusOK, "order retrieved")
    return result, nil
}

// ListUserOrders, AddItem, SubmitOrder, CancelOrder follow the same pattern...
```

### Step 3: Add Repository Support

#### Ent Schema

```go
// internal/repo/postgres/ent/schema/order.go
package schema

import (
    "time"
    
    "entgo.io/ent"
    "entgo.io/ent/schema/field"
)

type Order struct {
    ent.Schema
}

func (Order) Fields() []ent.Field {
    return []ent.Field{
        field.String("id").Unique().Immutable(),
        field.String("user_id"),
        field.Int64("total_price"),
        field.String("status"),
        field.JSON("items", []OrderItem{}).Optional(),
        field.Time("created_at").Default(time.Now).Immutable(),
        field.Time("updated_at").Default(time.Now).UpdateDefault(time.Now),
    }
}

type OrderItem struct {
    ProductID string `json:"product_id"`
    Name      string `json:"name"`
    Price     int64  `json:"price"`
    Quantity  int    `json:"quantity"`
}
```

#### Regenerate Ent

```bash
task generate:ent
```

#### Repository Methods

```go
// internal/repo/postgres/orders.go
package postgres

import (
    "context"
    "fmt"
    
    "your-service/internal/core/order"
    "your-service/internal/repo/postgres/ent"
    entorder "your-service/internal/repo/postgres/ent/order"
)

// SaveOrder saves an order (upsert).
func (r *Repo) SaveOrder(ctx context.Context, o *order.Order) error {
    items := make([]ent.OrderItem, len(o.Items))
    for i, item := range o.Items {
        items[i] = ent.OrderItem{
            ProductID: item.ProductID,
            Name:      item.Name,
            Price:     item.Price,
            Quantity:  item.Quantity,
        }
    }
    
    err := r.client.Order.Create().
        SetID(o.ID).
        SetUserID(o.UserID).
        SetTotalPrice(o.TotalPrice).
        SetStatus(string(o.Status)).
        SetItems(items).
        SetCreatedAt(o.CreatedAt).
        SetUpdatedAt(o.UpdatedAt).
        OnConflictColumns(entorder.FieldID).
        UpdateNewValues().
        Exec(ctx)
    if err != nil {
        return fmt.Errorf("failed to save order: %w", err)
    }
    return nil
}

// GetOrder retrieves an order by ID.
func (r *Repo) GetOrder(ctx context.Context, id string) (*order.Order, error) {
    o, err := r.client.Order.Query().
        Where(entorder.ID(id)).
        Only(ctx)
    if ent.IsNotFound(err) {
        return nil, nil
    }
    if err != nil {
        return nil, fmt.Errorf("failed to get order: %w", err)
    }
    return toCoreOrder(o), nil
}

// ListUserOrders retrieves all orders for a user.
func (r *Repo) ListUserOrders(ctx context.Context, userID string) ([]*order.Order, error) {
    orders, err := r.client.Order.Query().
        Where(entorder.UserID(userID)).
        Order(ent.Desc(entorder.FieldCreatedAt)).
        All(ctx)
    if err != nil {
        return nil, fmt.Errorf("failed to list orders: %w", err)
    }
    
    result := make([]*order.Order, len(orders))
    for i, o := range orders {
        result[i] = toCoreOrder(o)
    }
    return result, nil
}

func toCoreOrder(o *ent.Order) *order.Order {
    items := make([]order.Item, len(o.Items))
    for i, item := range o.Items {
        items[i] = order.Item{
            ProductID: item.ProductID,
            Name:      item.Name,
            Price:     item.Price,
            Quantity:  item.Quantity,
        }
    }
    
    return &order.Order{
        ID:         o.ID,
        UserID:     o.UserID,
        Items:      items,
        TotalPrice: o.TotalPrice,
        Status:     order.Status(o.Status),
        CreatedAt:  o.CreatedAt,
        UpdatedAt:  o.UpdatedAt,
    }
}
```

#### Update Repository Interface

```go
// internal/repo/repo.go
type Repo interface {
    // User operations
    SaveUser(ctx context.Context, u *user.User) error
    // ...
    
    // Order operations
    SaveOrder(ctx context.Context, o *order.Order) error
    GetOrder(ctx context.Context, id string) (*order.Order, error)
    ListUserOrders(ctx context.Context, userID string) ([]*order.Order, error)
}
```

#### Update Root Repository

```go
// internal/repo/root.go
func (r *RootRepo) SaveOrder(ctx context.Context, o *order.Order) error {
    return r.postgresRepo.SaveOrder(ctx, o)
}

func (r *RootRepo) GetOrder(ctx context.Context, id string) (*order.Order, error) {
    return r.postgresRepo.GetOrder(ctx, id)
}

func (r *RootRepo) ListUserOrders(ctx context.Context, userID string) ([]*order.Order, error) {
    return r.postgresRepo.ListUserOrders(ctx, userID)
}
```

### Step 4: Add gRPC Handlers

#### Update Proto

```protobuf
// api/protobuf/v1/orders.proto
service OrderService {
    rpc CreateOrder(CreateOrderRequest) returns (CreateOrderResponse);
    rpc GetOrder(GetOrderRequest) returns (GetOrderResponse);
    rpc ListUserOrders(ListUserOrdersRequest) returns (ListUserOrdersResponse);
    rpc AddItem(AddItemRequest) returns (AddItemResponse);
    rpc SubmitOrder(SubmitOrderRequest) returns (SubmitOrderResponse);
    rpc CancelOrder(CancelOrderRequest) returns (CancelOrderResponse);
}

message Order {
    string id = 1;
    string user_id = 2;
    repeated OrderItem items = 3;
    int64 total_price = 4;
    string status = 5;
}

message OrderItem {
    string product_id = 1;
    string name = 2;
    int64 price = 3;
    int32 quantity = 4;
}
```

#### Regenerate Proto

```bash
task generate:proto
```

#### Handler Implementation

```go
// internal/handlers/grpc/orders.go
package grpc

import (
    "context"
    
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"
    
    "your-service/internal/core/order"
    pb "your-service/internal/proto/gen/v1"
)

func (h *Handler) CreateOrder(ctx context.Context, req *pb.CreateOrderRequest) (*pb.CreateOrderResponse, error) {
    o, err := h.ordersService.CreateOrder(ctx, req.UserId)
    if err != nil {
        return nil, mapOrderError(err)
    }
    return &pb.CreateOrderResponse{Order: orderToProto(o)}, nil
}

func (h *Handler) GetOrder(ctx context.Context, req *pb.GetOrderRequest) (*pb.GetOrderResponse, error) {
    o, err := h.ordersService.GetOrder(ctx, req.Id)
    if err != nil {
        return nil, mapOrderError(err)
    }
    return &pb.GetOrderResponse{Order: orderToProto(o)}, nil
}

// ... other methods

func mapOrderError(err error) error {
    switch err {
    case order.ErrNotFound:
        return status.Error(codes.NotFound, err.Error())
    case order.ErrCannotModifyOrder, order.ErrInvalidTransition, order.ErrEmptyOrder:
        return status.Error(codes.FailedPrecondition, err.Error())
    default:
        return status.Error(codes.Internal, "internal error")
    }
}

func orderToProto(o *order.Order) *pb.Order {
    items := make([]*pb.OrderItem, len(o.Items))
    for i, item := range o.Items {
        items[i] = &pb.OrderItem{
            ProductId: item.ProductID,
            Name:      item.Name,
            Price:     item.Price,
            Quantity:  int32(item.Quantity),
        }
    }
    return &pb.Order{
        Id:         o.ID,
        UserId:     o.UserID,
        Items:      items,
        TotalPrice: o.TotalPrice,
        Status:     string(o.Status),
    }
}
```

### Step 5: Wire DI

```go
// cmd/run/service_builder.go

func (b *ServiceBuilder) WithServices() *ServiceBuilder {
    b.options = append(b.options,
        // Users service
        fx.Provide(func(r repo.Repo) *users.DefaultService {
            return users.NewDefaultService(r)
        }),
        fx.Provide(func(s *users.DefaultService) users.Service {
            return users.NewInstrumentedService(s)
        }),
        
        // Orders service (NEW)
        fx.Provide(func(r repo.Repo) *orders.DefaultService {
            return orders.NewDefaultService(r)
        }),
        fx.Provide(func(s *orders.DefaultService) orders.Service {
            return orders.NewInstrumentedService(s)
        }),
    )
    return b
}
```

Update handler to accept orders service:

```go
// internal/handlers/grpc/handler.go
type Handler struct {
    // ...
    usersService  users.Service
    ordersService orders.Service  // NEW
}

func NewHandler(
    cfg *config.Config,
    logger *zap.Logger,
    usersService users.Service,
    ordersService orders.Service,  // NEW
) *Handler {
    return &Handler{
        // ...
        usersService:  usersService,
        ordersService: ordersService,
    }
}
```

## Verification

After implementing:

1. **Build**: `go build ./...`
2. **Test**: `go test ./...`
3. **Lint**: `golangci-lint run`

Checklist:
- [ ] Domain entities in `internal/core/order/`
- [ ] No external imports in domain
- [ ] Service interface DEFINED directly in `service.go` (not type alias)
- [ ] Service implementation in `default.go` with proper error handling
- [ ] Instrumented wrapper in `instrumented.go` using `trace.Instrument`
- [ ] Unit tests in `default_test.go`
- [ ] Repository methods implemented
- [ ] Ent schema generated
- [ ] gRPC handlers with error mapping
- [ ] DI wiring updated

---

## Multi-Tenancy Patterns

For SaaS services requiring tenant isolation:

### Domain Layer

Add `TenantID` field to entities:

```go
// internal/core/product/product.go
type Product struct {
    ID          string
    TenantID    string    // Required for multi-tenancy
    Name        string
    Description string
    // ... other fields
    CreatedAt   time.Time
    UpdatedAt   time.Time
}
```

### Repository Interface

Include tenant filtering in repository signatures:

```go
// internal/repo/repo.go
type ProductRepository interface {
    Create(ctx context.Context, product *product.Product) error
    GetByID(ctx context.Context, tenantID, id string) (*product.Product, error)
    ListByTenant(ctx context.Context, tenantID string, limit, offset int) ([]*product.Product, error)
    Update(ctx context.Context, product *product.Product) error
    Delete(ctx context.Context, tenantID, id string) error
}
```

### Repository Implementation

Always filter by tenant_id:

```go
// internal/repo/postgres/products.go
func (r *Repo) GetByID(ctx context.Context, tenantID, id string) (*product.Product, error) {
    p, err := r.client.Product.
        Query().
        Where(
            entproduct.IDEQ(id),
            entproduct.TenantIDEQ(tenantID),  // Always filter by tenant
        ).
        Only(ctx)
    // ...
}
```

### Handler Layer

Extract tenant_id from context (via middleware):

```go
// internal/handlers/grpc/product.go
func (h *Handler) GetProduct(ctx context.Context, req *pb.GetProductRequest) (*pb.GetProductResponse, error) {
    // Extract tenant from context (set by interceptor/middleware)
    tenantID := xctx.TenantID(ctx)
    if tenantID == "" {
        return nil, status.Error(codes.InvalidArgument, "tenant_id required")
    }

    product, err := h.productService.GetByID(ctx, tenantID, req.Id)
    // ...
}
```

### Context Middleware

Use devkit/common context utilities:

```go
import "gitlab.com/umo-tech-ltd-group/platform/devkit/common/xctx"

// Extract from gRPC metadata
tenantID := xctx.TenantID(ctx)

// Set in context
ctx = xctx.WithTenantID(ctx, tenantID)
```

---

## Error Handling Patterns

### Error Wrapping

Always wrap errors with context:

```go
// Good - provides context for debugging
if err := r.client.Product.Create().Exec(ctx); err != nil {
    return fmt.Errorf("failed to create product %s: %w", id, err)
}

// Good - check specific error types
if ent.IsNotFound(err) {
    return product.ErrNotFound
}

// Bad - loses context
return err
```

### Domain Errors

Define sentinel errors in the domain layer:

```go
// internal/core/product/errors.go
package product

import "errors"

var (
    ErrNotFound      = errors.New("product not found")
    ErrAlreadyExists = errors.New("product already exists")
    ErrInvalidID     = errors.New("invalid product id")
    ErrInvalidPrice  = errors.New("price must be positive")
    ErrInvalidStatus = errors.New("invalid product status")
    ErrCannotModify  = errors.New("product cannot be modified")
)
```

### Error Checking

Use `errors.Is()` and `errors.As()` for checking:

```go
// Check specific error
if errors.Is(err, product.ErrNotFound) {
    return status.Error(codes.NotFound, "product not found")
}

// Check error type
var validationErr *ValidationError
if errors.As(err, &validationErr) {
    return status.Error(codes.InvalidArgument, validationErr.Message())
}
```

### Error Mapping in Handlers

Map domain errors to transport errors:

```go
// internal/handlers/grpc/errors.go
func mapError(err error) error {
    switch {
    case errors.Is(err, product.ErrNotFound):
        return status.Error(codes.NotFound, err.Error())
    case errors.Is(err, product.ErrAlreadyExists):
        return status.Error(codes.AlreadyExists, err.Error())
    case errors.Is(err, product.ErrInvalidID),
         errors.Is(err, product.ErrInvalidPrice),
         errors.Is(err, product.ErrInvalidStatus):
        return status.Error(codes.InvalidArgument, err.Error())
    case errors.Is(err, product.ErrCannotModify):
        return status.Error(codes.FailedPrecondition, err.Error())
    default:
        return status.Error(codes.Internal, "internal error")
    }
}
```

### Error Chain Preservation

Preserve error chains for logging while returning clean errors to clients:

```go
func (s *InstrumentedService) Create(ctx context.Context, input *CreateInput) (*product.Product, error) {
    p, err := s.inner.Create(ctx, input)
    if err != nil {
        // Log full error chain for debugging
        s.log.Error(ctx, "failed to create product",
            logger.Error(err),  // Full chain in logs
            logger.String("name", input.Name),
        )
        
        // Return clean domain error to handler
        // Handler will map to appropriate transport error
        return nil, err
    }
    return p, nil
}
```
