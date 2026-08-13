# Temporal Patterns — Production Reference

Complete reference for building Temporal workflows and activities using `common/temporal`. All patterns use the canonical abstraction layer; no service may bypass it.

---

## 1. Architectural Foundation

`common/temporal` is the sole entry point for all Temporal SDK interactions. Services depend on this package — never on `go.temporal.io/sdk` directly (except for SDK types like `workflow.Context`).

### Package Layout

```
common/temporal/
├── client.go           # NewClient, ClientOption functional opts
├── config.go           # Config, WorkerConfig, DefaultConfig, Validate
├── options.go          # DefaultActivityOptions, ApplyDefaultActivityOptions
├── retry.go            # DefaultRetryPolicy (1s initial, 2.0 backoff, 1m max, 5 attempts)
├── worker.go           # NewWorker, WorkerOption, NopWorker
├── fx/
│   └── module.go       # temporalfx.Module, Provide*Registrar helpers
├── identity/
│   └── identity.go     # identity.New("service", "env", opts...)
├── logging/
│   └── zap.go          # logging.NewAdapter — bridges devkit logger → Temporal log.Logger
├── otel/
│   └── interceptors.go # TracingConfig, NewTracingInterceptor
└── registry/
    ├── types.go        # WorkflowRegistrar, ActivityRegistrar, NexusRegistrar
    └── registry.go     # Registry — duplicate-checked registration
```

### Layering

```
Service Handlers / Use Cases
  → common/temporal client + workflow starter
    → Temporal Server
      → Worker Process (common/temporal worker + registry)
        → Workflows (deterministic, replay-safe)
          → Activities (idempotent, heartbeating)
            → Service/Domain Layer + External Systems
```

### Import Rules

```go
import (
    // ✅ common/temporal abstractions
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal"
    temporalfx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal/fx"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal/registry"

    // ✅ SDK types only (not constructors/builders)
    "go.temporal.io/sdk/workflow"
    "go.temporal.io/sdk/activity"
    temporalsdk "go.temporal.io/sdk/temporal"

    // ❌ NEVER import these directly
    // "go.temporal.io/sdk/client"   — use common/temporal.NewClient
    // "go.temporal.io/sdk/worker"   — use common/temporal.NewWorker
)
```

### Optional Tooling: protoc-gen-go-temporal

[protoc-gen-go-temporal](https://cludden.github.io/protoc-gen-go-temporal/) is a protoc plugin that generates typed Temporal clients and workers from proto definitions. It can produce type-safe workflow starters, signal/query helpers, and activity interfaces. Evaluate for services with complex Temporal APIs where type safety at the proto boundary reduces boilerplate.

---

## 2. Configuration

### Config Struct

Embed `temporal.Config` in service configuration:

```go
// internal/config/configuration.go
import (
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal"
    temporalotel "gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal/otel"
)

type Configuration struct {
    ServiceName string              `mapstructure:"service_name"`
    // ... other fields ...
    Temporal    temporal.Config              `mapstructure:"temporal"`
    TemporalOTel temporalotel.TracingConfig  `mapstructure:"temporal_otel"`
}
```

### YAML Configuration

```yaml
temporal:
  enabled: true
  host_port: "temporal:7233"
  namespace: "my-namespace"
  task_queue: "my-service-tasks"
  identity: ""                    # auto-generated if empty
  lazy: false
  connect_timeout: 10s
  worker:
    enabled: true
    max_concurrent_activity_execution_size: 100
    max_concurrent_workflow_task_execution_size: 100
    max_concurrent_activity_task_pollers: 4
    max_concurrent_workflow_task_pollers: 4
    worker_stop_timeout: 30s

temporal_otel:
  enabled: true
  disable_signal_tracing: false
  disable_query_tracing: false
  disable_baggage: false
```

### Config Defaults

`temporal.DefaultConfig()` returns:

| Field | Default |
|-------|---------|
| Enabled | `false` |
| HostPort | `localhost:7233` |
| Namespace | `default` |
| ConnectTimeout | `10s` |
| Worker.Enabled | `false` |

### Validation

`Config.Validate()` runs automatically and checks:
- If `Enabled=true`: `HostPort` and `Namespace` required.
- If `Worker.Enabled=true`: `TaskQueue` required.
- All numeric fields validated with `gt=0` when set.

---

## 3. Bootstrap & Dependency Injection (Fx)

### Standard Bootstrap

```go
// cmd/serve.go
import (
    temporalfx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal/fx"
    temporalotel "gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal/otel"
)

func runServeService() {
    cfg, _, err := config.Load()
    // ... error handling ...

    app := fx.New(
        // 1. Platform, Logger, Trace (unchanged)
        platformfx.Module(cfg.Platform),
        loggerfx.ModuleWithOptions(cfg.Logger, ...),
        tracefx.Module(cfg.Trace),

        // 2. Provide config
        fx.Provide(func() *config.Configuration { return cfg }),

        // 3. Temporal module — provides client, worker, registry
        temporalfx.Module(cfg.Temporal),

        // 4. OTel tracing config (optional, picked up by temporalfx)
        fx.Provide(func() *temporalotel.TracingConfig { return &cfg.TemporalOTel }),

        // 5. Register workflows and activities via registrars
        temporalfx.ProvideWorkflowRegistrar(NewOrderWorkflowRegistrar),
        temporalfx.ProvideActivityRegistrar(NewOrderActivitiesRegistrar),

        // 6. Infrastructure + transport modules
        postgres.Module,
        http.Module,
        grpc.Module,
    )

    app.Run()
}
```

### Module Order (with Temporal)

1. `platformfx.Module` — always first
2. `loggerfx.ModuleWithOptions` — logger
3. `tracefx.Module` — tracing
4. `temporalfx.Module` — Temporal client + worker
5. Workflow/activity registrar providers
6. Infrastructure modules (database, cache)
7. Transport modules (HTTP, gRPC) — always last

### What `temporalfx.Module` Provides

| Provided | Type | Shutdown Priority |
|----------|------|-------------------|
| `client.Client` | Temporal client | `PriorityDatabase` (60) |
| `worker.Worker` | Temporal worker | `PriorityServer` (10) |
| `registry.Registry` | Registration coordinator | — |

Shutdown order: worker stops first (priority 10, drains tasks), then client closes (priority 60).

### Registrar Pattern

Workflows and activities register via Fx groups — no manual `worker.Register*` calls:

```go
// internal/di/temporal/registrars.go
package temporal

import (
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal/registry"
    "go.temporal.io/sdk/worker"
    "go.temporal.io/sdk/workflow"

    orderworkflow "your-service/internal/orchestration/workflows/order"
    orderactivities "your-service/internal/orchestration/activities/order"
)

// NewOrderWorkflowRegistrar registers order workflows.
func NewOrderWorkflowRegistrar() registry.WorkflowRegistrar {
    return registry.WorkflowRegistrar{
        Name: "order-workflows",
        Register: func(r worker.WorkflowRegistry) {
            r.RegisterWorkflowWithOptions(
                orderworkflow.ProcessOrder,
                workflow.RegisterOptions{Name: "ProcessOrder"},
            )
        },
    }
}

// NewOrderActivitiesRegistrar registers order activities.
func NewOrderActivitiesRegistrar(svc *orderactivities.Activities) registry.ActivityRegistrar {
    return registry.ActivityRegistrar{
        Name: "order-activities",
        Register: func(r worker.ActivityRegistry) {
            r.RegisterActivity(svc)
        },
    }
}
```

---

## 3.1 Deployment Modes

Services using Temporal can run in three modes:

| Mode | Command | `temporal.enabled` | `temporal.worker.enabled` | gRPC | Worker | Use Case |
|------|---------|-------------------|--------------------------|------|--------|----------|
| Combined | `serve` | true | true | Yes | Yes | Local dev, small scale |
| API-only | `serve --worker=false` | true | false | Yes | No | API pods (horizontal scale) |
| Worker-only | `worker` | true | true | No | Yes | Worker pods (scale by backlog) |
| Disabled | N/A | false | N/A | Yes | No | Services without Temporal |

### Fx Behavior by Mode

- **Combined/Worker**: `temporalfx.Module` provides real `client.Client` and `worker.Worker`
- **API-only**: `temporalfx.Module` provides real `client.Client` and `NopWorker` (no polling)
- **Disabled**: `temporalfx.Module` returns empty; any injection of `client.Client` causes Fx startup failure

### Worker-Only Command Template

```go
// cmd/worker.go
var workerCmd = &cobra.Command{
    Use:   "worker",
    Short: "Run Temporal worker only",
    Run: func(cmd *cobra.Command, args []string) {
        cfg, _, _ := config.Load()
        cfg.Temporal.Worker.Enabled = true

        app := fx.New(
            platformfx.Module(cfg.Platform),
            loggerfx.ModuleWithOptions(cfg.Logger, ...),
            tracefx.Module(cfg.Trace),
            fx.Provide(func() *config.Configuration { return cfg }),

            // Infrastructure for activities
            postgresdi.Module,
            kafkadi.Module,
            clientsdi.Module,

            // Temporal worker + registrars
            temporaldi.NewModule(cfg),

            // NO grpcdi.Module, NO httpdi.Module
        )
        app.Run()
    },
}
```

---

## 4. Workflow Architecture

### Workflow Input/Output Types

All workflow inputs and outputs are versioned structs. No primitives, no `map[string]any`.

```go
// internal/orchestration/workflows/order/types.go
package order

import "time"

// ProcessOrderInput is the versioned input for ProcessOrder workflow.
type ProcessOrderInput struct {
    OrderID    string    `json:"order_id"`
    CustomerID string    `json:"customer_id"`
    Items      []Item    `json:"items"`
    CreatedAt  time.Time `json:"created_at"`
}

// ProcessOrderOutput is the versioned output for ProcessOrder workflow.
type ProcessOrderOutput struct {
    OrderID     string `json:"order_id"`
    Status      string `json:"status"`
    CompletedAt string `json:"completed_at"`
}

// Item represents an order line item.
type Item struct {
    ProductID string  `json:"product_id"`
    Quantity  int     `json:"quantity"`
    Price     float64 `json:"price"`
}
```

### Workflow Implementation

```go
// internal/orchestration/workflows/order/workflow.go
package order

import (
    "fmt"
    "time"

    "go.temporal.io/sdk/workflow"

    commontemporal "gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal"

    orderactivities "your-service/internal/orchestration/activities/order"
)

// ProcessOrder orchestrates order fulfillment with Saga compensation.
// Named return (retErr) allows the deferred compensation to inspect the error.
func ProcessOrder(ctx workflow.Context, input ProcessOrderInput) (_ *ProcessOrderOutput, retErr error) {
    logger := workflow.GetLogger(ctx)
    logger.Info("starting order processing", "order_id", input.OrderID)

    actCtx := workflow.WithActivityOptions(ctx, commontemporal.DefaultActivityOptions())

    // Use typed method value reference for compile-time safety (see §5).
    var a *orderactivities.Activities

    // Compensation stack — see "Compensation and Workflow Cancellation" section below.
    var compensations []func(workflow.Context) error

    defer func() {
        if retErr == nil || len(compensations) == 0 {
            return
        }
        // NewDisconnectedContext survives workflow cancellation.
        newCtx, cancel := workflow.NewDisconnectedContext(ctx)
        defer cancel()
        compActCtx := workflow.WithActivityOptions(newCtx, commontemporal.DefaultActivityOptions())
        for i := len(compensations) - 1; i >= 0; i-- {
            if err := compensations[i](compActCtx); err != nil {
                logger.Error("compensation failed", "step", i, "error", err)
            }
        }
    }()

    // Step 1: Validate order (no side effect — nothing to compensate).
    var validationResult ValidateOrderOutput
    if err := workflow.ExecuteActivity(actCtx, a.ValidateOrder, ValidateOrderInput{
        OrderID: input.OrderID,
        Items:   input.Items,
    }).Get(ctx, &validationResult); err != nil {
        retErr = fmt.Errorf("validate order: %w", err)
        return
    }

    // Step 2: Reserve inventory (longer timeout, heartbeat required).
    inventoryCtx := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
        StartToCloseTimeout:    10 * time.Minute,
        HeartbeatTimeout:       30 * time.Second,
        ScheduleToStartTimeout: 5 * time.Minute,
        RetryPolicy:            commontemporal.DefaultRetryPolicy(),
    })

    var reserveResult ReserveInventoryOutput
    if err := workflow.ExecuteActivity(inventoryCtx, a.ReserveInventory, ReserveInventoryInput{
        OrderID: input.OrderID,
        Items:   input.Items,
    }).Get(ctx, &reserveResult); err != nil {
        retErr = fmt.Errorf("reserve inventory: %w", err)
        return
    }
    compensations = append(compensations, func(c workflow.Context) error {
        return workflow.ExecuteActivity(c, a.ReleaseInventory, ReleaseInventoryInput{
            OrderID:       input.OrderID,
            ReservationID: reserveResult.ReservationID,
        }).Get(c, nil)
    })

    // Step 3: Process payment.
    var paymentResult ProcessPaymentOutput
    if err := workflow.ExecuteActivity(actCtx, a.ProcessPayment, ProcessPaymentInput{
        OrderID:    input.OrderID,
        CustomerID: input.CustomerID,
        Amount:     validationResult.TotalAmount,
    }).Get(ctx, &paymentResult); err != nil {
        retErr = fmt.Errorf("process payment: %w", err)
        return // defer runs → releases inventory.
    }

    // All succeeded — clear compensations.
    compensations = nil
    return &ProcessOrderOutput{
        OrderID:     input.OrderID,
        Status:      "completed",
        CompletedAt: workflow.Now(ctx).Format(time.RFC3339),
    }, nil
}
```

### Determinism Rules (Non-Negotiable)

| Forbidden in Workflows | Use Instead |
|------------------------|-------------|
| `time.Now()` | `workflow.Now(ctx)` |
| `time.Sleep()` | `workflow.Sleep(ctx, d)` |
| `time.After()` | `workflow.NewTimer(ctx, d)` |
| `rand.*` | `workflow.SideEffect(ctx, fn)` |
| `uuid.New()` | `workflow.SideEffect(ctx, fn)` |
| `os.Getenv()` | Pass via workflow input |
| `http.Get()`, any I/O | Encapsulate in an activity |
| `sync.Mutex`, goroutines | `workflow.Go(ctx, fn)`, `workflow.Channel` |
| `map` iteration (order) | Sort keys first or use slices |

### Continue-As-New for Long-Lived Workflows

Any workflow with unbounded iterations must use Continue-As-New to cap history growth:

```go
func PollingWorkflow(ctx workflow.Context, input PollingInput) error {
    const maxIterations = 1000

    for i := input.Iteration; i < input.Iteration+maxIterations; i++ {
        if err := workflow.Sleep(ctx, input.Interval); err != nil {
            return err
        }

        actCtx := workflow.WithActivityOptions(ctx, commontemporal.DefaultActivityOptions())
        if err := workflow.ExecuteActivity(actCtx, PollExternal, PollInput{ID: input.ID}).Get(ctx, nil); err != nil {
            workflow.GetLogger(ctx).Warn("poll failed, continuing", "error", err)
        }
    }

    // Continue-As-New: start fresh with incremented iteration counter.
    return workflow.NewContinueAsNewError(ctx, PollingWorkflow, PollingInput{
        ID:        input.ID,
        Interval:  input.Interval,
        Iteration: input.Iteration + maxIterations,
    })
}
```

### Compensation and Workflow Cancellation (Saga Pattern)

When a workflow step creates a side effect that must be undone on failure (e.g., reserving inventory, charging a card), you need **compensation**. Temporal provides the primitives; the pattern is yours to implement.

#### Signal Cancellation vs. Workflow Cancellation

These are fundamentally different — don't confuse them:

| Mechanism | `ctx` cancelled? | `NewDisconnectedContext` needed? |
|-----------|-------------------|----------------------------------|
| **Signal** (`GetSignalChannel`) | **No** — application-level event, `ctx` is alive | No — use `ctx` normally |
| **`client.CancelWorkflow()`** | **Yes** — all pending `.Get()` return `CanceledError` | **Yes** |
| **Parent cancels child workflow** | **Yes** | **Yes** |
| **`CancellationScope` cancellation** | **Yes** (within scope) | **Yes** |
| **Timer deadline exceeded** | **Yes** | **Yes** |

The signal example in §8 (Signals section) is correct — it uses `actCtx` for compensation because the signal doesn't cancel the context. But if you need compensation after **workflow cancellation**, the original `ctx` is dead and `ExecuteActivity(ctx, ...)` immediately returns `CanceledError`.

#### `workflow.NewDisconnectedContext`

Creates a new context that is **not cancelled** when the parent is. This is the only way to run activities after workflow cancellation:

```go
// ctx is cancelled (workflow was cancelled).
// newCtx is alive — activities scheduled with it will execute.
newCtx, cancel := workflow.NewDisconnectedContext(ctx)
defer cancel() // Prevent goroutine leak.
```

**Always `defer cancel()`** — without it, Temporal leaks an internal goroutine.

#### Structured Saga Pattern (`defer` + Compensation Stack)

For multi-step workflows where each step may need undoing, use a `defer`-based compensation stack. The `ProcessOrder` example in [Workflow Implementation](#workflow-implementation) above demonstrates the full pattern. Here is the skeleton:

```go
func MyWorkflow(ctx workflow.Context, input MyInput) (_ *MyOutput, retErr error) {
    actCtx := workflow.WithActivityOptions(ctx, commontemporal.DefaultActivityOptions())
    var a *myactivities.Activities

    // 1. Declare compensation stack.
    var compensations []func(workflow.Context) error

    // 2. Register defer BEFORE any activity — covers all exit paths including cancellation.
    //    Captures retErr and compensations by reference (sees values at function-exit time).
    defer func() {
        if retErr == nil || len(compensations) == 0 {
            return
        }
        newCtx, cancel := workflow.NewDisconnectedContext(ctx)
        defer cancel()
        compActCtx := workflow.WithActivityOptions(newCtx, commontemporal.DefaultActivityOptions())
        for i := len(compensations) - 1; i >= 0; i-- {
            if err := compensations[i](compActCtx); err != nil {
                workflow.GetLogger(newCtx).Error("compensation failed", "step", i, "error", err)
            }
        }
    }()

    // 3. Each step: execute activity, then push its undo.
    var result StepOneOutput
    if err := workflow.ExecuteActivity(actCtx, a.StepOne, ...).Get(ctx, &result); err != nil {
        retErr = fmt.Errorf("step one: %w", err)
        return // defer runs, compensations empty — nothing to undo.
    }
    compensations = append(compensations, func(c workflow.Context) error {
        return workflow.ExecuteActivity(c, a.UndoStepOne, UndoInput{ID: result.ID}).Get(c, nil)
    })

    // 4. On full success — clear compensations so defer is a no-op.
    compensations = nil
    return &MyOutput{Status: "completed"}, nil
}
```

**Key design rules:**

1. **`defer` goes BEFORE any activities** — if you place it after, a failure above it won't trigger compensation.
2. **Named return value `(retErr error)`** — the `defer` closure inspects `retErr` to decide whether to compensate. Without named returns you'd need a separate flag.
3. **Push compensation AFTER success** — if step 2 fails, only step 1's undo runs (step 2 never succeeded, nothing to undo).
4. **Reverse order** — Saga pattern: last successful step is undone first.
5. **`compensations = nil`** on full success — prevents the defer from running any cleanup.
6. **`defer cancel()`** on `NewDisconnectedContext` — prevents goroutine leak.
7. **`workflow.GetLogger(newCtx)`** in the defer — use the disconnected context's logger since the original `ctx` may be cancelled.

#### When You Don't Need Compensation

| Scenario | Why |
|----------|-----|
| All operations are idempotent upserts | Re-running the workflow IS the undo — no state to reverse |
| Single-step workflows | Nothing to compensate |
| Downstream system auto-rollbacks | e.g., Stripe auto-voids pending charges after timeout |
| Forward-only event pipelines | Webhook processing, audit logging — events are append-only |

The `HandleWebhook` workflow in this service falls into this category: provider records upsert, AML data overwrites, status transitions are validated. No compensation needed.

### Local Activities

Use local activities for fast, lightweight operations that don't need separate task queue delivery (e.g., input validation, data transformation, cache lookups). They execute in the same worker process that runs the workflow.

```go
func MyWorkflow(ctx workflow.Context, input MyInput) (*MyOutput, error) {
    lao := workflow.LocalActivityOptions{
        StartToCloseTimeout: 5 * time.Second,
        RetryPolicy:         commontemporal.DefaultRetryPolicy(),
    }
    laCtx := workflow.WithLocalActivityOptions(ctx, lao)

    var validated ValidatedInput
    if err := workflow.ExecuteLocalActivity(laCtx, a.ValidateInput, input).Get(ctx, &validated); err != nil {
        return nil, fmt.Errorf("validate input: %w", err)
    }

    // Continue with regular activities for I/O-heavy work...
    actCtx := workflow.WithActivityOptions(ctx, commontemporal.DefaultActivityOptions())
    // ...
}
```

**When to use local activities:**

| Use local activity | Use regular activity |
|----|---|
| Pure computation or validation | Network calls, DB queries, external APIs |
| Sub-second execution expected | May take seconds to minutes |
| No heartbeat needed | Needs heartbeat for long-running work |
| Same worker process is acceptable | Needs separate scaling / task queue routing |

**Constraints:** Local activities do not support heartbeats, have limited retry visibility in the Temporal UI, and their execution is not recorded as a separate task queue event. Prefer regular activities for any I/O or operations that may need independent scaling.

### Child Workflows

Use child workflows for isolation, fan-out, or when a sub-process needs its own retry/timeout policy independent of the parent.

```go
func ParentWorkflow(ctx workflow.Context, input ParentInput) (*ParentOutput, error) {
    childOpts := workflow.ChildWorkflowOptions{
        WorkflowID:        fmt.Sprintf("child-process-%s-%s", input.ParentID, input.ItemID),
        TaskQueue:         "my-service-child-tasks", // Can use same or different queue.
        ParentClosePolicy: enumspb.PARENT_CLOSE_POLICY_TERMINATE,
        RetryPolicy:       commontemporal.DefaultRetryPolicy(),
    }
    childCtx := workflow.WithChildOptions(ctx, childOpts)

    var result ChildOutput
    if err := workflow.ExecuteChildWorkflow(childCtx, ChildWorkflow, ChildInput{
        ItemID: input.ItemID,
    }).Get(ctx, &result); err != nil {
        return nil, fmt.Errorf("child workflow: %w", err)
    }

    return &ParentOutput{ChildResult: result.Status}, nil
}
```

**`ParentClosePolicy` options:**

| Policy | Behavior when parent closes |
|--------|---|
| `PARENT_CLOSE_POLICY_TERMINATE` | Child is terminated immediately (default, safest) |
| `PARENT_CLOSE_POLICY_REQUEST_CANCEL` | Child receives cancellation signal, can run cleanup |
| `PARENT_CLOSE_POLICY_ABANDON` | Child continues running independently |

**When to use child workflows:**

- Fan-out: process N items in parallel, each with its own retry budget
- Isolation: child failure doesn't automatically fail the parent (use `Get` error handling)
- Separate lifecycle: child may outlive parent (with `ABANDON` policy)
- History management: each child has its own event history, avoiding parent history bloat

**When NOT to use:** For simple sequential steps within a single domain, use activities directly. Child workflows add complexity and latency.

---

## 5. Activity Architecture

### Activity Struct Pattern

Activities are methods on a struct, injected via Fx. This allows dependency injection of services, repos, and clients.

```go
// internal/orchestration/activities/order/activities.go
package order

import (
    "context"
    "fmt"

    "go.temporal.io/sdk/activity"
    temporalsdk "go.temporal.io/sdk/temporal"

    ordersvc "your-service/internal/services/order"
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/logger"
)

// Activities groups order-related activities.
type Activities struct {
    orderSvc ordersvc.Service
    log      logger.Logger
}

// NewActivities creates Activities with injected dependencies.
func NewActivities(orderSvc ordersvc.Service, log logger.Logger) *Activities {
    return &Activities{
        orderSvc: orderSvc,
        log:      log.Named("order.activities"),
    }
}

// activityLog returns the injected logger enriched with Temporal activity metadata.
// Every activity method should use this instead of a.log directly.
// See §7 Logging for the full rationale.
func (a *Activities) activityLog(ctx context.Context) logger.Logger {
    info := activity.GetInfo(ctx)
    return a.log.With(
        logger.String("workflow_id", info.WorkflowExecution.ID),
        logger.String("run_id", info.WorkflowExecution.RunID),
        logger.String("activity_id", info.ActivityID),
        logger.String("activity_type", info.ActivityType.Name),
        logger.Int("attempt", int(info.Attempt)),
        logger.String("taskQueue", info.TaskQueue),
    )
}

// ValidateOrder checks order items and computes totals.
func (a *Activities) ValidateOrder(ctx context.Context, input ValidateOrderInput) (*ValidateOrderOutput, error) {
    log := a.activityLog(ctx)
    log.Info(ctx, "validating order", logger.String("order_id", input.OrderID))

    result, err := a.orderSvc.Validate(ctx, input.OrderID, input.Items)
    if err != nil {
        // Non-retryable: bad input should not be retried.
        return nil, temporalsdk.NewNonRetryableApplicationError(
            fmt.Sprintf("validation failed: %v", err),
            "VALIDATION_ERROR",
            err,
        )
    }

    return &ValidateOrderOutput{
        TotalAmount: result.Total,
        Valid:       true,
    }, nil
}

// ReserveInventory reserves stock with heartbeating.
func (a *Activities) ReserveInventory(ctx context.Context, input ReserveInventoryInput) (*ReserveInventoryOutput, error) {
    log := a.activityLog(ctx)

    for _, item := range input.Items {
        // Check for cancellation between work units (see §5 Cancellation).
        if ctx.Err() != nil {
            return nil, ctx.Err()
        }

        if err := a.orderSvc.ReserveItem(ctx, input.OrderID, item.ProductID, item.Quantity); err != nil {
            return nil, fmt.Errorf("reserve item %s: %w", item.ProductID, err)
        }

        // Heartbeat AFTER the work completes (see §5 Heartbeat Placement).
        activity.RecordHeartbeat(ctx, fmt.Sprintf("reserved %s", item.ProductID))
    }

    log.Info(ctx, "all items reserved", logger.String("order_id", input.OrderID))

    return &ReserveInventoryOutput{
        ReservationID: fmt.Sprintf("res-%s", input.OrderID),
    }, nil
}
```

### Idempotency Pattern

Activities execute at-least-once. Use deterministic idempotency keys derived from workflow identity:

```go
func (a *Activities) ProcessPayment(ctx context.Context, input ProcessPaymentInput) (*ProcessPaymentOutput, error) {
    actInfo := activity.GetInfo(ctx)

    // Idempotency key: deterministic, derived from workflow execution.
    idempotencyKey := fmt.Sprintf("payment-%s-%s-%d",
        actInfo.WorkflowExecution.ID,
        actInfo.WorkflowExecution.RunID,
        actInfo.Attempt,
    )

    result, err := a.paymentClient.Charge(ctx, input.Amount, idempotencyKey)
    if err != nil {
        return nil, err
    }

    return &ProcessPaymentOutput{TransactionID: result.ID}, nil
}
```

### Error Classification

```go
import temporalsdk "go.temporal.io/sdk/temporal"

// Non-retryable — bad input, business rule violation.
return nil, temporalsdk.NewNonRetryableApplicationError("invalid amount", "INVALID_INPUT", err)

// Retryable (default) — transient failure, just return error.
return nil, fmt.Errorf("database timeout: %w", err)

// Non-retryable types via retry policy (configure in activity options).
retryPolicy := &temporalsdk.RetryPolicy{
    InitialInterval:        1 * time.Second,
    BackoffCoefficient:     2.0,
    MaximumInterval:        1 * time.Minute,
    MaximumAttempts:        5,
    NonRetryableErrorTypes: []string{"VALIDATION_ERROR", "NOT_FOUND"},
}
```

### Activity Options Reference

Every activity call must specify explicit options. Use `commontemporal.DefaultActivityOptions()` as baseline:

| Option | Default | When to Override |
|--------|---------|------------------|
| `ScheduleToStartTimeout` | `10m` | Long queues, capacity-limited workers |
| `StartToCloseTimeout` | `5m` | External API calls, batch processing |
| `HeartbeatTimeout` | `30s` | Long-running activities (set proportional to work units) |
| `RetryPolicy` | 5 attempts, 2x backoff | External APIs, payment processing |

> **HeartbeatTimeout gotcha**: If an activity doesn't call `RecordHeartbeat`, the `HeartbeatTimeout` is still enforced but Temporal has no way to detect liveness — the timeout starts from the last heartbeat (or activity start). For activities that never heartbeat, either remove `HeartbeatTimeout` (use custom options with `HeartbeatTimeout: 0`) or add heartbeats.

### Heartbeat Placement (Critical)

**Always heartbeat AFTER slow work completes, never before.** The heartbeat resets Temporal's liveness timer. If you heartbeat before a slow call, the timer starts ticking during the call — if the call exceeds `HeartbeatTimeout`, Temporal kills the activity even though it's making progress.

```go
// ❌ WRONG: heartbeat before the slow call — timer runs during API call
activity.RecordHeartbeat(ctx, "fetching data from external API")
data, err := a.externalClient.FetchData(ctx, input.ID)  // takes 40s, HeartbeatTimeout=30s → killed!

// ✅ CORRECT: heartbeat after the slow call — timer resets after completion
data, err := a.externalClient.FetchData(ctx, input.ID)
if err != nil {
    return nil, err
}
activity.RecordHeartbeat(ctx, "fetched data, processing")
```

For activities with multiple sequential external calls:

```go
func (a *Activities) MultiStepActivity(ctx context.Context, input Input) error {
    // Step 1: external call
    result1, err := a.client.Step1(ctx, input.ID)
    if err != nil {
        return fmt.Errorf("step1: %w", err)
    }
    activity.RecordHeartbeat(ctx, "step1 complete")

    // Check cancellation between steps
    if ctx.Err() != nil {
        return ctx.Err()
    }

    // Step 2: external call
    result2, err := a.client.Step2(ctx, result1)
    if err != nil {
        return fmt.Errorf("step2: %w", err)
    }
    activity.RecordHeartbeat(ctx, "step2 complete")

    return nil
}
```

### Cancellation Handling

When Temporal cancels an activity (worker shutdown, workflow cancelled, heartbeat timeout), it cancels the activity's `context.Context`. Activities should check `ctx.Err()` between work units to stop promptly:

```go
func (a *Activities) BatchProcess(ctx context.Context, input BatchInput) error {
    for _, item := range input.Items {
        // Check for cancellation BEFORE starting next work unit.
        if ctx.Err() != nil {
            return ctx.Err()
        }

        if err := a.processItem(ctx, item); err != nil {
            return err
        }

        activity.RecordHeartbeat(ctx, fmt.Sprintf("processed %s", item.ID))
    }
    return nil
}
```

**When to check `ctx.Err()`:**
- Between sequential external calls (DB, API, gRPC)
- Between iterations in a loop
- Before starting expensive computation

**When you can skip it:**
- If the activity makes a single call that already respects `ctx` (e.g., a gRPC call with context propagation — the underlying call will fail fast on cancellation)
- Very fast activities (< 1s total)

### Invoking Struct-Based Activities from Workflows

When activities are registered as struct methods via `r.RegisterActivity(structInstance)`, the workflow must reference them correctly.

**Method value reference (recommended)** — use a nil pointer to the struct type:

```go
func ProcessOrder(ctx workflow.Context, input ProcessOrderInput) (*ProcessOrderOutput, error) {
    actCtx := workflow.WithActivityOptions(ctx, commontemporal.DefaultActivityOptions())

    // ✅ Typed method value reference — compile-time safe, refactor-safe.
    var a *orderactivities.Activities
    var result ValidateOrderOutput
    err := workflow.ExecuteActivity(actCtx, a.ValidateOrder, ValidateOrderInput{
        OrderID: input.OrderID,
    }).Get(ctx, &result)
}
```

The nil pointer is safe because Temporal only uses the method value to derive the registered activity name — it never calls the method on this pointer. The actual execution happens on the real struct instance in the worker.

**String name invocation (avoid):**

```go
// ❌ AVOID: string names are fragile — typos and renames are silent runtime errors.
// The registered name for struct methods depends on SDK version and registration options.
err := workflow.ExecuteActivity(actCtx, "ValidateOrder", input).Get(ctx, &result)
```

With struct-based registration (`r.RegisterActivity(structInstance)`), the Temporal Go SDK registers methods with names like `StructType-MethodName`. Using a bare string like `"ValidateOrder"` may not match the registered name, causing "unknown activity type" errors at runtime.

**Function reference (for standalone activity functions):**

```go
// ✅ For standalone functions (not struct methods), pass the function directly.
err := workflow.ExecuteActivity(actCtx, StandaloneValidate, input).Get(ctx, &result)
```

### Single-Responsibility in Activities

Each activity should own **one concern**. Mixing multiple concerns in a single activity makes retry semantics confusing:

```go
// ❌ BAD: mixes verification status update + onboarding status update.
// If verification succeeds but onboarding fails, the whole activity retries —
// re-running the verification update unnecessarily.
func (a *Activities) UpdateStatusAndOnboarding(ctx context.Context, input Input) error {
    if err := a.verifySvc.UpdateStatus(ctx, ...); err != nil {
        return err
    }
    // Onboarding update buried as a side effect — hard to test, hard to retry independently.
    if input.Type == "created" {
        if err := a.complianceSvc.UpdateOnboarding(ctx, ...); err != nil {
            return err // retries BOTH operations
        }
    }
    return nil
}

// ✅ GOOD: separate activities — each retries independently.
func (a *Activities) UpdateVerificationStatus(ctx context.Context, input UpdateStatusInput) (*StatusOutput, error) { ... }
func (a *Activities) UpdateOnboardingStatus(ctx context.Context, input OnboardingInput) error { ... }
```

**Exception**: if two operations must be atomic (both succeed or both fail), they belong in one activity. But that's rare — prefer idempotent upserts in separate activities.

### Conditional Side Effects in Activities

When an activity's behavior depends on external state (feature flags, config), be explicit about the failure semantics:

```go
// ❌ BAD: flag check failure silently succeeds — lost retriability.
func (a *Activities) UpdateExternal(ctx context.Context, input Input) error {
    enabled, err := a.flags.IsEnabled(ctx, "my-flag")
    if err != nil {
        a.log.Warn(ctx, "flag check failed, skipping") // silent success
        return nil
    }
    if !enabled {
        return nil
    }
    return a.client.Update(ctx, input)
}

// ✅ BETTER: move the flag check to the workflow via a dedicated activity.
// The workflow records the decision in history, making it deterministic on replay.
func (a *Activities) CheckFeatureFlag(ctx context.Context, input FlagInput) (*FlagOutput, error) {
    enabled, err := a.flags.IsEnabled(ctx, input.Flag)
    if err != nil {
        return nil, fmt.Errorf("check feature flag %s: %w", input.Flag, err)
    }
    return &FlagOutput{Enabled: enabled}, nil
}

// In workflow:
var flagResult FlagOutput
err := workflow.ExecuteActivity(actCtx, a.CheckFeatureFlag, FlagInput{Flag: "my-flag"}).Get(ctx, &flagResult)
if err != nil { /* retry or fail */ }
if flagResult.Enabled {
    err = workflow.ExecuteActivity(actCtx, a.UpdateExternal, input).Get(ctx, nil)
}
```

---

## 6. Retry Policies

### Default Retry Policy

`commontemporal.DefaultRetryPolicy()` returns:

```go
&temporal.RetryPolicy{
    InitialInterval:    1 * time.Second,
    BackoffCoefficient: 2.0,
    MaximumInterval:    1 * time.Minute,
    MaximumAttempts:    5,
}
```

### Custom Retry Policies

```go
// Aggressive retries for idempotent external APIs.
aggressiveRetry := &temporalsdk.RetryPolicy{
    InitialInterval:    500 * time.Millisecond,
    BackoffCoefficient: 1.5,
    MaximumInterval:    30 * time.Second,
    MaximumAttempts:    10,
}

// Conservative retries for payment/billing.
paymentRetry := &temporalsdk.RetryPolicy{
    InitialInterval:    2 * time.Second,
    BackoffCoefficient: 3.0,
    MaximumInterval:    5 * time.Minute,
    MaximumAttempts:    3,
    NonRetryableErrorTypes: []string{"INSUFFICIENT_FUNDS", "INVALID_CARD"},
}

// No retries — use for activities that are non-idempotent by nature.
noRetry := &temporalsdk.RetryPolicy{
    MaximumAttempts: 1,
}
```

---

## 7. Observability & Cross-Cutting Concerns

### OTel Tracing

Enabled via `temporalotel.TracingConfig` and automatically injected by `temporalfx.Module`:

```go
// Provide tracing config — picked up by temporalfx.NewClient and temporalfx.NewWorker.
fx.Provide(func() *temporalotel.TracingConfig {
    return &cfg.TemporalOTel
})
```

The interceptor propagates trace context across:
- Client → Workflow (start workflow spans)
- Workflow → Activity (activity execution spans)
- Workflow → Child Workflow (child spans)

### Logging

Temporal logs are bridged to devkit's `logger.Logger` via `logging.NewAdapter`.

#### Workflows — `workflow.GetLogger` Only

```go
logger := workflow.GetLogger(ctx)
logger.Info("processing step", "step", "validate", "order_id", input.OrderID)
```

**Critical**: Never use `fmt.Println`, `log.Printf`, or the injected `logger.Logger` inside workflow code. Only `workflow.GetLogger` is replay-safe — it suppresses duplicate logs during replay.

#### Activities — Enriched Injected Logger (Recommended)

`activity.GetLogger(ctx)` returns the Temporal SDK logger, which automatically includes `WorkflowID`, `RunID`, `ActivityType`, and `Attempt` in every log entry. However, it does **not** carry OTel trace context (`trace_id`, `span_id`).

The injected devkit `logger.Logger` carries OTel trace context (via `zaplogger.WithOTelTracing()`) but does **not** include Temporal metadata.

**Recommended pattern**: enrich the injected logger with Temporal metadata so you get both:

```go
// activityLog returns the injected logger enriched with Temporal activity metadata.
// This gives you OTel trace context (trace_id, span_id) AND Temporal identity
// (workflow_id, run_id, activity_type, attempt) in every log entry.
func (a *Activities) activityLog(ctx context.Context) logger.Logger {
    info := activity.GetInfo(ctx)
    return a.log.With(
        logger.String("workflow_id", info.WorkflowExecution.ID),
        logger.String("run_id", info.WorkflowExecution.RunID),
        logger.String("activity_type", info.ActivityType.Name),
        logger.Int("attempt", int(info.Attempt)),
    )
}

func (a *Activities) ProcessPayment(ctx context.Context, input ProcessPaymentInput) (*ProcessPaymentOutput, error) {
    log := a.activityLog(ctx)
    log.Info(ctx, "processing payment", logger.String("order_id", input.OrderID))
    // ...
}
```

| Logger | OTel trace_id | Temporal workflow_id | Temporal attempt |
|--------|--------------|---------------------|-----------------|
| `activity.GetLogger(ctx)` | ❌ | ✅ automatic | ✅ automatic |
| `a.log` (raw injected) | ✅ | ❌ | ❌ |
| `a.activityLog(ctx)` (enriched) | ✅ | ✅ | ✅ |

Without the attempt number in logs, you cannot distinguish retry #1 from retry #5 during incident response.

### Identity

Use `identity.New` for worker/client identity:

```go
import "gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal/identity"

id := identity.New("order-service", "production",
    identity.WithVersion("v1.2.3"),
)
// → "order-service@production/hostname#v1.2.3"
```

Set in config or pass via `temporal.Config.Identity`.

---

## 8. Signals, Queries, and Async Patterns

### Signals (Incoming Events)

```go
func ProcessOrderWithCancellation(ctx workflow.Context, input ProcessOrderInput) (*ProcessOrderOutput, error) {
    // Create signal channel.
    cancelCh := workflow.GetSignalChannel(ctx, "cancel-order")

    // Use selector for deterministic multi-wait.
    selector := workflow.NewSelector(ctx)

    var cancelled bool
    selector.AddReceive(cancelCh, func(ch workflow.ReceiveChannel, more bool) {
        var reason string
        ch.Receive(ctx, &reason)
        cancelled = true
        workflow.GetLogger(ctx).Info("order cancelled", "reason", reason)
    })

    // Run activity concurrently.
    actCtx := workflow.WithActivityOptions(ctx, commontemporal.DefaultActivityOptions())
    actFuture := workflow.ExecuteActivity(actCtx, ProcessPayment, ProcessPaymentInput{
        OrderID: input.OrderID,
    })

    selector.AddFuture(actFuture, func(f workflow.Future) {
        // Activity completed.
    })

    selector.Select(ctx)

    if cancelled {
        // Run compensation.
        _ = workflow.ExecuteActivity(actCtx, RefundPayment, RefundInput{OrderID: input.OrderID}).Get(ctx, nil)
        return &ProcessOrderOutput{Status: "cancelled"}, nil
    }

    var result ProcessPaymentOutput
    if err := actFuture.Get(ctx, &result); err != nil {
        return nil, err
    }

    return &ProcessOrderOutput{Status: "completed"}, nil
}
```

### Queries (Read-Only State)

```go
func OrderTrackingWorkflow(ctx workflow.Context, input OrderInput) error {
    var currentStatus string

    // Register query handler — NO side effects allowed.
    if err := workflow.SetQueryHandler(ctx, "get-status", func() (string, error) {
        return currentStatus, nil
    }); err != nil {
        return err
    }

    currentStatus = "validating"
    // ... do work, update currentStatus ...
    currentStatus = "processing"
    // ... more work ...
    currentStatus = "completed"

    return nil
}
```

### Update Handlers (Validated Mutations)

```go
func OrderWorkflowWithUpdates(ctx workflow.Context, input OrderInput) error {
    var discount float64

    // Update handler with validation.
    if err := workflow.SetUpdateHandlerWithOptions(ctx, "apply-discount",
        func(ctx workflow.Context, pct float64) error {
            discount = pct
            return nil
        },
        workflow.UpdateHandlerOptions{
            Validator: func(ctx workflow.Context, pct float64) error {
                if pct < 0 || pct > 50 {
                    return fmt.Errorf("discount must be 0-50%%, got %.1f", pct)
                }
                return nil
            },
        },
    ); err != nil {
        return err
    }

    // ... workflow logic using discount ...
    return nil
}
```

### Async Activity Completion

For activities that complete asynchronously (e.g., human approval, webhook callback):

```go
func (a *Activities) RequestApproval(ctx context.Context, input ApprovalInput) error {
    // Get task token for async completion.
    actInfo := activity.GetInfo(ctx)
    taskToken := actInfo.TaskToken

    // Store token externally (e.g., in database keyed by approval ID).
    if err := a.approvalStore.Save(ctx, input.ApprovalID, taskToken); err != nil {
        return err
    }

    // Signal external system (email, Slack, etc.).
    if err := a.notifier.RequestApproval(ctx, input); err != nil {
        return err
    }

    // Return ErrResultPending — activity stays open until async completion.
    return activity.ErrResultPending
}

// Called by webhook/API handler when approval arrives.
func (h *ApprovalHandler) CompleteApproval(ctx context.Context, approvalID string, approved bool) error {
    taskToken, err := h.approvalStore.Get(ctx, approvalID)
    if err != nil {
        return err
    }

    if approved {
        return h.temporalClient.CompleteActivity(ctx, taskToken, "approved", nil)
    }
    return h.temporalClient.CompleteActivityByID(ctx,
        h.namespace, workflowID, runID, activityID,
        "rejected", nil,
    )
}
```

---

## 9. Task Queues, Concurrency, and Scaling

### Task Queue Naming

Task queues are stable, namespaced, and domain-scoped:

```
{service-name}-{domain}-tasks      # Standard
{service-name}-{domain}-high       # Priority queue
{service-name}-{domain}-batch      # Batch processing
```

Examples:
- `order-service-fulfillment-tasks`
- `payment-service-billing-tasks`
- `notification-service-email-batch`

### Workflow ID Naming

Embed business identity for deduplication and traceability:

```go
// Pattern: {domain}-{entity}-{business-id}
workflowID := fmt.Sprintf("order-process-%s", orderID)
workflowID := fmt.Sprintf("payment-charge-%s-%s", customerID, invoiceID)
workflowID := fmt.Sprintf("user-onboard-%s", userID)
```

### Starting Workflows

```go
// internal/services/order/default.go
func (s *DefaultService) CreateOrder(ctx context.Context, input CreateOrderInput) (*Order, error) {
    // ... create order in DB ...

    // Start workflow via common/temporal client.
    workflowOpts := client.StartWorkflowOptions{
        ID:                    fmt.Sprintf("order-process-%s", order.ID),
        TaskQueue:             s.cfg.Temporal.TaskQueue,
        WorkflowIDReusePolicy: enumspb.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE,
    }

    run, err := s.temporalClient.ExecuteWorkflow(ctx, workflowOpts,
        orderworkflow.ProcessOrder,
        orderworkflow.ProcessOrderInput{
            OrderID:    order.ID,
            CustomerID: input.CustomerID,
            Items:      input.Items,
            CreatedAt:  order.CreatedAt,
        },
    )
    if err != nil {
        return nil, fmt.Errorf("start order workflow: %w", err)
    }

    s.log.Info(ctx, "order workflow started",
        logger.String("workflow_id", run.GetID()),
        logger.String("run_id", run.GetRunID()),
    )

    return order, nil
}
```

### Workflow ID Reuse Policies

The `WorkflowIDReusePolicy` controls what happens when starting a workflow with an ID that was already used:

| Policy | Behavior | Use when |
|--------|----------|----------|
| `ALLOW_DUPLICATE` | Always start a new run, even if a completed one exists | Default; fire-and-forget patterns |
| `ALLOW_DUPLICATE_FAILED_ONLY` | Only start if the previous run failed/cancelled/terminated | Retry-on-failure patterns |
| `REJECT_DUPLICATE` | Fail if any run (completed or running) exists with this ID | Strict idempotency; one-shot business operations |
| `TERMINATE_IF_RUNNING` | Terminate any running execution, start a new one | Restart/reset patterns; latest-wins semantics |

**Retention and enforcement:** Reuse policies are bounded by the namespace **Retention Period** (typically 1-30 days). Once workflow history is deleted after retention, the ID becomes available again regardless of policy. For long-term deduplication beyond retention, track workflow IDs externally (e.g., in a database).

### Worker Scaling

| Setting | Recommended Minimum | Notes |
|---------|---------------------|-------|
| Worker replicas | >= 2 per task queue (production) | Availability and throughput |
| `MaxConcurrentActivityExecutionSize` | 100 (default) | Tune based on activity resource usage |
| `MaxConcurrentWorkflowTaskExecutionSize` | 100 (default) | Tune based on workflow complexity |
| `MaxConcurrentActivityTaskPollers` | 4 | Increase for high-throughput queues |
| `MaxConcurrentWorkflowTaskPollers` | 4 | Increase for high fan-out |

---

## 10. Versioning & Workflow Evolution

### Using `workflow.GetVersion`

Every semantic change to workflow logic requires a version guard:

```go
func ProcessOrder(ctx workflow.Context, input ProcessOrderInput) (*ProcessOrderOutput, error) {
    // Version guard: v1 had no fraud check, v2 added it.
    v := workflow.GetVersion(ctx, "add-fraud-check", workflow.DefaultVersion, 1)

    actCtx := workflow.WithActivityOptions(ctx, commontemporal.DefaultActivityOptions())

    if v >= 1 {
        // New path: fraud check before payment.
        var fraudResult FraudCheckOutput
        if err := workflow.ExecuteActivity(actCtx, CheckFraud, FraudCheckInput{
            OrderID:    input.OrderID,
            CustomerID: input.CustomerID,
            Amount:     input.TotalAmount,
        }).Get(ctx, &fraudResult); err != nil {
            return nil, fmt.Errorf("fraud check: %w", err)
        }
        if fraudResult.Flagged {
            return &ProcessOrderOutput{Status: "flagged"}, nil
        }
    }
    // Old path (v == DefaultVersion): proceed directly to payment.

    // ... rest of workflow (shared) ...
    return &ProcessOrderOutput{Status: "completed"}, nil
}
```

### Version Guard Rules

1. **Never remove old paths** until all executions on the old version have completed.
2. **Increment version** for each successive change to the same change ID.
3. **Use descriptive change IDs**: `"add-fraud-check"`, `"split-shipping-activity"`, `"fix-compensation-order"`.
4. **Test both paths** in replay tests.

### Patching (Deprecation)

When old version paths can be retired:

```go
// Phase 1: Both paths active (during rollout).
v := workflow.GetVersion(ctx, "add-fraud-check", workflow.DefaultVersion, 1)
if v >= 1 { /* new path */ } else { /* old path */ }

// Phase 2: All old executions complete — deprecate old path.
workflow.GetVersion(ctx, "add-fraud-check", 1, 1)  // minSupported = 1
// Only new path runs. Old replay will fail (intentional).
```

---

## 11. Testing

### Workflow Unit Tests

```go
package order_test

import (
    "testing"

    "github.com/stretchr/testify/suite"
    "go.temporal.io/sdk/testsuite"

    orderworkflow "your-service/internal/orchestration/workflows/order"
)

type OrderWorkflowTestSuite struct {
    suite.Suite
    testsuite.WorkflowTestSuite
    env *testsuite.TestWorkflowEnvironment
}

func (s *OrderWorkflowTestSuite) SetupTest() {
    s.env = s.NewTestWorkflowEnvironment()
}

func (s *OrderWorkflowTestSuite) AfterTest(_, _ string) {
    s.env.AssertExpectations(s.T())
}

func (s *OrderWorkflowTestSuite) TestProcessOrder_Success() {
    // Mock activities.
    s.env.OnActivity(orderworkflow.ValidateOrder, mock.Anything, mock.Anything).
        Return(&orderworkflow.ValidateOrderOutput{TotalAmount: 100.0, Valid: true}, nil)

    s.env.OnActivity(orderworkflow.ReserveInventory, mock.Anything, mock.Anything).
        Return(&orderworkflow.ReserveInventoryOutput{ReservationID: "res-123"}, nil)

    s.env.OnActivity(orderworkflow.ProcessPayment, mock.Anything, mock.Anything).
        Return(&orderworkflow.ProcessPaymentOutput{TransactionID: "txn-456"}, nil)

    // Execute workflow.
    s.env.ExecuteWorkflow(orderworkflow.ProcessOrder, orderworkflow.ProcessOrderInput{
        OrderID:    "order-1",
        CustomerID: "cust-1",
        Items:      []orderworkflow.Item{{ProductID: "prod-1", Quantity: 2, Price: 50.0}},
    })

    s.True(s.env.IsWorkflowCompleted())
    s.NoError(s.env.GetWorkflowError())

    var result orderworkflow.ProcessOrderOutput
    s.NoError(s.env.GetWorkflowResult(&result))
    s.Equal("completed", result.Status)
}

func (s *OrderWorkflowTestSuite) TestProcessOrder_PaymentFails_CompensatesInventory() {
    s.env.OnActivity(orderworkflow.ValidateOrder, mock.Anything, mock.Anything).
        Return(&orderworkflow.ValidateOrderOutput{TotalAmount: 100.0, Valid: true}, nil)

    s.env.OnActivity(orderworkflow.ReserveInventory, mock.Anything, mock.Anything).
        Return(&orderworkflow.ReserveInventoryOutput{ReservationID: "res-123"}, nil)

    s.env.OnActivity(orderworkflow.ProcessPayment, mock.Anything, mock.Anything).
        Return(nil, fmt.Errorf("payment declined"))

    // Expect compensation activity (Saga: inventory released on payment failure).
    s.env.OnActivity(orderworkflow.ReleaseInventory, mock.Anything, mock.Anything).
        Return(nil, nil)

    s.env.ExecuteWorkflow(orderworkflow.ProcessOrder, orderworkflow.ProcessOrderInput{
        OrderID:    "order-1",
        CustomerID: "cust-1",
        Items:      []orderworkflow.Item{{ProductID: "prod-1", Quantity: 2, Price: 50.0}},
    })

    s.True(s.env.IsWorkflowCompleted())
    s.Error(s.env.GetWorkflowError())
}

func (s *OrderWorkflowTestSuite) TestProcessOrder_CancelledDuringPayment_CompensatesInventory() {
    s.env.OnActivity(orderworkflow.ValidateOrder, mock.Anything, mock.Anything).
        Return(&orderworkflow.ValidateOrderOutput{TotalAmount: 100.0, Valid: true}, nil)

    s.env.OnActivity(orderworkflow.ReserveInventory, mock.Anything, mock.Anything).
        Return(&orderworkflow.ReserveInventoryOutput{ReservationID: "res-123"}, nil)

    // Trigger workflow cancellation DURING ProcessPayment via Run callback.
    // Run fires when the activity is invoked — guarantees cancellation happens
    // after ValidateOrder and ReserveInventory have already succeeded.
    s.env.OnActivity(orderworkflow.ProcessPayment, mock.Anything, mock.Anything).
        Run(func(args mock.Arguments) {
            s.env.CancelWorkflow()
        }).
        Return(nil, temporal.NewCanceledError())

    // Expect compensation via defer + NewDisconnectedContext:
    // inventory must be released even though ctx is cancelled.
    s.env.OnActivity(orderworkflow.ReleaseInventory, mock.Anything, mock.Anything).
        Return(nil, nil)

    s.env.ExecuteWorkflow(orderworkflow.ProcessOrder, orderworkflow.ProcessOrderInput{
        OrderID:    "order-1",
        CustomerID: "cust-1",
        Items:      []orderworkflow.Item{{ProductID: "prod-1", Quantity: 2, Price: 50.0}},
    })

    s.True(s.env.IsWorkflowCompleted())
    s.Error(s.env.GetWorkflowError())
    // Verify the compensation activity was called despite workflow cancellation.
    s.env.AssertExpectations(s.T())
}

func TestOrderWorkflow(t *testing.T) {
    suite.Run(t, new(OrderWorkflowTestSuite))
}
```

### Activity Unit Tests

Test idempotency and retry behavior:

```go
func (s *ActivityTestSuite) TestProcessPayment_Idempotent() {
    // Call twice with same workflow context — should produce same result.
    s.env.OnActivity(orderworkflow.ProcessPayment, mock.Anything, mock.Anything).
        Return(&orderworkflow.ProcessPaymentOutput{TransactionID: "txn-1"}, nil).
        Twice()

    // Verify payment service receives same idempotency key on retry.
}

func (s *ActivityTestSuite) TestValidateOrder_NonRetryable() {
    s.env.OnActivity(orderworkflow.ValidateOrder, mock.Anything, mock.Anything).
        Return(nil, temporal.NewNonRetryableApplicationError("bad input", "VALIDATION_ERROR", nil))

    // Verify workflow fails immediately without retrying.
}
```

### Replay Tests (Determinism Verification)

```go
func TestReplayProcessOrder(t *testing.T) {
    replayer := worker.NewWorkflowReplayer()
    replayer.RegisterWorkflow(orderworkflow.ProcessOrder)

    // Replay from recorded history file.
    err := replayer.ReplayWorkflowHistoryFromJSONFile(nil, "testdata/process_order_history.json")
    require.NoError(t, err, "workflow replay must succeed — determinism violation detected")
}
```

Export history from Temporal CLI:
```bash
temporal workflow show --workflow-id order-process-123 --output json > testdata/process_order_history.json
```

---

## 12. Service Directory Structure (with Temporal)

### Complete Layout

```
service/
├── cmd/
│   ├── root.go
│   ├── serve.go          # Bootstrap with temporalfx.Module
│   └── worker.go         # Worker-only command (optional)
├── internal/
│   ├── config/
│   │   └── configuration.go   # Embeds temporal.Config
│   ├── di/
│   │   ├── http/module.go
│   │   ├── grpc/module.go
│   │   ├── postgres/module.go
│   │   └── temporal/
│   │       └── module.go       # Registrar constructors (optional, can inline)
│   ├── core/                   # Domain layer (NO Temporal deps)
│   │   └── order/
│   │       ├── order.go
│   │       └── errors.go
│   ├── services/               # Service layer (starts workflows)
│   │   └── order/
│   │       ├── service.go
│   │       ├── default.go      # Uses temporalClient.ExecuteWorkflow
│   │       └── instrumented.go
│   ├── orchestration/          # Temporal orchestration
│   │   ├── workflows/          # Workflow definitions
│   │   │   └── order/
│   │   │       ├── types.go        # Input/Output structs
│   │   │       ├── workflow.go     # Workflow function(s)
│   │   │       └── workflow_test.go
│   │   └── activities/         # Activity implementations
│   │       └── order/
│   │           ├── types.go        # Input/Output structs
│   │           ├── activities.go   # Activity struct with methods
│   │           └── activities_test.go
│   ├── handlers/
│   │   ├── grpc/
│   │   └── http/
│   └── repo/
├── config/
│   └── configuration.yaml
├── testdata/
│   └── replay/                 # Workflow history JSON for replay tests
└── test/
```

### Key Boundaries

- **`internal/core/`** — Zero Temporal imports. Pure domain.
- **`internal/services/`** — May import `client.Client` to start workflows. No workflow/activity logic.
- **`internal/orchestration/workflows/`** — Only `workflow.*` SDK imports + `common/temporal` for options/retry.
- **`internal/orchestration/activities/`** — Import services/repos. Use `activity.*` for heartbeat/info. Use `common/temporal` for error classification.

---

## Quick Reference Card

### Imports Cheat Sheet

```go
// Configuration
"gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal"          // Config, NewClient, NewWorker, options, retry

// Fx DI
temporalfx "gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal/fx"   // Module, Provide*Registrar

// Registration
"gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal/registry"  // WorkflowRegistrar, ActivityRegistrar

// Tracing
temporalotel "gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal/otel" // TracingConfig

// Identity
"gitlab.com/umo-tech-ltd-group/platform/devkit/common/temporal/identity"  // identity.New

// SDK types (allowed in services)
"go.temporal.io/sdk/workflow"      // workflow.Context, workflow.GetLogger, etc.
"go.temporal.io/sdk/activity"      // activity.GetInfo, activity.RecordHeartbeat
temporalsdk "go.temporal.io/sdk/temporal"  // RetryPolicy, NonRetryableApplicationError
"go.temporal.io/sdk/client"        // client.StartWorkflowOptions (types only)
```

### Defaults at a Glance

| Default | Value |
|---------|-------|
| `ScheduleToStartTimeout` | 10 min |
| `StartToCloseTimeout` | 5 min |
| `HeartbeatTimeout` | 30 sec |
| `RetryPolicy.InitialInterval` | 1 sec |
| `RetryPolicy.BackoffCoefficient` | 2.0 |
| `RetryPolicy.MaximumInterval` | 1 min |
| `RetryPolicy.MaximumAttempts` | 5 |
| `ConnectTimeout` | 10 sec |

### Shutdown Order

| Priority | Component | Hook Type |
|----------|-----------|-----------|
| 10 (`PriorityServer`) | Temporal worker | `platformfx.ServerHook` |
| 60 (`PriorityDatabase`) | Temporal client | `platformfx.DatabaseHook` |

Worker drains in-flight tasks first, then client connection closes.
