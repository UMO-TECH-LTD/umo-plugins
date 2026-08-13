# Proto Mapping Patterns

This document describes patterns for bidirectional conversion between Protocol Buffer messages and domain types in Go microservices.

## Overview

A dedicated proto mapping layer provides:
- **Separation of concerns**: Handlers stay thin, conversion logic is centralized
- **Testability**: Conversion functions can be unit tested independently
- **Maintainability**: Changes to proto or domain types affect only the mapping layer
- **Consistency**: All conversions follow the same patterns

**When to use a protomap layer:**
- Service has multiple gRPC methods
- Proto messages differ significantly from domain types
- Complex nested structures require conversion
- Multiple handlers need the same conversions

## Directory Structure

```
internal/protomap/
├── product.go              # Product entity conversions
├── product_test.go         # Conversion tests
├── order.go                # Order entity conversions
├── order_test.go
├── enums.go                # Enum conversions
├── helpers.go              # Common utilities
└── errors.go               # Conversion error types

# Import paths
# - Domain types: {{module}}/internal/core/product
# - Proto types:  {{module}}/api/proto/product/v1
```

## Core Conversion Pattern

### Entity Conversion Functions

```go
// internal/protomap/product.go
package protomap

import (
    "fmt"
    "time"

    "github.com/shopspring/decimal"
    "google.golang.org/protobuf/types/known/timestamppb"

    productcore "{{module}}/internal/core/product"
    pb "{{module}}/api/proto/product/v1"
)

// ProductToProto converts a domain Product to a protobuf Product.
func ProductToProto(p *productcore.Product) (*pb.Product, error) {
    if p == nil {
        return nil, nil
    }

    // Convert nested/complex fields
    attributes, err := attributesToProto(p.Attributes)
    if err != nil {
        return nil, fmt.Errorf("failed to convert attributes: %w", err)
    }

    return &pb.Product{
        Id:          p.ID,
        TenantId:    p.TenantID,
        Name:        p.Name,
        Description: p.Description,
        Price:       p.Price.InexactFloat64(),
        Quantity:    int32(p.Quantity),
        Status:      productStatusToProto(p.Status),
        Attributes:  attributes,
        CreatedAt:   timestamppb.New(p.CreatedAt),
        UpdatedAt:   timestamppb.New(p.UpdatedAt),
    }, nil
}

// ProtoToProduct converts a protobuf Product to a domain Product.
func ProtoToProduct(proto *pb.Product) (*productcore.Product, error) {
    if proto == nil {
        return nil, nil
    }

    attributes := protoToAttributes(proto.Attributes)

    return &productcore.Product{
        ID:          proto.Id,
        TenantID:    proto.TenantId,
        Name:        proto.Name,
        Description: proto.Description,
        Price:       decimal.NewFromFloat(proto.Price),
        Quantity:    int(proto.Quantity),
        Status:      protoToProductStatus(proto.Status),
        Attributes:  attributes,
        CreatedAt:   proto.CreatedAt.AsTime(),
        UpdatedAt:   proto.UpdatedAt.AsTime(),
    }, nil
}
```

### Nil Handling at Entry

Always check for nil at the start of conversion functions:

```go
func EntityToProto(e *domain.Entity) (*pb.Entity, error) {
    if e == nil {
        return nil, nil
    }
    // ... conversion logic
}

func ProtoToEntity(proto *pb.Entity) (*domain.Entity, error) {
    if proto == nil {
        return nil, nil
    }
    // ... conversion logic
}
```

## Enum Conversion Pattern

```go
// internal/protomap/enums.go
package protomap

import (
    productcore "{{module}}/internal/core/product"
    pb "{{module}}/api/proto/product/v1"
)

// productStatusToProto converts domain ProductStatus to protobuf.
func productStatusToProto(s productcore.Status) pb.ProductStatus {
    switch s {
    case productcore.StatusActive:
        return pb.ProductStatus_PRODUCT_STATUS_ACTIVE
    case productcore.StatusInactive:
        return pb.ProductStatus_PRODUCT_STATUS_INACTIVE
    case productcore.StatusDeleted:
        return pb.ProductStatus_PRODUCT_STATUS_DELETED
    default:
        return pb.ProductStatus_PRODUCT_STATUS_UNSPECIFIED
    }
}

// protoToProductStatus converts protobuf ProductStatus to domain.
func protoToProductStatus(s pb.ProductStatus) productcore.Status {
    switch s {
    case pb.ProductStatus_PRODUCT_STATUS_ACTIVE:
        return productcore.StatusActive
    case pb.ProductStatus_PRODUCT_STATUS_INACTIVE:
        return productcore.StatusInactive
    case pb.ProductStatus_PRODUCT_STATUS_DELETED:
        return productcore.StatusDeleted
    default:
        return productcore.StatusActive // Default to a valid state
    }
}

// orderStatusToProto converts domain OrderStatus to protobuf.
func orderStatusToProto(s order.Status) pb.OrderStatus {
    switch s {
    case order.StatusPending:
        return pb.OrderStatus_ORDER_STATUS_PENDING
    case order.StatusProcessing:
        return pb.OrderStatus_ORDER_STATUS_PROCESSING
    case order.StatusCompleted:
        return pb.OrderStatus_ORDER_STATUS_COMPLETED
    case order.StatusCancelled:
        return pb.OrderStatus_ORDER_STATUS_CANCELLED
    case order.StatusFailed:
        return pb.OrderStatus_ORDER_STATUS_FAILED
    default:
        return pb.OrderStatus_ORDER_STATUS_UNSPECIFIED
    }
}
```

## Collection Conversion Pattern

```go
// internal/protomap/product.go
package protomap

// ProductsToProto converts a slice of domain Products to protobuf.
func ProductsToProto(products []*productcore.Product) ([]*pb.Product, error) {
    if products == nil {
        return nil, nil
    }

    result := make([]*pb.Product, len(products))
    for i, p := range products {
        proto, err := ProductToProto(p)
        if err != nil {
            return nil, fmt.Errorf("failed to convert product at index %d: %w", i, err)
        }
        result[i] = proto
    }
    return result, nil
}

// ProtoToProducts converts a slice of protobuf Products to domain.
func ProtoToProducts(protos []*pb.Product) ([]*productcore.Product, error) {
    if protos == nil {
        return nil, nil
    }

    result := make([]*productcore.Product, len(protos))
    for i, proto := range protos {
        p, err := ProtoToProduct(proto)
        if err != nil {
            return nil, fmt.Errorf("failed to convert product at index %d: %w", i, err)
        }
        result[i] = p
    }
    return result, nil
}
```

## Complex Type Handling

### Dynamic Values (structpb)

```go
// internal/protomap/helpers.go
package protomap

import (
    "fmt"

    "google.golang.org/protobuf/types/known/structpb"
)

// attributesToProto converts a map to protobuf Attributes.
func attributesToProto(attrs map[string]any) ([]*pb.Attribute, error) {
    if attrs == nil {
        return nil, nil
    }

    result := make([]*pb.Attribute, 0, len(attrs))
    for name, val := range attrs {
        value, err := structpb.NewValue(val)
        if err != nil {
            return nil, fmt.Errorf("failed to convert attribute %q: %w", name, err)
        }
        result = append(result, &pb.Attribute{
            Name:  name,
            Value: value,
        })
    }
    return result, nil
}

// protoToAttributes converts protobuf Attributes to a map.
func protoToAttributes(attrs []*pb.Attribute) map[string]any {
    if attrs == nil {
        return make(map[string]any)
    }

    result := make(map[string]any, len(attrs))
    for _, attr := range attrs {
        result[attr.Name] = attr.Value.AsInterface()
    }
    return result
}

// mapToStruct converts a Go map to structpb.Struct.
func mapToStruct(m map[string]any) (*structpb.Struct, error) {
    if m == nil {
        return nil, nil
    }
    return structpb.NewStruct(m)
}

// structToMap converts structpb.Struct to a Go map.
func structToMap(s *structpb.Struct) map[string]any {
    if s == nil {
        return make(map[string]any)
    }
    return s.AsMap()
}
```

### Timestamp Conversion

```go
import "google.golang.org/protobuf/types/known/timestamppb"

// Domain to Proto
CreatedAt: timestamppb.New(entity.CreatedAt)

// Proto to Domain
CreatedAt: proto.CreatedAt.AsTime()

// Handle optional timestamps
func optionalTimestampToProto(t *time.Time) *timestamppb.Timestamp {
    if t == nil {
        return nil
    }
    return timestamppb.New(*t)
}

func protoToOptionalTimestamp(ts *timestamppb.Timestamp) *time.Time {
    if ts == nil {
        return nil
    }
    t := ts.AsTime()
    return &t
}
```

### Decimal Conversion

```go
import "github.com/shopspring/decimal"

// Domain to Proto (as float64)
Price: entity.Price.InexactFloat64()

// Proto to Domain
Price: decimal.NewFromFloat(proto.Price)

// Alternative: as string for precision
PriceStr: entity.Price.String()
Price:    decimal.RequireFromString(proto.PriceStr)
```

### Optional Fields

```go
// Proto uses wrappers or pointer types for optional fields
import "google.golang.org/protobuf/types/known/wrapperspb"

// Optional string
func optionalStringToProto(s *string) *wrapperspb.StringValue {
    if s == nil {
        return nil
    }
    return wrapperspb.String(*s)
}

func protoToOptionalString(s *wrapperspb.StringValue) *string {
    if s == nil {
        return nil
    }
    v := s.Value
    return &v
}

// Using proto3 optional keyword (generates pointer in Go)
// message Product {
//   optional string description = 4;
// }
```

## Nested Type Conversion

```go
// internal/protomap/order.go
package protomap

// OrderToProto converts a domain Order to protobuf.
func OrderToProto(o *order.Order) (*pb.Order, error) {
    if o == nil {
        return nil, nil
    }

    // Convert nested items
    items, err := orderItemsToProto(o.Items)
    if err != nil {
        return nil, fmt.Errorf("failed to convert order items: %w", err)
    }

    // Convert nested address
    shippingAddr, err := addressToProto(o.ShippingAddress)
    if err != nil {
        return nil, fmt.Errorf("failed to convert shipping address: %w", err)
    }

    return &pb.Order{
        Id:              o.ID,
        CustomerId:      o.CustomerID,
        Items:           items,
        ShippingAddress: shippingAddr,
        Total:           o.Total.InexactFloat64(),
        Status:          orderStatusToProto(o.Status),
        CreatedAt:       timestamppb.New(o.CreatedAt),
    }, nil
}

// orderItemsToProto converts order items.
func orderItemsToProto(items []*order.Item) ([]*pb.OrderItem, error) {
    if items == nil {
        return nil, nil
    }

    result := make([]*pb.OrderItem, len(items))
    for i, item := range items {
        result[i] = &pb.OrderItem{
            ProductId: item.ProductID,
            Quantity:  int32(item.Quantity),
            Price:     item.Price.InexactFloat64(),
        }
    }
    return result, nil
}

// addressToProto converts an address.
func addressToProto(addr *order.Address) (*pb.Address, error) {
    if addr == nil {
        return nil, nil
    }

    return &pb.Address{
        Street:  addr.Street,
        City:    addr.City,
        Country: addr.Country,
        ZipCode: addr.ZipCode,
    }, nil
}
```

## Request/Response Conversion

```go
// internal/protomap/requests.go
package protomap

// CreateProductInputFromProto converts CreateProductRequest to service input.
func CreateProductInputFromProto(req *pb.CreateProductRequest) (*product.CreateInput, error) {
    if req == nil {
        return nil, fmt.Errorf("request is nil")
    }

    attrs := protoToAttributes(req.Attributes)

    return &product.CreateInput{
        Name:        req.Name,
        Description: req.Description,
        Price:       decimal.NewFromFloat(req.Price),
        Quantity:    int(req.Quantity),
        Attributes:  attrs,
    }, nil
}

// UpdateProductInputFromProto converts UpdateProductRequest to service input.
func UpdateProductInputFromProto(req *pb.UpdateProductRequest) (*product.UpdateInput, error) {
    if req == nil {
        return nil, fmt.Errorf("request is nil")
    }

    input := &product.UpdateInput{}

    // Handle optional fields
    if req.Name != nil {
        input.Name = req.Name
    }
    if req.Description != nil {
        input.Description = req.Description
    }
    if req.Price != nil {
        p := decimal.NewFromFloat(*req.Price)
        input.Price = &p
    }
    if req.Quantity != nil {
        q := int(*req.Quantity)
        input.Quantity = &q
    }
    if req.Status != pb.ProductStatus_PRODUCT_STATUS_UNSPECIFIED {
        s := protoToProductStatus(req.Status)
        input.Status = &s
    }

    return input, nil
}
```

## Usage in Handlers

### gRPC Handler Example

```go
// internal/handlers/grpc/product.go
package grpc

import (
    "context"

    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"

    pb "{{module}}/api/proto/product/v1"
    "{{module}}/internal/protomap"
    "{{module}}/internal/services/product"
)

type ProductHandler struct {
    pb.UnimplementedProductServiceServer
    service product.Service
}

func (h *ProductHandler) CreateProduct(
    ctx context.Context,
    req *pb.CreateProductRequest,
) (*pb.CreateProductResponse, error) {
    // Convert request to service input
    input, err := protomap.CreateProductInputFromProto(req)
    if err != nil {
        return nil, status.Errorf(codes.InvalidArgument, "invalid request: %v", err)
    }

    // Call service
    p, err := h.service.Create(ctx, input)
    if err != nil {
        return nil, mapError(err)
    }

    // Convert response to proto
    protoProduct, err := protomap.ProductToProto(p)
    if err != nil {
        return nil, status.Errorf(codes.Internal, "failed to convert response: %v", err)
    }

    return &pb.CreateProductResponse{Product: protoProduct}, nil
}

func (h *ProductHandler) ListProducts(
    ctx context.Context,
    req *pb.ListProductsRequest,
) (*pb.ListProductsResponse, error) {
    products, err := h.service.List(ctx, int(req.PageSize), int(req.Offset))
    if err != nil {
        return nil, mapError(err)
    }

    // Convert slice to proto
    protoProducts, err := protomap.ProductsToProto(products)
    if err != nil {
        return nil, status.Errorf(codes.Internal, "failed to convert response: %v", err)
    }

    return &pb.ListProductsResponse{Products: protoProducts}, nil
}
```

## Testing Conversion Functions

```go
// internal/protomap/product_test.go
package protomap_test

import (
    "testing"
    "time"

    "github.com/shopspring/decimal"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
    "google.golang.org/protobuf/types/known/timestamppb"

    productcore "{{module}}/internal/core/product"
    pb "{{module}}/api/proto/product/v1"
    "{{module}}/internal/protomap"
)

func TestProductToProto(t *testing.T) {
    now := time.Now().Truncate(time.Microsecond) // Proto truncates to microseconds

    tests := []struct {
        name    string
        domain  *productcore.Product
        want    *pb.Product
        wantErr bool
    }{
        {
            name:   "nil product",
            domain: nil,
            want:   nil,
        },
        {
            name: "full product",
            domain: &productcore.Product{
                ID:          "prod-123",
                TenantID:    "tenant-1",
                Name:        "Widget",
                Description: "A fine widget",
                Price:       decimal.NewFromFloat(19.99),
                Quantity:    10,
                Status:      productcore.StatusActive,
                Attributes:  map[string]any{"color": "blue"},
                CreatedAt:   now,
                UpdatedAt:   now,
            },
            want: &pb.Product{
                Id:          "prod-123",
                TenantId:    "tenant-1",
                Name:        "Widget",
                Description: "A fine widget",
                Price:       19.99,
                Quantity:    10,
                Status:      pb.ProductStatus_PRODUCT_STATUS_ACTIVE,
                CreatedAt:   timestamppb.New(now),
                UpdatedAt:   timestamppb.New(now),
            },
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := protomap.ProductToProto(tt.domain)
            if tt.wantErr {
                require.Error(t, err)
                return
            }
            require.NoError(t, err)

            if tt.want == nil {
                assert.Nil(t, got)
                return
            }

            assert.Equal(t, tt.want.Id, got.Id)
            assert.Equal(t, tt.want.TenantId, got.TenantId)
            assert.Equal(t, tt.want.Name, got.Name)
            assert.Equal(t, tt.want.Status, got.Status)
            assert.InDelta(t, tt.want.Price, got.Price, 0.001)
        })
    }
}

func TestProtoToProduct(t *testing.T) {
    now := time.Now().Truncate(time.Microsecond)

    tests := []struct {
        name    string
        proto   *pb.Product
        want    *productcore.Product
        wantErr bool
    }{
        {
            name:  "nil proto",
            proto: nil,
            want:  nil,
        },
        {
            name: "full proto",
            proto: &pb.Product{
                Id:          "prod-123",
                TenantId:    "tenant-1",
                Name:        "Widget",
                Description: "A fine widget",
                Price:       19.99,
                Quantity:    10,
                Status:      pb.ProductStatus_PRODUCT_STATUS_ACTIVE,
                CreatedAt:   timestamppb.New(now),
                UpdatedAt:   timestamppb.New(now),
            },
            want: &productcore.Product{
                ID:          "prod-123",
                TenantID:    "tenant-1",
                Name:        "Widget",
                Description: "A fine widget",
                Price:       decimal.NewFromFloat(19.99),
                Quantity:    10,
                Status:      productcore.StatusActive,
                CreatedAt:   now,
                UpdatedAt:   now,
            },
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := protomap.ProtoToProduct(tt.proto)
            if tt.wantErr {
                require.Error(t, err)
                return
            }
            require.NoError(t, err)

            if tt.want == nil {
                assert.Nil(t, got)
                return
            }

            assert.Equal(t, tt.want.ID, got.ID)
            assert.Equal(t, tt.want.TenantID, got.TenantID)
            assert.Equal(t, tt.want.Name, got.Name)
            assert.Equal(t, tt.want.Status, got.Status)
            assert.True(t, tt.want.Price.Equal(got.Price))
        })
    }
}

func TestRoundTrip(t *testing.T) {
    // Test that converting to proto and back produces the same domain object
    now := time.Now().Truncate(time.Microsecond)

    original := &productcore.Product{
        ID:          "prod-123",
        TenantID:    "tenant-1",
        Name:        "Widget",
        Description: "A fine widget",
        Price:       decimal.NewFromFloat(19.99),
        Quantity:    10,
        Status:      productcore.StatusActive,
        Attributes:  map[string]any{"color": "blue", "size": "large"},
        CreatedAt:   now,
        UpdatedAt:   now,
    }

    // Convert to proto
    proto, err := protomap.ProductToProto(original)
    require.NoError(t, err)

    // Convert back to domain
    result, err := protomap.ProtoToProduct(proto)
    require.NoError(t, err)

    // Verify round-trip
    assert.Equal(t, original.ID, result.ID)
    assert.Equal(t, original.Name, result.Name)
    assert.Equal(t, original.Status, result.Status)
    assert.True(t, original.Price.Equal(result.Price))
}
```

## Quick Reference

### Naming Conventions

| Function | Pattern |
|----------|---------|
| Domain → Proto | `EntityToProto(e *domain.Entity) (*pb.Entity, error)` |
| Proto → Domain | `ProtoToEntity(proto *pb.Entity) (*domain.Entity, error)` |
| Enum → Proto | `entityStatusToProto(s domain.Status) pb.EntityStatus` |
| Proto → Enum | `protoToEntityStatus(s pb.EntityStatus) domain.Status` |
| Collection | `EntitiesToProto`, `ProtoToEntities` |

### Error Handling

```go
// Wrap errors with context
if err != nil {
    return nil, fmt.Errorf("failed to convert %s: %w", fieldName, err)
}

// Use specific error types for validation
var ErrNilRequest = errors.New("request is nil")
var ErrInvalidField = errors.New("invalid field value")
```

### Common Imports

```go
import (
    "google.golang.org/protobuf/types/known/timestamppb"
    "google.golang.org/protobuf/types/known/structpb"
    "google.golang.org/protobuf/types/known/wrapperspb"
    "github.com/shopspring/decimal"
)
```
