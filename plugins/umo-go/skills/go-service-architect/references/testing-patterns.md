# Testing Patterns

This document describes comprehensive testing patterns for production-ready Go microservices, including unit tests, integration tests, and end-to-end (E2E) tests.

## Overview

Production services require multiple layers of testing:

| Test Type | Purpose | Dependencies | Speed |
|-----------|---------|--------------|-------|
| **Unit** | Test individual functions/methods | Mocks only | Fast |
| **Integration** | Test with real infrastructure | Database, Redis, etc. | Medium |
| **E2E** | Test complete workflows | Full service stack | Slow |

## Directory Structure

```
test/
├── infra/                        # Infrastructure management
│   ├── suite.go                  # Main infrastructure controller
│   ├── docker.go                 # Docker Compose management
│   ├── grpc.go                   # gRPC client management
│   └── wait.go                   # Service readiness waiting
├── integration/                  # Integration tests
│   ├── suite.go                  # Integration suite setup
│   ├── helpers.go                # Test utilities
│   ├── product_test.go           # Entity-specific tests
│   └── ...
├── e2e/                          # End-to-end tests
│   ├── suite.go                  # E2E suite setup
│   ├── helpers.go                # E2E-specific helpers
│   └── workflow_test.go          # Workflow tests
└── fixtures/                     # Test data fixtures
    └── products.go

# Inside main codebase (unit tests)
internal/
├── core/product/
│   ├── product.go
│   └── product_test.go           # Unit tests for domain
├── services/product/
│   ├── service.go
│   └── service_test.go           # Unit tests with mocks
└── handlers/
    ├── http/
    │   └── product_test.go       # Handler unit tests
    └── grpc/
        └── handlers_test.go
```

## Unit Testing Patterns

### Domain Entity Tests

```go
// internal/core/product/product_test.go
package product_test

import (
    "testing"
    "time"

    "github.com/shopspring/decimal"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"

    "{{module}}/internal/core/product"
)

func TestProduct_IsActive(t *testing.T) {
    tests := []struct {
        name     string
        status   product.Status
        expected bool
    }{
        {"active product", product.StatusActive, true},
        {"inactive product", product.StatusInactive, false},
        {"deleted product", product.StatusDeleted, false},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            p := &product.Product{Status: tt.status}
            assert.Equal(t, tt.expected, p.IsActive())
        })
    }
}

func TestProduct_Validate(t *testing.T) {
    tests := []struct {
        name    string
        product *product.Product
        wantErr bool
    }{
        {
            name: "valid product",
            product: &product.Product{
                ID:       "prod-123",
                Name:     "Widget",
                Price:    decimal.NewFromFloat(19.99),
                Quantity: 10,
                Status:   product.StatusActive,
            },
            wantErr: false,
        },
        {
            name: "empty name",
            product: &product.Product{
                ID:       "prod-123",
                Name:     "",
                Price:    decimal.NewFromFloat(19.99),
                Quantity: 10,
            },
            wantErr: true,
        },
        {
            name: "negative price",
            product: &product.Product{
                ID:       "prod-123",
                Name:     "Widget",
                Price:    decimal.NewFromFloat(-10),
                Quantity: 10,
            },
            wantErr: true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            err := tt.product.Validate()
            if tt.wantErr {
                require.Error(t, err)
            } else {
                require.NoError(t, err)
            }
        })
    }
}
```

### Service Tests with Mocks

```go
// internal/services/product/service_test.go
package product_test

import (
    "context"
    "testing"

    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/mock"
    "github.com/stretchr/testify/require"

    productcore "{{module}}/internal/core/product"
    "{{module}}/internal/services/product"
)

// MockRepository is a mock implementation of the product repository.
type MockRepository struct {
    mock.Mock
}

func (m *MockRepository) Create(ctx context.Context, p *productcore.Product) error {
    args := m.Called(ctx, p)
    return args.Error(0)
}

func (m *MockRepository) GetByID(ctx context.Context, id string) (*productcore.Product, error) {
    args := m.Called(ctx, id)
    if args.Get(0) == nil {
        return nil, args.Error(1)
    }
    return args.Get(0).(*productcore.Product), args.Error(1)
}

func (m *MockRepository) List(ctx context.Context, limit, offset int) ([]*productcore.Product, error) {
    args := m.Called(ctx, limit, offset)
    return args.Get(0).([]*productcore.Product), args.Error(1)
}

func (m *MockRepository) Update(ctx context.Context, p *productcore.Product) error {
    args := m.Called(ctx, p)
    return args.Error(0)
}

func (m *MockRepository) Delete(ctx context.Context, id string) error {
    args := m.Called(ctx, id)
    return args.Error(0)
}

func TestProductService_Create(t *testing.T) {
    ctx := context.Background()
    mockRepo := new(MockRepository)
    svc := product.NewDefaultService(mockRepo)

    t.Run("successful creation", func(t *testing.T) {
        input := &product.CreateInput{
            Name:        "Widget",
            Description: "A fine widget",
            Price:       decimal.NewFromFloat(19.99),
            Quantity:    10,
        }

        mockRepo.On("Create", ctx, mock.AnythingOfType("*product.Product")).
            Return(nil).Once()

        p, err := svc.Create(ctx, input)

        require.NoError(t, err)
        assert.NotEmpty(t, p.ID)
        assert.Equal(t, "Widget", p.Name)
        assert.Equal(t, productcore.StatusActive, p.Status)
        mockRepo.AssertExpectations(t)
    })

    t.Run("validation error", func(t *testing.T) {
        input := &product.CreateInput{
            Name: "", // Invalid: empty name
        }

        p, err := svc.Create(ctx, input)

        require.Error(t, err)
        assert.Nil(t, p)
        // Repository should not be called for invalid input
        mockRepo.AssertNotCalled(t, "Create")
    })
}

func TestProductService_GetByID(t *testing.T) {
    ctx := context.Background()
    mockRepo := new(MockRepository)
    svc := product.NewDefaultService(mockRepo)

    t.Run("found", func(t *testing.T) {
        expected := &productcore.Product{
            ID:   "prod-123",
            Name: "Widget",
        }
        mockRepo.On("GetByID", ctx, "prod-123").
            Return(expected, nil).Once()

        p, err := svc.GetByID(ctx, "prod-123")

        require.NoError(t, err)
        assert.Equal(t, expected, p)
        mockRepo.AssertExpectations(t)
    })

    t.Run("not found", func(t *testing.T) {
        mockRepo.On("GetByID", ctx, "nonexistent").
            Return(nil, productcore.ErrNotFound).Once()

        p, err := svc.GetByID(ctx, "nonexistent")

        require.ErrorIs(t, err, productcore.ErrNotFound)
        assert.Nil(t, p)
        mockRepo.AssertExpectations(t)
    })
}
```

## Infrastructure Suite Pattern

### Infrastructure Controller

```go
// test/infra/suite.go
package infra

import (
    "context"
    "path/filepath"
    "testing"
    "time"

    "github.com/stretchr/testify/require"
    "google.golang.org/grpc"

    pb "{{module}}/api/proto/product/v1"
)

// Config holds configuration for the test infrastructure.
type Config struct {
    ComposeFile    string
    ProjectName    string
    ServiceAddress string
    WaitTimeout    time.Duration
}

// Infrastructure manages the complete test infrastructure.
type Infrastructure struct {
    t             *testing.T
    config        Config
    dockerCompose *DockerCompose
    grpcConn      *grpc.ClientConn
    grpcClient    pb.ProductServiceClient
}

// New creates and initializes a new test infrastructure.
func New(t *testing.T, config Config) *Infrastructure {
    t.Helper()

    // Set defaults
    if config.WaitTimeout == 0 {
        config.WaitTimeout = 120 * time.Second
    }
    if config.ServiceAddress == "" {
        config.ServiceAddress = "localhost:50051"
    }

    // Resolve compose file path
    composeFilePath, err := filepath.Abs(config.ComposeFile)
    require.NoError(t, err, "failed to resolve compose file path")

    infra := &Infrastructure{
        t:             t,
        config:        config,
        dockerCompose: NewDockerCompose(composeFilePath, config.ProjectName),
    }

    infra.setup()
    return infra
}

func (i *Infrastructure) setup() {
    i.t.Helper()
    ctx := context.Background()

    i.t.Log("Starting docker-compose stack...")
    err := i.dockerCompose.Up()
    require.NoError(i.t, err, "failed to start docker-compose")

    i.t.Logf("Waiting for service at %s to be ready...", i.config.ServiceAddress)
    err = WaitForGRPCService(ctx, i.config.ServiceAddress, i.config.WaitTimeout)
    require.NoError(i.t, err, "service did not become ready in time")

    i.t.Log("Creating gRPC client connection...")
    i.grpcConn, err = grpc.NewClient(
        i.config.ServiceAddress,
        grpc.WithTransportCredentials(insecure.NewCredentials()),
    )
    require.NoError(i.t, err, "failed to create gRPC connection")

    i.grpcClient = pb.NewProductServiceClient(i.grpcConn)
    i.t.Log("Infrastructure setup completed successfully")
}

// Teardown cleans up the infrastructure.
func (i *Infrastructure) Teardown() {
    i.t.Helper()
    i.t.Log("Tearing down infrastructure...")

    if i.grpcConn != nil {
        if err := i.grpcConn.Close(); err != nil {
            i.t.Logf("Warning: failed to close gRPC connection: %v", err)
        }
    }

    if err := i.dockerCompose.Down(); err != nil {
        i.t.Logf("Warning: failed to stop docker-compose: %v", err)
    }

    i.t.Log("Infrastructure teardown completed")
}

// GRPCClient returns the gRPC client.
func (i *Infrastructure) GRPCClient() pb.ProductServiceClient {
    return i.grpcClient
}
```

### Docker Compose Management

```go
// test/infra/docker.go
package infra

import (
    "bytes"
    "context"
    "fmt"
    "os"
    "os/exec"
    "time"
)

// DockerCompose manages Docker Compose operations.
type DockerCompose struct {
    composeFile string
    projectName string
}

// NewDockerCompose creates a new Docker Compose manager.
func NewDockerCompose(composeFile, projectName string) *DockerCompose {
    return &DockerCompose{
        composeFile: composeFile,
        projectName: projectName,
    }
}

// Up starts the docker-compose stack.
func (d *DockerCompose) Up() error {
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
    defer cancel()

    cmd := exec.CommandContext(ctx, "docker", "compose",
        "-f", d.composeFile,
        "-p", d.projectName,
        "up", "-d", "--build", "--remove-orphans",
    )

    var stderr bytes.Buffer
    cmd.Stdout = os.Stdout
    cmd.Stderr = &stderr

    if err := cmd.Run(); err != nil {
        return fmt.Errorf("docker compose up failed: %w, stderr: %s", err, stderr.String())
    }

    return nil
}

// Down stops and removes the docker-compose stack.
func (d *DockerCompose) Down() error {
    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
    defer cancel()

    cmd := exec.CommandContext(ctx, "docker", "compose",
        "-f", d.composeFile,
        "-p", d.projectName,
        "down", "-v", "--remove-orphans",
    )

    var stderr bytes.Buffer
    cmd.Stdout = os.Stdout
    cmd.Stderr = &stderr

    if err := cmd.Run(); err != nil {
        return fmt.Errorf("docker compose down failed: %w, stderr: %s", err, stderr.String())
    }

    return nil
}

// Logs retrieves logs from a specific service.
func (d *DockerCompose) Logs(service string) (string, error) {
    cmd := exec.Command("docker", "compose",
        "-f", d.composeFile,
        "-p", d.projectName,
        "logs", service,
    )

    output, err := cmd.Output()
    if err != nil {
        return "", fmt.Errorf("failed to get logs: %w", err)
    }

    return string(output), nil
}
```

### Service Readiness Waiting

```go
// test/infra/wait.go
package infra

import (
    "context"
    "fmt"
    "net"
    "time"

    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
    "google.golang.org/grpc/health/grpc_health_v1"
)

// WaitForGRPCService waits for a gRPC service to be ready.
func WaitForGRPCService(ctx context.Context, address string, timeout time.Duration) error {
    ctx, cancel := context.WithTimeout(ctx, timeout)
    defer cancel()

    ticker := time.NewTicker(2 * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ctx.Done():
            return fmt.Errorf("timeout waiting for service at %s", address)
        case <-ticker.C:
            if err := checkGRPCHealth(ctx, address); err == nil {
                return nil
            }
        }
    }
}

func checkGRPCHealth(ctx context.Context, address string) error {
    // First check if port is open
    conn, err := net.DialTimeout("tcp", address, 2*time.Second)
    if err != nil {
        return fmt.Errorf("port not open: %w", err)
    }
    _ = conn.Close()

    // Then check gRPC health
    grpcConn, err := grpc.NewClient(
        address,
        grpc.WithTransportCredentials(insecure.NewCredentials()),
    )
    if err != nil {
        return fmt.Errorf("failed to create grpc client: %w", err)
    }
    defer grpcConn.Close()

    healthClient := grpc_health_v1.NewHealthClient(grpcConn)
    resp, err := healthClient.Check(ctx, &grpc_health_v1.HealthCheckRequest{})
    if err != nil {
        return fmt.Errorf("health check failed: %w", err)
    }

    if resp.Status != grpc_health_v1.HealthCheckResponse_SERVING {
        return fmt.Errorf("service not serving: %s", resp.Status)
    }

    return nil
}

// WaitForHTTPService waits for an HTTP service to be ready.
func WaitForHTTPService(ctx context.Context, url string, timeout time.Duration) error {
    ctx, cancel := context.WithTimeout(ctx, timeout)
    defer cancel()

    ticker := time.NewTicker(2 * time.Second)
    defer ticker.Stop()

    client := &http.Client{Timeout: 5 * time.Second}

    for {
        select {
        case <-ctx.Done():
            return fmt.Errorf("timeout waiting for service at %s", url)
        case <-ticker.C:
            resp, err := client.Get(url)
            if err == nil && resp.StatusCode == http.StatusOK {
                _ = resp.Body.Close()
                return nil
            }
        }
    }
}
```

## Integration Test Suite

### Suite Setup

```go
// test/integration/suite.go
package integration

import (
    "testing"

    "{{module}}/test/infra"
    pb "{{module}}/api/proto/product/v1"
)

// IntegrationSuite provides integration test infrastructure.
type IntegrationSuite struct {
    t     *testing.T
    infra *infra.Infrastructure
}

// SetupIntegrationSuite creates a new integration test suite.
func SetupIntegrationSuite(t *testing.T) *IntegrationSuite {
    t.Helper()

    infrastructure := infra.New(t, infra.Config{
        ComposeFile:    "../../deployment/local/docker-compose.yml",
        ProjectName:    "integration-test",
        ServiceAddress: "localhost:50051",
    })

    return &IntegrationSuite{
        t:     t,
        infra: infrastructure,
    }
}

// Teardown cleans up the test suite.
func (s *IntegrationSuite) Teardown() {
    s.t.Helper()
    s.infra.Teardown()
}

// Client returns the gRPC client.
func (s *IntegrationSuite) Client() pb.ProductServiceClient {
    return s.infra.GRPCClient()
}
```

### Test Helpers

```go
// test/integration/helpers.go
package integration

import (
    "fmt"
    "testing"
    "time"

    "github.com/stretchr/testify/require"
    "google.golang.org/protobuf/types/known/structpb"
)

// generateTestID creates a unique test identifier to avoid collisions.
func generateTestID(prefix string) string {
    return fmt.Sprintf("%s-%d", prefix, time.Now().UnixNano())
}

// mustValue converts a Go value to a structpb.Value.
func mustValue(t *testing.T, v interface{}) *structpb.Value {
    t.Helper()
    val, err := structpb.NewValue(v)
    require.NoError(t, err, "failed to create structpb.Value")
    return val
}

// mustStruct converts a map to a structpb.Struct.
func mustStruct(t *testing.T, m map[string]interface{}) *structpb.Struct {
    t.Helper()
    s, err := structpb.NewStruct(m)
    require.NoError(t, err, "failed to create structpb.Struct")
    return s
}
```

### Integration Test Example

```go
// test/integration/product_test.go
//go:build integration

package integration

import (
    "context"
    "testing"

    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"

    pb "{{module}}/api/proto/product/v1"
)

func TestProduct_CRUD(t *testing.T) {
    suite := SetupIntegrationSuite(t)
    defer suite.Teardown()

    ctx := context.Background()
    client := suite.Client()

    var productID string

    t.Run("Create", func(t *testing.T) {
        productID = generateTestID("product")
        resp, err := client.CreateProduct(ctx, &pb.CreateProductRequest{
            Id:          productID,
            Name:        "Integration Test Product",
            Description: "A product for testing",
            Price:       19.99,
            Quantity:    100,
        })

        require.NoError(t, err)
        require.NotNil(t, resp)
        assert.Equal(t, productID, resp.Product.Id)
        assert.Equal(t, "Integration Test Product", resp.Product.Name)
        assert.Equal(t, pb.ProductStatus_PRODUCT_STATUS_ACTIVE, resp.Product.Status)
    })

    t.Run("Get", func(t *testing.T) {
        resp, err := client.GetProduct(ctx, &pb.GetProductRequest{
            Id: productID,
        })

        require.NoError(t, err)
        require.NotNil(t, resp)
        assert.Equal(t, productID, resp.Product.Id)
        assert.Equal(t, "Integration Test Product", resp.Product.Name)
    })

    t.Run("Update", func(t *testing.T) {
        resp, err := client.UpdateProduct(ctx, &pb.UpdateProductRequest{
            Id:   productID,
            Name: "Updated Product Name",
        })

        require.NoError(t, err)
        require.NotNil(t, resp)
        assert.Equal(t, "Updated Product Name", resp.Product.Name)
    })

    t.Run("List", func(t *testing.T) {
        resp, err := client.ListProducts(ctx, &pb.ListProductsRequest{
            PageSize: 10,
        })

        require.NoError(t, err)
        require.NotNil(t, resp)
        assert.GreaterOrEqual(t, len(resp.Products), 1)
    })

    t.Run("Delete", func(t *testing.T) {
        _, err := client.DeleteProduct(ctx, &pb.DeleteProductRequest{
            Id: productID,
        })
        require.NoError(t, err)

        // Verify deletion (soft delete - status changed)
        resp, err := client.GetProduct(ctx, &pb.GetProductRequest{
            Id: productID,
        })
        require.NoError(t, err)
        assert.Equal(t, pb.ProductStatus_PRODUCT_STATUS_DELETED, resp.Product.Status)
    })
}

func TestProduct_NotFound(t *testing.T) {
    suite := SetupIntegrationSuite(t)
    defer suite.Teardown()

    ctx := context.Background()
    client := suite.Client()

    _, err := client.GetProduct(ctx, &pb.GetProductRequest{
        Id: "nonexistent-product-id",
    })

    require.Error(t, err)
    // Check for NOT_FOUND status code
    assert.Contains(t, err.Error(), "NotFound")
}
```

## E2E Test Suite

### E2E Suite Setup

```go
// test/e2e/suite.go
//go:build e2e

package e2e

import (
    "context"
    "testing"
    "time"

    "{{module}}/test/infra"
    pb "{{module}}/api/proto/product/v1"
)

// E2ESuite provides E2E test infrastructure.
type E2ESuite struct {
    t     *testing.T
    infra *infra.Infrastructure
}

// SetupE2ESuite creates a new E2E test suite.
func SetupE2ESuite(t *testing.T) *E2ESuite {
    t.Helper()

    // E2E tests use a separate compose file with all dependencies
    infrastructure := infra.New(t, infra.Config{
        ComposeFile:    "../../deployment/local/docker-compose.test.yml",
        ProjectName:    "e2e-test",
        ServiceAddress: "localhost:50051",
        WaitTimeout:    180 * time.Second, // Longer timeout for full stack
    })

    return &E2ESuite{
        t:     t,
        infra: infrastructure,
    }
}

// Teardown cleans up the test suite.
func (s *E2ESuite) Teardown() {
    s.t.Helper()
    s.infra.Teardown()
}

// Client returns the gRPC client.
func (s *E2ESuite) Client() pb.ProductServiceClient {
    return s.infra.GRPCClient()
}

// WaitForCondition polls until a condition is met or timeout.
func (s *E2ESuite) WaitForCondition(
    ctx context.Context,
    timeout time.Duration,
    check func() (bool, error),
) error {
    ctx, cancel := context.WithTimeout(ctx, timeout)
    defer cancel()

    ticker := time.NewTicker(500 * time.Millisecond)
    defer ticker.Stop()

    for {
        select {
        case <-ctx.Done():
            return ctx.Err()
        case <-ticker.C:
            done, err := check()
            if err != nil {
                return err
            }
            if done {
                return nil
            }
        }
    }
}
```

### E2E Test Example

```go
// test/e2e/product_workflow_test.go
//go:build e2e

package e2e

import (
    "context"
    "testing"
    "time"

    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"

    pb "{{module}}/api/proto/product/v1"
)

func TestProductWorkflow_FullLifecycle(t *testing.T) {
    suite := SetupE2ESuite(t)
    defer suite.Teardown()

    ctx := context.Background()
    client := suite.Client()

    productID := generateTestID("e2e-product")

    // Step 1: Create product
    t.Run("Step 1: Create product", func(t *testing.T) {
        resp, err := client.CreateProduct(ctx, &pb.CreateProductRequest{
            Id:          productID,
            Name:        "E2E Test Product",
            Description: "Complete lifecycle test",
            Price:       99.99,
            Quantity:    50,
        })
        require.NoError(t, err)
        assert.Equal(t, pb.ProductStatus_PRODUCT_STATUS_ACTIVE, resp.Product.Status)
    })

    // Step 2: Update inventory
    t.Run("Step 2: Update inventory", func(t *testing.T) {
        resp, err := client.UpdateProduct(ctx, &pb.UpdateProductRequest{
            Id:       productID,
            Quantity: 25, // Reduced inventory
        })
        require.NoError(t, err)
        assert.Equal(t, int32(25), resp.Product.Quantity)
    })

    // Step 3: Deactivate product
    t.Run("Step 3: Deactivate product", func(t *testing.T) {
        resp, err := client.UpdateProduct(ctx, &pb.UpdateProductRequest{
            Id:     productID,
            Status: pb.ProductStatus_PRODUCT_STATUS_INACTIVE,
        })
        require.NoError(t, err)
        assert.Equal(t, pb.ProductStatus_PRODUCT_STATUS_INACTIVE, resp.Product.Status)
    })

    // Step 4: Verify in list (should be excluded from active list)
    t.Run("Step 4: Verify not in active list", func(t *testing.T) {
        resp, err := client.ListProducts(ctx, &pb.ListProductsRequest{
            PageSize:   100,
            StatusFilter: pb.ProductStatus_PRODUCT_STATUS_ACTIVE,
        })
        require.NoError(t, err)

        for _, p := range resp.Products {
            assert.NotEqual(t, productID, p.Id, "Inactive product should not appear in active list")
        }
    })

    // Step 5: Delete product
    t.Run("Step 5: Delete product", func(t *testing.T) {
        _, err := client.DeleteProduct(ctx, &pb.DeleteProductRequest{Id: productID})
        require.NoError(t, err)
    })

    // Step 6: Verify final state
    t.Run("Step 6: Verify final state", func(t *testing.T) {
        resp, err := client.GetProduct(ctx, &pb.GetProductRequest{Id: productID})
        require.NoError(t, err)
        assert.Equal(t, pb.ProductStatus_PRODUCT_STATUS_DELETED, resp.Product.Status)
    })
}
```

## Docker Compose for Tests

### Test Docker Compose File

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
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=postgres
      - DB_PASSWORD=postgres
      - DB_NAME=testdb
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - LOG_LEVEL=debug
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

## Makefile Targets

```makefile
# Test targets
.PHONY: test test-unit test-integration test-e2e test-coverage

# Run all unit tests
test-unit:
	@echo "Running unit tests..."
	go test -v -race ./internal/...

# Run integration tests (requires docker)
test-integration:
	@echo "Running integration tests..."
	go test -v -tags=integration -timeout 5m ./test/integration/...

# Run E2E tests (requires docker)
test-e2e:
	@echo "Running E2E tests..."
	go test -v -tags=e2e -timeout 10m ./test/e2e/...

# Run all tests
test: test-unit test-integration test-e2e

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
	docker compose -f deployment/local/docker-compose.test.yml -p test down -v
```

## Best Practices

### Test Isolation
- Use unique IDs per test: `generateTestID("prefix")`
- Clean up test data in teardown
- Use separate Docker Compose projects per test suite

### Test Organization
- Unit tests: Same package as code under test
- Integration tests: `test/integration/` with build tag
- E2E tests: `test/e2e/` with build tag

### Build Tags
```go
//go:build integration

package integration
```

Run with: `go test -tags=integration ./...`

### Parallel Tests
```go
func TestSomething(t *testing.T) {
    t.Parallel() // Enable parallel execution
    // ... test code
}
```

### Table-Driven Tests
```go
func TestFunction(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    string
        wantErr bool
    }{
        {"case 1", "input1", "output1", false},
        {"case 2", "input2", "output2", false},
        {"error case", "bad", "", true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := Function(tt.input)
            if tt.wantErr {
                require.Error(t, err)
                return
            }
            require.NoError(t, err)
            assert.Equal(t, tt.want, got)
        })
    }
}
```
