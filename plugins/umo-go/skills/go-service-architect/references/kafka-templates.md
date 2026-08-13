# Kafka Templates

Complete templates for Kafka event publishing and consuming using Sarama and devkit/common patterns.

## Table of Contents

1. [Directory Structure](#1-directory-structure)
2. [Publisher Interface](#2-publisher-interface)
3. [Kafka Producer Implementation](#3-kafka-producer-implementation)
4. [Instrumented Publisher Wrapper](#4-instrumented-publisher-wrapper)
5. [Configuration](#5-configuration)
6. [Fx Module Wiring](#6-fx-module-wiring)
7. [Consumer Patterns](#7-consumer-patterns)
8. [Message Serialization](#8-message-serialization)
9. [Topic Naming Conventions](#9-topic-naming-conventions)
10. [Testing Kafka Publishers](#10-testing-kafka-publishers)

---

## 1. Directory Structure

Kafka components follow the 3-file pattern for publishers:

```
internal/
├── publisher/                   # Event publishers (3-file pattern)
│   ├── publisher.go            # Interface definition (port)
│   ├── instrumented.go         # Observability wrapper using devkit/common
│   └── kafka/                  # Kafka adapter
│       └── publisher.go        # Sarama SyncProducer implementation
├── handlers/
│   └── kafka/                  # Kafka consumers
│       └── handler.go          # Consumer message handlers
└── di/
    └── kafka/
        └── module.go           # Fx DI module for Kafka
```

**Pattern benefits:**
- **Separation of concerns**: Interface defines contract, Kafka implementation handles connection, wrapper adds observability
- **Testability**: Mock the publisher interface in tests
- **Graceful degradation**: Service works when Kafka is disabled
- **Automatic instrumentation**: All publishes get tracing and logging

---

## 2. Publisher Interface

The interface defines the contract for event publishing. Keep it focused on domain events.

```go
// internal/publisher/publisher.go
package publisher

import (
    "context"

    "your-service/internal/core/order"
    "your-service/internal/core/user"
)

// Publisher defines the interface for publishing domain events.
// This interface should contain methods for each event type your service publishes.
type Publisher interface {
    // SendOrderCreatedEvent publishes an order created event.
    SendOrderCreatedEvent(ctx context.Context, tenantID string, order *order.Order) error

    // SendOrderCompletedEvent publishes an order completed event.
    SendOrderCompletedEvent(ctx context.Context, tenantID string, order *order.Order) error

    // SendUserRegisteredEvent publishes a user registered event.
    SendUserRegisteredEvent(ctx context.Context, tenantID string, user *user.User) error

    // Close closes the publisher connection.
    Close() error
}

// Event represents a generic event structure.
type Event struct {
    Name      string      // Event name (e.g., "order.created", "user.registered")
    TenantID  string      // Tenant identifier for multi-tenant systems
    EntityID  string      // Entity ID (used as message key for partitioning)
    Payload   interface{} // Event payload (serialized to protobuf/JSON)
}
```

**Key principles:**
- Define domain-specific event methods, not generic `Publish(event)`
- Use domain types, not proto types in the interface
- Include `Close()` method for cleanup
- Pass `tenantID` for multi-tenant topic routing

---

## 3. Kafka Producer Implementation

The Kafka publisher handles the actual Sarama producer and message serialization.

```go
// internal/publisher/kafka/publisher.go
package kafka

import (
    "context"
    "fmt"

    "github.com/IBM/sarama"
    "google.golang.org/protobuf/proto"

    pb "your-service/api/proto/events/v1"
    "your-service/internal/core/order"
    "your-service/internal/core/user"
    "your-service/internal/publisher/kafka/protomap"
)

// Publisher is the Kafka implementation of the publisher.Publisher interface.
type Publisher struct {
    producer sarama.SyncProducer
}

// NewPublisher creates a new Kafka publisher.
func NewPublisher(producer sarama.SyncProducer) *Publisher {
    return &Publisher{
        producer: producer,
    }
}

// SendOrderCreatedEvent publishes an order created event.
func (p *Publisher) SendOrderCreatedEvent(ctx context.Context, tenantID string, o *order.Order) error {
    event := &pb.OrderEvent{
        Event: "order.created",
        Data:  protomap.OrderToProto(o),
    }

    return p.publish(ctx, tenantID, o.ID, "order.events", event)
}

// SendOrderCompletedEvent publishes an order completed event.
func (p *Publisher) SendOrderCompletedEvent(ctx context.Context, tenantID string, o *order.Order) error {
    event := &pb.OrderEvent{
        Event: "order.completed",
        Data:  protomap.OrderToProto(o),
    }

    return p.publish(ctx, tenantID, o.ID, "order.events", event)
}

// SendUserRegisteredEvent publishes a user registered event.
func (p *Publisher) SendUserRegisteredEvent(ctx context.Context, tenantID string, u *user.User) error {
    event := &pb.UserEvent{
        Event: "user.registered",
        Data:  protomap.UserToProto(u),
    }

    return p.publish(ctx, tenantID, u.ID, "user.events", event)
}

// Close closes the Kafka producer.
func (p *Publisher) Close() error {
    return p.producer.Close()
}

// publish sends a message to both tenant-specific and global topics.
func (p *Publisher) publish(ctx context.Context, tenantID, entityID, eventType string, event proto.Message) error {
    // Serialize protobuf message
    payload, err := proto.Marshal(event)
    if err != nil {
        return fmt.Errorf("failed to marshal event: %w", err)
    }

    // Publish to tenant-specific topic
    tenantTopic := buildTenantTopic(tenantID, eventType)
    if err := p.sendMessage(tenantTopic, entityID, payload); err != nil {
        return fmt.Errorf("failed to publish to tenant topic: %w", err)
    }

    // Publish to global topic (for cross-tenant consumers)
    globalTopic := buildGlobalTopic(eventType)
    if err := p.sendMessage(globalTopic, entityID, payload); err != nil {
        return fmt.Errorf("failed to publish to global topic: %w", err)
    }

    return nil
}

// sendMessage sends a single message to Kafka.
func (p *Publisher) sendMessage(topic, key string, value []byte) error {
    msg := &sarama.ProducerMessage{
        Topic: topic,
        Key:   sarama.StringEncoder(key),
        Value: sarama.ByteEncoder(value),
    }

    _, _, err := p.producer.SendMessage(msg)
    return err
}

// buildTenantTopic builds a tenant-specific topic name.
func buildTenantTopic(tenantID, eventType string) string {
    return fmt.Sprintf("saas.myservice.t_%s.%s", tenantID, eventType)
}

// buildGlobalTopic builds a global topic name.
func buildGlobalTopic(eventType string) string {
    return fmt.Sprintf("saas.myservice.%s", eventType)
}
```

---

## 4. Instrumented Publisher Wrapper

The instrumented wrapper adds tracing and logging using devkit/common.

```go
// internal/publisher/instrumented.go
package publisher

import (
    "context"
    "time"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/observability/trace"

    "your-service/internal/core/order"
    "your-service/internal/core/user"
)

// InstrumentedPublisher wraps a Publisher with tracing and logging.
type InstrumentedPublisher struct {
    inner Publisher
    log   logger.Logger
}

// NewInstrumentedPublisher creates a new instrumented publisher wrapper.
func NewInstrumentedPublisher(inner Publisher, log logger.Logger) *InstrumentedPublisher {
    return &InstrumentedPublisher{
        inner: inner,
        log:   log.Named("publisher"),
    }
}

// SendOrderCreatedEvent publishes an order created event with instrumentation.
func (p *InstrumentedPublisher) SendOrderCreatedEvent(ctx context.Context, tenantID string, o *order.Order) error {
    start := time.Now()

    // Create span for this publish operation
    ctx, span := trace.Instrument(ctx, p.inner.SendOrderCreatedEvent)
    defer span.End()

    // Add business-specific attributes
    span.SetAttributes(
        trace.String("event.name", "order.created"),
        trace.String("event.tenant_id", tenantID),
        trace.String("order.id", o.ID),
        trace.String("messaging.system", "kafka"),
        trace.String("messaging.destination_kind", "topic"),
    )

    p.log.Debug(ctx, "publishing order created event",
        logger.String("event", "order.created"),
        logger.String("tenant_id", tenantID),
        logger.String("order_id", o.ID),
    )

    // Publish the event
    err := p.inner.SendOrderCreatedEvent(ctx, tenantID, o)

    duration := time.Since(start)
    span.SetAttributes(trace.Float64("duration_seconds", duration.Seconds()))

    if err != nil {
        span.RecordError(err)
        span.SetStatus(trace.StatusError, "failed to publish order created event")
        p.log.Error(ctx, "failed to publish order created event",
            logger.String("event", "order.created"),
            logger.String("tenant_id", tenantID),
            logger.String("order_id", o.ID),
            logger.Err(err),
            logger.Duration("duration", duration),
        )
        return err
    }

    span.SetStatus(trace.StatusOK, "event published")
    p.log.Info(ctx, "order created event published",
        logger.String("event", "order.created"),
        logger.String("tenant_id", tenantID),
        logger.String("order_id", o.ID),
        logger.Duration("duration", duration),
    )

    return nil
}

// SendOrderCompletedEvent publishes an order completed event with instrumentation.
func (p *InstrumentedPublisher) SendOrderCompletedEvent(ctx context.Context, tenantID string, o *order.Order) error {
    start := time.Now()

    ctx, span := trace.Instrument(ctx, p.inner.SendOrderCompletedEvent)
    defer span.End()

    span.SetAttributes(
        trace.String("event.name", "order.completed"),
        trace.String("event.tenant_id", tenantID),
        trace.String("order.id", o.ID),
        trace.String("messaging.system", "kafka"),
    )

    p.log.Debug(ctx, "publishing order completed event",
        logger.String("event", "order.completed"),
        logger.String("tenant_id", tenantID),
        logger.String("order_id", o.ID),
    )

    err := p.inner.SendOrderCompletedEvent(ctx, tenantID, o)

    duration := time.Since(start)
    span.SetAttributes(trace.Float64("duration_seconds", duration.Seconds()))

    if err != nil {
        span.RecordError(err)
        span.SetStatus(trace.StatusError, "failed to publish order completed event")
        p.log.Error(ctx, "failed to publish order completed event",
            logger.String("event", "order.completed"),
            logger.Err(err),
            logger.Duration("duration", duration),
        )
        return err
    }

    span.SetStatus(trace.StatusOK, "event published")
    p.log.Info(ctx, "order completed event published",
        logger.String("event", "order.completed"),
        logger.String("order_id", o.ID),
        logger.Duration("duration", duration),
    )

    return nil
}

// SendUserRegisteredEvent publishes a user registered event with instrumentation.
func (p *InstrumentedPublisher) SendUserRegisteredEvent(ctx context.Context, tenantID string, u *user.User) error {
    start := time.Now()

    ctx, span := trace.Instrument(ctx, p.inner.SendUserRegisteredEvent)
    defer span.End()

    span.SetAttributes(
        trace.String("event.name", "user.registered"),
        trace.String("event.tenant_id", tenantID),
        trace.String("user.id", u.ID),
        trace.String("messaging.system", "kafka"),
    )

    p.log.Debug(ctx, "publishing user registered event",
        logger.String("event", "user.registered"),
        logger.String("tenant_id", tenantID),
        logger.String("user_id", u.ID),
    )

    err := p.inner.SendUserRegisteredEvent(ctx, tenantID, u)

    duration := time.Since(start)
    span.SetAttributes(trace.Float64("duration_seconds", duration.Seconds()))

    if err != nil {
        span.RecordError(err)
        span.SetStatus(trace.StatusError, "failed to publish user registered event")
        p.log.Error(ctx, "failed to publish user registered event",
            logger.String("event", "user.registered"),
            logger.Err(err),
            logger.Duration("duration", duration),
        )
        return err
    }

    span.SetStatus(trace.StatusOK, "event published")
    p.log.Info(ctx, "user registered event published",
        logger.String("event", "user.registered"),
        logger.String("user_id", u.ID),
        logger.Duration("duration", duration),
    )

    return nil
}

// Close closes the underlying publisher.
func (p *InstrumentedPublisher) Close() error {
    return p.inner.Close()
}
```

---

## 5. Configuration

### Configuration Struct

```go
// internal/config/configuration.go
package config

// Add to your Configuration struct:

type Configuration struct {
    // ... other fields ...

    Kafka KafkaConfig `mapstructure:"kafka"`
}

// KafkaConfig holds Kafka-specific configuration.
type KafkaConfig struct {
    // Brokers is a list of Kafka broker addresses.
    Brokers []string `mapstructure:"brokers"`

    // ConsumerGroup is the consumer group name for this service.
    ConsumerGroup string `mapstructure:"consumer_group"`

    // Enabled controls whether Kafka is enabled.
    // When false, publisher operations are no-ops.
    Enabled bool `mapstructure:"enabled"`

    // Producer configuration
    Producer ProducerConfig `mapstructure:"producer"`
}

// ProducerConfig holds Kafka producer-specific configuration.
type ProducerConfig struct {
    // RequiredAcks specifies the number of acknowledgments required.
    // -1 = WaitForAll (recommended for reliability)
    RequiredAcks int `mapstructure:"required_acks"`

    // RetryMax is the maximum number of retries for failed sends.
    RetryMax int `mapstructure:"retry_max"`

    // RetryBackoff is the backoff duration between retries.
    RetryBackoff time.Duration `mapstructure:"retry_backoff"`
}
```

### Configuration Defaults

```go
// Add to defaults() function:

func defaults() map[string]any {
    return map[string]any{
        // ... other defaults ...

        // Kafka defaults
        "kafka.brokers":                []string{"localhost:9092"},
        "kafka.consumer_group":         "myservice",
        "kafka.enabled":                true,
        "kafka.producer.required_acks": -1,  // WaitForAll
        "kafka.producer.retry_max":     5,
        "kafka.producer.retry_backoff": "100ms",
    }
}
```

### Configuration YAML

```yaml
# config/configuration.yaml

kafka:
  brokers:
    - localhost:9092
  consumer_group: myservice
  enabled: true
  producer:
    required_acks: -1  # WaitForAll
    retry_max: 5
    retry_backoff: 100ms
```

### Environment Variables

```bash
# Override via environment variables
MYSERVICE_KAFKA_BROKERS=broker1:9092,broker2:9092
MYSERVICE_KAFKA_CONSUMER_GROUP=myservice
MYSERVICE_KAFKA_ENABLED=true
```

---

## 6. Fx Module Wiring

### Kafka DI Module

```go
// internal/di/kafka/module.go
package kafka

import (
    "context"
    "fmt"
    "time"

    "github.com/IBM/sarama"
    "go.uber.org/fx"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/platformfx"

    "your-service/internal/config"
    "your-service/internal/publisher"
    kafkapublisher "your-service/internal/publisher/kafka"
)

// Module provides Kafka components as an Fx module.
var Module = fx.Module("kafka",
    // Provide Sarama producer
    fx.Provide(NewKafkaProducer),

    // Provide Kafka publisher implementation
    fx.Provide(NewKafkaPublisher),

    // Provide instrumented publisher interface
    fx.Provide(NewInstrumentedPublisher),

    // Register shutdown hook
    platformfx.ProvideShutdownHook(NewKafkaShutdownHook),
)

// KafkaProducerResult holds the producer result.
type KafkaProducerResult struct {
    fx.Out
    Producer sarama.SyncProducer `optional:"true"`
}

// NewKafkaProducer creates a new Sarama SyncProducer.
// Returns nil when Kafka is disabled (graceful degradation).
func NewKafkaProducer(cfg *config.Configuration, log logger.Logger) (KafkaProducerResult, error) {
    // Graceful disable - return nil producer when Kafka is disabled
    if !cfg.Kafka.Enabled {
        log.Info(context.Background(), "Kafka is disabled, skipping producer creation")
        return KafkaProducerResult{}, nil
    }

    // Configure Sarama producer
    saramaConfig := sarama.NewConfig()

    // Producer settings for reliability
    switch cfg.Kafka.Producer.RequiredAcks {
    case -1:
        saramaConfig.Producer.RequiredAcks = sarama.WaitForAll
    case 0:
        saramaConfig.Producer.RequiredAcks = sarama.NoResponse
    case 1:
        saramaConfig.Producer.RequiredAcks = sarama.WaitForLocal
    default:
        saramaConfig.Producer.RequiredAcks = sarama.WaitForAll
    }

    saramaConfig.Producer.Retry.Max = cfg.Kafka.Producer.RetryMax
    saramaConfig.Producer.Retry.Backoff = cfg.Kafka.Producer.RetryBackoff
    saramaConfig.Producer.Return.Successes = true
    saramaConfig.Producer.Return.Errors = true

    // Create sync producer
    producer, err := sarama.NewSyncProducer(cfg.Kafka.Brokers, saramaConfig)
    if err != nil {
        return KafkaProducerResult{}, fmt.Errorf("failed to create Kafka producer: %w", err)
    }

    log.Info(context.Background(), "Kafka producer created",
        logger.Strings("brokers", cfg.Kafka.Brokers),
    )

    return KafkaProducerResult{Producer: producer}, nil
}

// NewKafkaPublisher creates the Kafka publisher implementation.
// Returns nil when Kafka is disabled.
func NewKafkaPublisher(producer sarama.SyncProducer) *kafkapublisher.Publisher {
    if producer == nil {
        return nil
    }
    return kafkapublisher.NewPublisher(producer)
}

// NewInstrumentedPublisher creates the instrumented publisher interface.
// Returns nil when Kafka is disabled.
func NewInstrumentedPublisher(p *kafkapublisher.Publisher, log logger.Logger) publisher.Publisher {
    if p == nil {
        return nil
    }
    return publisher.NewInstrumentedPublisher(p, log)
}

// NewKafkaShutdownHook creates a shutdown hook for Kafka producer.
func NewKafkaShutdownHook(producer sarama.SyncProducer, log logger.Logger) platformfx.ShutdownHook {
    return platformfx.ClientHook("kafka-producer", func(ctx context.Context) error {
        if producer == nil {
            return nil
        }
        log.Info(ctx, "Closing Kafka producer")
        if err := producer.Close(); err != nil {
            log.Error(ctx, "Failed to close Kafka producer", logger.Err(err))
            return err
        }
        log.Info(ctx, "Kafka producer closed")
        return nil
    })
}
```

### Bootstrap Integration

```go
// cmd/serve.go

import (
    // ... other imports ...
    kafkadi "your-service/internal/di/kafka"
)

func runServeService() {
    cfg, meta, err := config.Load()
    // ...

    app := fx.New(
        // ... logger, platform, trace modules ...

        fx.Provide(func() *config.Configuration { return cfg }),

        // Infrastructure modules
        postgres.Module,
        kafkadi.Module,  // Add Kafka module

        // Transport modules
        httpdi.Module,
        grpcdi.Module,

        fx.Invoke(registerServiceLifecycle),
    )

    app.Run()
}
```

### Using Publisher in Services

```go
// internal/services/order/service.go
package order

import (
    "context"

    "your-service/internal/core/order"
    "your-service/internal/publisher"
)

type Service struct {
    repo      order.Repository
    publisher publisher.Publisher  // Injected via Fx
}

func NewService(repo order.Repository, pub publisher.Publisher) *Service {
    return &Service{
        repo:      repo,
        publisher: pub,
    }
}

func (s *Service) CreateOrder(ctx context.Context, tenantID string, items []order.Item) (*order.Order, error) {
    o := order.New(items)

    if err := s.repo.Save(ctx, o); err != nil {
        return nil, err
    }

    // Publish event (nil-safe - no-op when Kafka is disabled)
    if s.publisher != nil {
        if err := s.publisher.SendOrderCreatedEvent(ctx, tenantID, o); err != nil {
            // Log but don't fail - event publishing should not block order creation
            // Consider: add to retry queue, use transactional outbox pattern
        }
    }

    return o, nil
}
```

---

## 7. Consumer Patterns

> **Note**: Consumer patterns are less common but follow similar structure. Use Sarama's `ConsumerGroup` for reliable consumption.

### Consumer Handler Interface

```go
// internal/handlers/kafka/handler.go
package kafka

import (
    "context"

    "github.com/IBM/sarama"
)

// Handler processes Kafka messages.
type Handler interface {
    // Setup is run before consuming begins.
    Setup(sarama.ConsumerGroupSession) error

    // Cleanup is run after consuming ends.
    Cleanup(sarama.ConsumerGroupSession) error

    // ConsumeClaim processes messages from a partition.
    ConsumeClaim(sarama.ConsumerGroupSession, sarama.ConsumerGroupClaim) error
}

// OrderEventHandler handles order-related events.
type OrderEventHandler struct {
    // Inject services needed to process events
}

func (h *OrderEventHandler) Setup(session sarama.ConsumerGroupSession) error {
    return nil
}

func (h *OrderEventHandler) Cleanup(session sarama.ConsumerGroupSession) error {
    return nil
}

func (h *OrderEventHandler) ConsumeClaim(session sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
    for msg := range claim.Messages() {
        ctx := context.Background()

        // Process message
        if err := h.processMessage(ctx, msg); err != nil {
            // Handle error (log, retry, dead letter queue)
            continue
        }

        // Mark message as processed
        session.MarkMessage(msg, "")
    }
    return nil
}

func (h *OrderEventHandler) processMessage(ctx context.Context, msg *sarama.ConsumerMessage) error {
    // Deserialize and process
    return nil
}
```

### Consumer Fx Module

```go
// internal/di/kafka/consumer_module.go
package kafka

import (
    "context"

    "github.com/IBM/sarama"
    "go.uber.org/fx"

    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"

    "your-service/internal/config"
    kafkahandlers "your-service/internal/handlers/kafka"
)

// ConsumerModule provides Kafka consumer components.
var ConsumerModule = fx.Module("kafka-consumer",
    fx.Provide(NewConsumerGroup),
    fx.Invoke(StartConsumer),
)

func NewConsumerGroup(cfg *config.Configuration) (sarama.ConsumerGroup, error) {
    if !cfg.Kafka.Enabled {
        return nil, nil
    }

    config := sarama.NewConfig()
    config.Consumer.Group.Rebalance.Strategy = sarama.BalanceStrategyRoundRobin
    config.Consumer.Offsets.Initial = sarama.OffsetNewest

    return sarama.NewConsumerGroup(cfg.Kafka.Brokers, cfg.Kafka.ConsumerGroup, config)
}

func StartConsumer(
    lc fx.Lifecycle,
    group sarama.ConsumerGroup,
    handler *kafkahandlers.OrderEventHandler,
    cfg *config.Configuration,
    log logger.Logger,
) {
    if group == nil {
        return
    }

    topics := []string{"saas.myservice.order.events"}

    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            go func() {
                for {
                    if err := group.Consume(ctx, topics, handler); err != nil {
                        log.Error(ctx, "Consumer error", logger.Err(err))
                    }
                }
            }()
            return nil
        },
        OnStop: func(ctx context.Context) error {
            return group.Close()
        },
    })
}
```

---

## 8. Message Serialization

### Protobuf Events

```protobuf
// api/proto/events/v1/events.proto
syntax = "proto3";

package events.v1;

option go_package = "your-service/api/proto/events/v1;eventsv1";

import "google/protobuf/timestamp.proto";

// OrderEvent represents an order-related event.
message OrderEvent {
    string event = 1;           // Event name (e.g., "order.created")
    Order data = 2;             // Order payload
    google.protobuf.Timestamp timestamp = 3;
}

// Order is the order payload in events.
message Order {
    string id = 1;
    string user_id = 2;
    int64 total_price = 3;
    string status = 4;
    google.protobuf.Timestamp created_at = 5;
}

// UserEvent represents a user-related event.
message UserEvent {
    string event = 1;
    User data = 2;
    google.protobuf.Timestamp timestamp = 3;
}

// User is the user payload in events.
message User {
    string id = 1;
    string email = 2;
    string name = 3;
    google.protobuf.Timestamp created_at = 4;
}
```

### Proto Mapping

```go
// internal/publisher/kafka/protomap/order.go
package protomap

import (
    "google.golang.org/protobuf/types/known/timestamppb"

    pb "your-service/api/proto/events/v1"
    "your-service/internal/core/order"
)

// OrderToProto converts a domain order to proto.
func OrderToProto(o *order.Order) *pb.Order {
    return &pb.Order{
        Id:         o.ID,
        UserId:     o.UserID,
        TotalPrice: o.TotalPrice,
        Status:     string(o.Status),
        CreatedAt:  timestamppb.New(o.CreatedAt),
    }
}
```

---

## 9. Topic Naming Conventions

Follow a consistent naming convention for topics:

```
{namespace}.{service}.{scope}.{entity}.{event_type}
```

**Examples:**
- `saas.myservice.order.events` - Global order events
- `saas.myservice.t_tenant123.order.events` - Tenant-specific order events
- `saas.myservice.user.events` - Global user events

**Naming rules:**
1. Use lowercase with dots as separators
2. Include service name for identification
3. Use `t_{tenant_id}` prefix for tenant-specific topics
4. Group by entity type (order, user, payment)
5. End with event category (events, commands, queries)

---

## 10. Testing Kafka Publishers

### Mock Publisher

```go
// internal/publisher/mock_publisher.go
package publisher

import (
    "context"

    "github.com/stretchr/testify/mock"

    "your-service/internal/core/order"
    "your-service/internal/core/user"
)

// MockPublisher is a mock implementation of Publisher for testing.
type MockPublisher struct {
    mock.Mock
}

func (m *MockPublisher) SendOrderCreatedEvent(ctx context.Context, tenantID string, o *order.Order) error {
    args := m.Called(ctx, tenantID, o)
    return args.Error(0)
}

func (m *MockPublisher) SendOrderCompletedEvent(ctx context.Context, tenantID string, o *order.Order) error {
    args := m.Called(ctx, tenantID, o)
    return args.Error(0)
}

func (m *MockPublisher) SendUserRegisteredEvent(ctx context.Context, tenantID string, u *user.User) error {
    args := m.Called(ctx, tenantID, u)
    return args.Error(0)
}

func (m *MockPublisher) Close() error {
    return m.Called().Error(0)
}
```

### Usage in Tests

```go
func TestOrderService_CreateOrder(t *testing.T) {
    mockPublisher := &publisher.MockPublisher{}
    mockPublisher.On("SendOrderCreatedEvent", mock.Anything, "tenant-123", mock.AnythingOfType("*order.Order")).Return(nil)

    service := order.NewService(mockRepo, mockPublisher)

    result, err := service.CreateOrder(ctx, "tenant-123", items)

    require.NoError(t, err)
    mockPublisher.AssertExpectations(t)
}
```

---

## Adding Kafka Checklist

1. **Create publisher directory**: `internal/publisher/`
2. **Define publisher interface** (`publisher.go`):
   - Domain-specific event methods
   - Close method
3. **Create Kafka implementation** (`kafka/publisher.go`):
   - Use `sarama.SyncProducer`
   - Implement protobuf serialization
   - Handle tenant-specific and global topics
4. **Create instrumented wrapper** (`instrumented.go`):
   - Use `trace.Instrument()` for each method
   - Add logging with `logger.Logger`
5. **Add configuration**:
   - Add `KafkaConfig` to `internal/config/configuration.go`
   - Add to `config/configuration.yaml`
   - Set defaults for brokers, consumer group, enabled
6. **Create Fx module** (`internal/di/kafka/module.go`):
   - Provide producer with graceful disable pattern
   - Provide publisher and instrumented wrapper
   - Add shutdown hook with `platformfx.ProvideShutdownHook`
7. **Wire in bootstrap** (`cmd/serve.go`):
   - Add `kafkadi.Module` to Fx application
8. **Define protobuf events** (`api/proto/events/v1/events.proto`)
9. **Add docker-compose Kafka** (for local development)
