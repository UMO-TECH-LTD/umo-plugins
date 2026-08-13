---
name: go-google-style
description: Comprehensive Go development guidance following Google Go Style Guide. Use when writing new Go code, reviewing existing Go code, refactoring Go projects, or answering questions about Go style and best practices. Automatically apply these guidelines when creating or modifying .go files, providing code review feedback, or discussing Go programming patterns. Covers naming conventions, error handling, formatting, testing, documentation, concurrency, and idiomatic Go patterns.
license: MIT
metadata:
  language: go
  tags: [go, style-guide, best-practices, idiomatic]
---

# Go Development - Google Style Guide

## Overview

This skill provides comprehensive guidance for writing idiomatic Go code following the Google Go Style Guide. It covers three key areas:

1. **Style Guide** - Foundational principles and canonical rules
2. **Style Decisions** - Specific decisions on style points with detailed reasoning
3. **Best Practices** - Common patterns that solve problems effectively

Apply these guidelines when writing new code, reviewing pull requests, or refactoring existing Go projects.

## Core Style Principles

Apply these principles in priority order when making style decisions:

1. **Clarity** - Code purpose and rationale are understandable to readers
2. **Simplicity** - Goals achieved in the most straightforward way
3. **Concision** - High signal-to-noise ratio
4. **Maintainability** - Code easily modified by future programmers
5. **Consistency** - Aligns with broader codebase patterns

### Quick Principle Guidelines

**Clarity:**
- Answer "What is the code doing?" and "Why?"
- Use descriptive names, helpful comments, efficient organization
- Document nuances not obvious from code

**Simplicity:**
- Write code readable from top to bottom
- Prefer: core language → standard library → internal libraries
- Justify complexity with documentation and tests

**Concision:**
- Reduce repetitive code (table-driven tests)
- Use common idioms (standard error handling)
- Remove extraneous syntax

**Maintainability:**
- Structure APIs for graceful growth
- Make assumptions explicit
- Write comprehensive tests with clear failure diagnostics

**Consistency:**
- Package-level consistency most important
- Use consistency to break ties between valid approaches

## Essential Quick Reference

### Naming Rules

| Element | Rule | Example |
|---------|------|---------|
| Package | lowercase, no underscores | `tabwriter`, `oauth2` |
| Multi-word package | unbroken lowercase | `tabwriter` not `tab_writer` |
| Receiver | 1-2 letters, type abbreviation | `t *Tray`, `ri *ResearchInfo` |
| Constants | MixedCaps, by role not value | `MaxPacketSize` not `MAX_PACKET_SIZE` |
| Initialisms | Consistent case | `URL` or `url`, never `Url` |
| Getters | No "Get" prefix | `Counts()` not `GetCounts()` |
| Variables | Length ∝ scope | Small scope: `i`, large scope: `authenticatedUserCount` |

**Avoid repetition:**
```go
// Bad
widget.NewWidget()
func (w *Widget) WidgetName() string

// Good
widget.New()
func (w *Widget) Name() string
```

### Error Handling

**Return pattern:**
```go
// Errors always last, return nil on success
func Process(data []byte) (Result, error)
```

**Error strings:**
```go
// Good - lowercase, no punctuation
fmt.Errorf("failed to connect to database")

// Bad
fmt.Errorf("Failed to connect to database.")
```

**Error flow:**
```go
// Good - check errors first, normal code after
result, err := DoSomething()
if err != nil {
    return err
}
processResult(result)

// Bad - normal code in else
if err == nil {
    processResult(result)
} else {
    return err
}
```

**Error wrapping:**
```go
// Use %w for inspection, %v for simple annotation
return fmt.Errorf("loading config: %w", err)  // Allows errors.Is/As
return fmt.Errorf("failed to save user: %v", err)  // Simple message
```

### Formatting Essentials

**Core rules:**
- All code must conform to `gofmt` output
- Use `MixedCaps` or `mixedCaps` for multi-word names
- No fixed line length limit
- Field names required for external package types

**Literals:**
```go
// Good - closing brace matches opening indentation
items := []Item{
    {Name: "foo"},
    {Name: "bar"},
}

// Good - omit repeated types
items := []*Item{
    {Name: "foo"},
    {Name: "bar"},
}
```

### Function Guidelines

**Signature formatting:**
- Keep on single line when possible
- Extract variables to shorten argument lists
- Use option structs for many parameters

**Context and errors:**
```go
// Context always first, errors always last
func Process(ctx context.Context, data []byte) (*Result, error)
```

### Testing Patterns

**Convention:** devkit and saas standardize on `stretchr/testify` (`assert`/`require`) for test assertions — use it for new tests instead of raw `if`/`t.Errorf` chains or hand-rolled assertion helpers, to stay consistent with the existing suite.

**Test failure format:**
```go
// Format: FunctionName(inputs) = got, want expected
t.Errorf("Parse(%q) = %v, want %v", input, got, want)
```

**`require` vs `assert`:**

| Function family | Behavior | Use for |
|---|---|---|
| `require.*` | Stops the test immediately | Preconditions/setup (e.g. `require.NoError(t, err)` before using the result) |
| `assert.*` | Records failure, keeps going | Value checks you want reported even if others also fail |

**Error handling in tests:**
- Use `t.Error` + `continue` for table entries without subtests
- Use `t.Fatal`/`require.*` in subtests (inside `t.Run`) and in helpers when setup fails
- Never call `t.Fatal` from goroutines
- Never string-match `err.Error()` to distinguish error kinds — use `errors.Is`/`assert.ErrorIs`, or a `wantErr bool` table field when only presence/absence matters

**Comparisons:**
```go
// Scalars and comparable structs
assert.Equal(t, want, got)

// Proto messages / cmp-only comparisons
if diff := cmp.Diff(want, got, protocmp.Transform()); diff != "" {
    t.Errorf("Result mismatch (-want +got):\n%s", diff)
}
```

## Code Review Checklist

Use this checklist when reviewing Go code:

### Naming
- [ ] Package names lowercase, no underscores, not generic (`util`, `common`, `helper`)
- [ ] Receiver names consistent across all methods (1-2 letters)
- [ ] Constants use MixedCaps, named by role
- [ ] Initialisms have consistent case (`URL` not `Url`)
- [ ] No "Get" prefix on getters unless concept requires it
- [ ] Variable names appropriate for scope size
- [ ] No redundant repetition in names (package/type/context)

### Error Handling
- [ ] Errors returned as last parameter
- [ ] Error strings lowercase, no punctuation
- [ ] Errors checked before proceeding with normal code
- [ ] `%w` used for wrapping when inspection needed, `%v` for simple annotation
- [ ] Errors documented when significant
- [ ] No duplicate logging (return or log, not both)

### Functions & Structure
- [ ] Context is first parameter (when applicable)
- [ ] Long parameter lists converted to option structs
- [ ] `context.Context` never in struct members
- [ ] Function signatures on single line when possible

### Interfaces & Types
- [ ] Interfaces defined in consuming package, not implementing package
- [ ] Return concrete types, not interfaces
- [ ] Receiver types consistent (all pointer or all value)
- [ ] No copying of types with `sync.Mutex` or similar

### Concurrency
- [ ] Goroutine lifetimes clear and documented
- [ ] Channel directions specified (send-only/receive-only)
- [ ] Concurrency safety documented when non-obvious

### Testing
- [ ] Test helpers call `t.Helper()`
- [ ] Test failure messages include function, inputs, got, want
- [ ] Comparisons use testify `assert.Equal`/`require.Equal` (or `cmp.Diff` for proto/complex types)
- [ ] `require` used for preconditions/setup, `assert` used for value checks that should continue
- [ ] Tests continue after failures to report all issues
- [ ] No `t.Fatal` called from goroutines
- [ ] Errors validated via `errors.Is`/`assert.ErrorIs` or `wantErr bool` — never string-matched
- [ ] Subtest names are identifier-like (no slashes, not prose)
- [ ] Setup scoped to specific tests, not package-level

### Documentation
- [ ] All exported names have doc comments
- [ ] Doc comments are complete sentences starting with name
- [ ] Comments avoid restating obvious
- [ ] Cleanup requirements clearly explained
- [ ] Package comments appear immediately before package clause

### Common Mistakes
- [ ] No `panic` for normal error handling
- [ ] Nil slices use `var s []T` not `s := []T{}`
- [ ] No dot imports (`import .`)
- [ ] Blank imports only in main packages/tests
- [ ] No `math/rand` for cryptographic keys (use `crypto/rand`)
- [ ] Imports grouped: stdlib, project, protos, side-effects
- [ ] Flag names use snake_case, variables use camelCase

## Detailed References

For comprehensive guidance on specific topics, see:

### Style Decisions Reference

**File:** `references/style-decisions.md`

**When to read:** When you need detailed rules and specific decisions on:
- Naming conventions (packages, receivers, constants, variables)
- Error handling patterns and flows
- Formatting and literal syntax
- Function and control flow
- Imports and packages organization
- Language features (panic, goroutines, interfaces, generics)
- Commentary and documentation
- Common libraries (flags, logging, contexts, crypto/rand)
- Testing requirements and assertions

**Contents:**
- Complete naming rules with examples
- Error handling patterns
- Formatting guidelines
- Function design rules
- Import organization
- Language feature usage
- Testing standards
- Quick reference table

### Best Practices Reference

**File:** `references/best-practices.md`

**When to read:** When you need recommended patterns and practices for:
- Advanced naming strategies
- Package organization and structure
- Structured error handling and wrapping
- Documentation best practices
- Variable declaration patterns
- Function design with options
- Testing strategies and helpers
- String operations optimization
- Global state management
- Concurrency patterns

**Contents:**
- Naming best practices and test doubles
- Package organization strategies
- Error handling patterns (wrapping, logging, panics)
- Documentation guidelines and Godoc formatting
- Variable declarations and preallocation
- Function design (option structs, variadic patterns)
- Testing best practices (helpers, validation APIs, structure)
- String concatenation optimization
- Global state guidelines
- Concurrency with errgroup
- Summary checklist

## Utility Library Conventions

### Pointer Helpers — use `samber/lo` (not hand-rolled)

All Go services use `github.com/samber/lo` (zero external deps, MIT) as the canonical source for pointer utilities. **Do not write local `StrPtr`, `BoolPtr`, or `Ptr[T]` helpers** — they are redundant.

| Use case | Correct approach |
|----------|-----------------|
| Create a pointer from a value | `lo.ToPtr(value)` |
| Safely dereference (zero value if nil) | `lo.FromPtr(ptr)` |
| Dereference with explicit fallback | `lo.FromPtrOr(ptr, fallback)` |
| Slice of values → slice of pointers | `lo.ToSlicePtr(slice)` |
| Non-zero value → pointer, zero → `nil` | `lo.EmptyableToPtr(x)` (values; not a `MapNil` substitute) |
| Transform `*T` → `*R` only if `*T` non-nil (do not call `fn` on nil) | `ptr.MapNil(p, fn)` from `gitlab.com/umo-tech-ltd-group/platform/devkit/common/ptr` |
| Same, callback can return `error` | `ptr.MapNilErr(p, fn)` from `devkit/common/ptr` |

```go
// Good — idiomatic, zero ceremony
pm.MinBaseAmount = lo.ToPtr(amount.String())
name := lo.FromPtrOr(req.Name, "anonymous")

// Bad — hand-rolled duplicates
func StrPtr(s string) *string { return &s }
func Ptr[T any](v T) *T { return &v }
```

#### Nil-safe `*T` → `*R` maps — **not** in `lo`

`samber/lo` exposes pointer **primitives** (`ToPtr`, `FromPtr`, `FromPtrOr`, `EmptyableToPtr`, etc.) but **no** built-in that matches `MapNil` / `MapNilErr`: “if `p == nil` return `(nil, nil)` and **do not** invoke the mapper.”

**Do not** fake `MapNil` with `lo.ToPtr(fn(lo.FromPtr(p)))` — for `p == nil`, `FromPtr` yields the zero value of `T`, so **`fn` would still run**, which is usually wrong.

**Do** use `devkit/common/ptr`:

```go
out := ptr.MapNil(label, func(v string) int { return len(v) })
parsed, err := ptr.MapNilErr(digits, strconv.Atoi) // *string → *int, nil-safe
```

Keep service-local copies of `MapNil` / `MapNilErr` only when the service cannot depend on devkit yet; prefer the shared package otherwise.

> `devkit/common/ptr` and `lo` complement each other: **`lo`** for create/deref/copy patterns, **`ptr`** for optional pointer transforms.

### Collection Utilities — prefer stdlib `slices`/`maps` first

All services run Go 1.21+, which ships `slices` and `maps` stdlib packages. **Reach for stdlib before lo for collection operations.**

| Use case | Correct approach |
|----------|-----------------|
| Check if element exists | `slices.Contains(s, v)` ✅ stdlib |
| Sort a slice | `slices.Sort(s)` ✅ stdlib |
| Map keys / values | `maps.Keys(m)`, `maps.Values(m)` ✅ stdlib |
| Remove duplicates | `lo.Uniq(s)` — no stdlib equivalent |
| Group by key | `lo.GroupBy(s, fn)` — no stdlib equivalent |
| Filter + map in one pass | `lo.FilterMap(s, fn)` — no stdlib equivalent |
| Deduplicate by field | `lo.UniqBy(s, fn)` — no stdlib equivalent |

```go
// Good — stdlib for simple contains check
if slices.Contains(allowedStatuses, status) { ... }

// Good — lo for operations with no stdlib equivalent
byTenant := lo.GroupBy(accounts, func(a Account) string { return a.TenantID })
unique   := lo.Uniq(ids)
```

**Explicit for-loops are always acceptable.** Use lo collection helpers only when they meaningfully reduce complexity — not just to avoid a loop.

### Never use lo.Must / lo.Try

`lo.Must` panics on error. `lo.Try` swallows errors as booleans. Both patterns obscure error handling and violate Go conventions. Use explicit error returns instead.

```go
// Bad — hides errors, can panic in production
val := lo.Must(strconv.Atoi(s))
ok := lo.Try(func() error { return riskyOp() })

// Good — explicit, inspectable
val, err := strconv.Atoi(s)
if err != nil {
    return fmt.Errorf("parse value: %w", err)
}
```

### Code Review Checklist Addition

When reviewing Go code, also check:
- [ ] No hand-rolled `StrPtr`, `BoolPtr`, `IntPtr`, `Ptr[T]` helpers — use `lo.ToPtr`
- [ ] No fake `MapNil` via `lo.FromPtr` + `fn` without an explicit `p == nil` branch (prefer `devkit/common/ptr`)
- [ ] `slices.Contains` / `slices.Sort` / `maps.Keys` used before reaching for lo equivalents
- [ ] `lo.Must` and `lo.Try` are absent
- [ ] `devkit/common/ptr` used for nil-safe pointer transformation (`MapNil`, `MapNilErr`)

## Configuration Conventions (devkit/common v0.17.0+)

All Go services in this monorepo MUST follow the declarative configuration pattern using `config.Load[T]()` from `devkit/common/config`. When writing or reviewing config code, enforce these rules:

### Struct Tags

Every config struct field MUST have a `mapstructure` tag. Use `default` tags for universal defaults:

```go
// Good — declarative, self-documenting
type PostgresConfig struct {
    Host     string `mapstructure:"host"     default:"postgres"`
    Port     int    `mapstructure:"port"     default:"5432"`
    SSLMode  string `mapstructure:"ssl_mode" default:"disable"`
}

// Bad — manual defaults, error-prone, verbose
v.SetDefault("postgres.host", "postgres")
v.SetDefault("postgres.port", 5432)
```

### Value Types (Not Pointers)

Config sub-structs MUST be value types. This eliminates nil checks in DI modules:

```go
// Good — value type, always initialized
type Config struct {
    Postgres PostgresConfig `mapstructure:"postgresql"`
    Redis    RedisConfig    `mapstructure:"redis"`
}

// Bad — pointer type, requires nil checks everywhere
type Config struct {
    Postgres *PostgresConfig `mapstructure:"postgresql"`
    Redis    *RedisConfig    `mapstructure:"redis"`
}
```

### Config Loading

Use `config.Load[T]()` with functional options. Never import `viper` directly in service config packages:

```go
// Good — declarative, minimal
cfg, _, err := config.Load[Config](
    config.WithEnvironmentFile("ENVIRONMENT", "./configs"),
    config.WithDefaults(defaults()),
    config.WithRedactKeys("postgresql.password"),
)

// Bad — manual Viper, verbose, error-prone
v := viper.New()
v.SetConfigName("local")
v.AddConfigPath("./configs")
v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
v.AutomaticEnv()
// ... 50+ more lines of SetDefault/BindEnv
```

### YAML Key Naming

YAML keys MUST match `mapstructure` tags — underscore-separated, not dot-separated:

```yaml
# Good
sentry:
  sample_rate: 1.0
  traces_sample_rate: 0.1

# Bad (legacy dot-separated)
sentry:
  sample:
    rate: 1.0
```

### Review Checklist Addition

When reviewing config code, also check:
- [ ] No direct `viper` import in service config package
- [ ] All struct fields have `mapstructure` tags
- [ ] `default` tags used instead of manual `SetDefault()` calls
- [ ] Sub-configs are value types (not pointers)
- [ ] YAML keys use underscores, not dots
- [ ] devkit/common config types embedded directly (not wrapped in local structs)
- [ ] `EnvBinder`-implementing types not duplicated with manual `BindEnv` calls

## Usage Examples

### Writing New Code

When writing new Go code:

1. **Start with clear naming** - Use package context, avoid redundancy
2. **Handle errors properly** - Return errors, use `%w` for wrapping
3. **Format with gofmt** - Let tooling handle formatting
4. **Write tests first or alongside** - Use table-driven tests
5. **Document exported APIs** - Doc comments for all exported names

**Example:**
```go
// Package user provides user management functionality.
package user

import (
    "context"
    "fmt"
)

// ErrNotFound indicates the requested user doesn't exist.
var ErrNotFound = errors.New("not found")

// Find retrieves a user by ID.
// Returns ErrNotFound if the user doesn't exist.
func Find(ctx context.Context, id int) (*User, error) {
    u, err := db.Query(ctx, id)
    if err != nil {
        if errors.Is(err, sql.ErrNoRows) {
            return nil, ErrNotFound
        }
        return nil, fmt.Errorf("query user: %w", err)
    }
    return u, nil
}
```

### Code Review

When reviewing Go code:

1. **Check against the Code Review Checklist** (above)
2. **Apply the Core Style Principles** in priority order
3. **Refer to Style Decisions reference** for specific rules
4. **Refer to Best Practices reference** for recommended patterns
5. **Focus on clarity, simplicity, and maintainability**

**Common review feedback patterns:**
```go
// Naming - avoid repetition
// Before: func (u *User) GetUserName() string
// Feedback: Remove "Get" prefix and "User" redundancy
// After: func (u *User) Name() string

// Error handling - check first
// Before:
if err == nil {
    process(result)
} else {
    return err
}
// Feedback: Check error first, normal code after
// After:
if err != nil {
    return err
}
process(result)

// Testing - use proper format
// Before: t.Errorf("unexpected result")
// Feedback: Include function, inputs, got, want
// After: t.Errorf("Parse(%q) = %v, want %v", input, got, want)
```

### Refactoring

When refactoring Go code:

1. **Identify violations** using Code Review Checklist
2. **Prioritize changes** by principles: clarity → simplicity → concision
3. **Maintain consistency** with existing patterns unless they violate guidelines
4. **Add tests** before refactoring if coverage is insufficient
5. **Document rationale** for complex changes

**Focus areas:**
- Long functions → extract smaller focused functions
- Large parameter lists → option structs
- Repeated error handling → helper functions (return errors)
- Missing tests → add table-driven tests
- Poor naming → rename for clarity and context
- Global state → instance-based APIs

## Summary

This skill enables you to:
- Write idiomatic Go code following Google's style guide
- Review Go code against established best practices
- Refactor Go projects for clarity, simplicity, and maintainability
- Apply consistent naming, error handling, and testing patterns
- Make informed decisions on Go language features and patterns

When in doubt:
1. Prioritize clarity over cleverness
2. Choose simplicity over abstraction
3. Follow established patterns in the codebase
4. Refer to the detailed references for specific guidance
