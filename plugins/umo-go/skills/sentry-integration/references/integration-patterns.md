# Sentry Integration Patterns Reference

## Config Struct Reference

### `sentry.Config` (devkit/common/sentry/config.go)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Enabled` | `bool` | `true` | Master toggle. Set to false to disable entirely. |
| `DSN` | `string` | `""` | Sentry project DSN. Also auto-read from `SENTRY_DSN` by SDK. |
| `Debug` | `bool` | `false` | Enable SDK debug logging to stdout. |
| `Environment` | `string` | `""` | Deployment environment. Also auto-read from `SENTRY_ENVIRONMENT`. |
| `Release` | `string` | `""` | Release version. Also auto-read from `SENTRY_RELEASE`. |
| `ServerName` | `string` | `""` | Server hostname (auto-detected if empty). |
| `SampleRate` | `float64` | `1.0` | Error event sample rate (0.0-1.0). |
| `EnableTracing` | `bool` | `false` | Enable Sentry performance tracing. |
| `TracesSampleRate` | `float64` | `0.1` | Transaction sample rate (0.0-1.0). |
| `AttachStacktrace` | `bool` | `true` | Attach stack traces to messages. |
| `SendDefaultPII` | `bool` | `false` | Include PII (headers, IPs). |
| `MaxBreadcrumbs` | `int` | `100` | Max breadcrumbs to capture. |
| `FlushTimeout` | `time.Duration` | `5s` | Max wait for event delivery on shutdown. |
| `IgnoreErrors` | `[]string` | `nil` | Regex patterns for errors to ignore. |

## gRPC Interceptor Options

### `sentrygrpc.ServerOption` (devkit/common/sentry/grpc/options.go)

| Option | Default | Description |
|--------|---------|-------------|
| `WithServerSkipper(fn)` | `nil` | Skip methods (compatible with `grpcserver.SkipHealthChecks()`). |
| `WithRepanic(bool)` | `true` | Re-panic after capture (let Recovery handle gRPC response). |
| `WithWaitForDelivery(bool)` | `false` | Block until event is sent. |
| `WithDeliveryTimeout(dur)` | `2s` | Timeout for blocking delivery. |
| `WithReportOn(fn)` | `DefaultReportOn` | Filter which gRPC codes trigger capture. |

### Default `ReportOn` Codes

Only these codes are captured by default:

- `codes.Internal` -- Server-side bugs
- `codes.Unknown` -- Unhandled errors
- `codes.DataLoss` -- Data corruption
- `codes.Unavailable` -- Service down

Not captured (expected application behavior):

- `codes.InvalidArgument`, `codes.NotFound`, `codes.PermissionDenied`
- `codes.AlreadyExists`, `codes.FailedPrecondition`, `codes.Unauthenticated`
- `codes.ResourceExhausted`, `codes.Unimplemented`, `codes.Cancelled`
- `codes.DeadlineExceeded`, `codes.Aborted`, `codes.OutOfRange`

### Custom ReportOn Example

```go
// Capture all non-OK codes
sentrygrpc.WithReportOn(func(code codes.Code) bool {
    return code != codes.OK
})

// Capture Internal + Unavailable only
sentrygrpc.WithReportOn(func(code codes.Code) bool {
    return code == codes.Internal || code == codes.Unavailable
})
```

## Custom BeforeSend Hooks

Use `WithBeforeSend` to filter or modify events before they are sent:

```go
import (
    "gitlab.com/umo-tech-ltd-group/platform/devkit/common/sentry"
    gosentry "github.com/getsentry/sentry-go"
)

sentry.Init(cfg,
    sentry.WithBeforeSend(func(event *gosentry.Event, hint *gosentry.EventHint) *gosentry.Event {
        // Drop events from known noisy sources
        if event.Message == "context canceled" {
            return nil
        }

        // Strip sensitive data from extras
        delete(event.Extra, "password")

        return event
    }),
)
```

## Context Enrichment

The interceptor and helper functions automatically enrich Sentry scope with:

| Tag | Source | Description |
|-----|--------|-------------|
| `trace_id` | `logctx.TraceID(ctx)` | OpenTelemetry trace ID |
| `span_id` | `logctx.SpanID(ctx)` | OpenTelemetry span ID |
| `tenant_id` | `xctx.MustTenantID(ctx)` | Multi-tenant identifier |
| `request_id` | `xctx.MustRequestID(ctx)` | Unique request identifier |
| `correlation_id` | `xctx.MustCorrelationID(ctx)` | Cross-service correlation |
| `grpc.method` | `info.FullMethod` | Full gRPC method path |
| `grpc.service` | Parsed from method | gRPC service name |
| `grpc.method_name` | Parsed from method | gRPC method name |
| `grpc.status_code` | `status.Code(err)` | gRPC status code (on error) |

Additionally, `sentry.User` is set with:
- `ID` from `xctx.UserID(ctx)`
- `Data.tenant_id` from `xctx.TenantID(ctx)`

## Interceptor Chain Positioning

```
Position 1: Recovery        -- Catches panics, converts to codes.Internal
Position 2: Tracing         -- Creates OTel spans, extracts trace context
Position 3: Sentry          -- Captures errors/panics with trace context
Position 4: Logging         -- Logs requests with trace_id, span_id
Position 5: Metrics         -- Records Prometheus metrics
Position 6: RequestID       -- Generates/extracts request IDs
Position 7: Validation      -- Validates request payloads
```

Sentry at position 3 ensures:
- Trace context is available from Tracing (position 2)
- Panics are captured before Recovery (position 1) converts them
- Errors from downstream interceptors bubble up through Sentry

## Shutdown Order

```
Priority 10:  gRPC server stops accepting requests
Priority 60:  Database connections close
Priority 90:  OTel tracer exporter flushes spans
Priority 95:  Sentry flushes buffered events
Priority 100: Logger syncs remaining logs
```

## Testing with Mock Transport

For unit tests, use Sentry's `HTTPSyncTransport` to capture events synchronously:

```go
func TestSentryCapture(t *testing.T) {
    transport := sentry.NewHTTPSyncTransport()
    transport.Timeout = time.Second

    err := sentry.Init(sentry.ClientOptions{
        Dsn:       "https://key@sentry.example.com/1",
        Transport: transport,
    })
    require.NoError(t, err)

    sentry.CaptureMessage("test")
    sentry.Flush(time.Second)
}
```

For integration tests that don't send real events, leave the DSN empty -- all operations become no-ops.

## Release Tracking

Set the release version via build-time ldflags for proper Sentry release association:

```bash
go build -ldflags='-X main.release=my-service@1.0.0' -o bin/service ./cmd
```

Then pass it to the config:

```go
var release string // Set by ldflags

cfg.Sentry.Release = release
```

Or set via environment variable:

```bash
export SENTRY_RELEASE="my-service@1.0.0"
```
