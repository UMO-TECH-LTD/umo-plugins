# Go Best Practices - Patterns & Recommendations

This document contains recommended patterns and practices from the Google Go Style Guide. These are encouraged but not mandatory.

## Table of Contents

- [Naming Best Practices](#naming-best-practices)
- [Package Organization](#package-organization)
- [Error Handling Patterns](#error-handling-patterns)
- [Documentation Best Practices](#documentation-best-practices)
- [Variable Declarations](#variable-declarations)
- [Function Design](#function-design)
- [Testing Best Practices](#testing-best-practices)
- [String Operations](#string-operations)
- [Global State](#global-state)
- [Concurrency](#concurrency)

---

## Naming Best Practices

### Function & Method Names

**Avoid repetition:**
- Package names
- Receiver types
- Parameter names
- Return value types

**Examples:**
```go
// Bad - repetitive
package user
func (u *User) GetUserName() string

// Good
package user
func (u *User) Name() string
```

**Naming style:**
- **Noun-like names** for functions returning values
- **Verb-like names** for functions performing actions

**Examples:**
```go
// Good - returns value
func Count() int
func Status() string

// Good - performs action
func Process() error
func Save() error
```

**Type differentiation:**
Include type names at the end when functions differ only by types.

**Examples:**
```go
func ParseInt(s string) (int, error)
func ParseFloat(s string) (float64, error)
func ParseBool(s string) (bool, error)
```

### Test Doubles & Helpers

**Test helper packages:**
Append "test" to package name.

**Examples:**
```go
package creditcardtest  // Test helpers for creditcard package
package usertest        // Test helpers for user package
```

**Test double naming:**
Name by behavior they emulate.

**Examples:**
```go
// Good - describes behavior
type AlwaysChargesCard struct{}
type AlwaysDeclinesCard struct{}
type NetworkErrorAPI struct{}

// Bad - generic
type FakeCard struct{}
type MockAPI struct{}
```

**Local test variables:**
Use prefixed names to differentiate from production types.

**Examples:**
```go
// Good - clear distinction
func TestProcess(t *testing.T) {
    stubDB := &StubDatabase{}
    fakeCache := &FakeCache{}
    realProcessor := processor.New(stubDB, fakeCache)
}
```

### Shadowing & Variable Scope

**Distinguish:**
- **Stomping:** Reassigning in same scope
- **Shadowing:** Creating new variable in nested scope

**Examples:**
```go
// Stomping - same scope
var count int
count = 5
count = 10  // Stomping

// Shadowing - nested scope
var count int = 5
if true {
    count := 10  // Shadows outer count
    fmt.Println(count)  // 10
}
fmt.Println(count)  // 5
```

**Avoid shadowing standard packages:**

**Examples:**
```go
// Bad
func ProcessURL(url string) {
    // "url" package is now inaccessible
    parsed, _ := url.Parse(url)  // Won't compile
}

// Good
func ProcessURL(rawURL string) {
    parsed, _ := url.Parse(rawURL)
}
```

**Reassigning to outer scope:**
Use simple assignment `=` not `:=`.

**Examples:**
```go
var result int

if condition {
    // Good - reassign to outer scope
    var err error
    result, err = compute()
    if err != nil {
        return err
    }
}

// Bad - shadows outer result
if condition {
    result, err := compute()  // New result variable
    if err != nil {
        return err
    }
}  // Outer result unchanged
```

### Util Packages

**Rule:** Avoid generic names like "util", "helper", "common" for packages.

**Examples:**
```go
// Bad
package util
func ValidateEmail(email string) bool

// Good
package validation
func Email(email string) bool

// Bad
package common
func FormatCurrency(amount float64) string

// Good
package currency
func Format(amount float64) string
```

**Consider call site readability:**

**Examples:**
```go
// Bad
util.ValidateEmail(email)

// Good
validation.Email(email)

// Bad
common.FormatCurrency(amount)

// Good
currency.Format(amount)
```

---

## Package Organization

### Size Considerations

**Rules:**
- No strict line-count limits
- Avoid single files with thousands of lines
- Group related code by file
- Standard library's "bytes" package exemplifies good organization

**Example structure:**
```
bytes/
├── buffer.go       // Buffer type and methods
├── bytes.go        // Byte slice utilities
├── reader.go       // Reader type
└── bytes_test.go   // Tests
```

**Multiple package imports:**
If users need to import multiple packages together, consider combining them.

**Examples:**
```go
// Bad - always used together
import (
    "myapp/auth/login"
    "myapp/auth/session"
    "myapp/auth/token"
)

// Good - combined
import "myapp/auth"
```

### File Organization

**Rules:**
- Use `doc.go` for long package documentation
- Split large packages across multiple files by domain
- No "one type, one file" convention required

**Example:**
```
user/
├── doc.go          // Package documentation
├── user.go         // User type and core methods
├── auth.go         // Authentication-related methods
├── profile.go      // Profile management
└── user_test.go    // Tests
```

---

## Error Handling Patterns

### Structured Errors

**Rule:** Make errors interrogatable by code, not string matching.

**Simple cases - sentinel values:**
```go
var (
    ErrNotFound = errors.New("not found")
    ErrInvalid  = errors.New("invalid input")
)

func Find(id int) (*User, error) {
    if !exists(id) {
        return nil, ErrNotFound
    }
    // ...
}

// Usage
user, err := Find(123)
if errors.Is(err, ErrNotFound) {
    // Handle not found
}
```

**Complex cases - custom error types:**
```go
type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("%s: %s", e.Field, e.Message)
}

func Validate(user *User) error {
    if user.Email == "" {
        return &ValidationError{
            Field:   "email",
            Message: "required",
        }
    }
    return nil
}

// Usage
if err := Validate(user); err != nil {
    var validErr *ValidationError
    if errors.As(err, &validErr) {
        fmt.Printf("validation failed on %s\n", validErr.Field)
    }
}
```

**os.PathError pattern:**
```go
type DatabaseError struct {
    Op    string  // Operation: "read", "write", "delete"
    Table string
    Err   error
}

func (e *DatabaseError) Error() string {
    return fmt.Sprintf("database %s on %s: %v", e.Op, e.Table, e.Err)
}

func (e *DatabaseError) Unwrap() error {
    return e.Err
}
```

### Error Wrapping Guidelines

**Use `%v` when:**
- Simple annotation needed
- Transforming errors at system boundaries
- Caller doesn't need to inspect error

**Examples:**
```go
// Good - simple annotation
if err := saveUser(user); err != nil {
    return fmt.Errorf("failed to save user: %v", err)
}
```

**Use `%w` when:**
- Programmatic inspection needed
- Error chaining within application
- Caller may use `errors.Is` or `errors.As`

**Examples:**
```go
// Good - allows inspection
if err := db.Query(sql); err != nil {
    return fmt.Errorf("query failed: %w", err)
}

// Usage
if errors.Is(err, sql.ErrNoRows) {
    // Handle no rows
}
```

**Wrapping format:**
Place `%w` at the end of error strings.

**Examples:**
```go
// Good
return fmt.Errorf("failed to connect to database: %w", err)

// Bad
return fmt.Errorf("%w: additional context", err)
```

**Documentation:**
Document which errors your functions return.

**Examples:**
```go
// ProcessUser processes the user data.
// Returns ErrNotFound if user doesn't exist.
// Returns ErrInvalid if user data is invalid.
func ProcessUser(id int) error {
    // ...
}
```

### Adding Context to Errors

**Avoid redundancy:**
Don't repeat information already in underlying error.

**Examples:**
```go
// Bad - redundant "failed to open"
file, err := os.Open(path)
if err != nil {
    return fmt.Errorf("failed to open file: %w", err)
    // os.Open already says "open /path/to/file: no such file or directory"
}

// Good - adds new context
file, err := os.Open(configPath)
if err != nil {
    return fmt.Errorf("loading config: %w", err)
}
```

**Add meaningful context:**
Explain significance to current function.

**Examples:**
```go
// Good - explains why this matters
user, err := fetchUser(id)
if err != nil {
    return fmt.Errorf("cannot generate report without user data: %w", err)
}
```

### Error Logging

**Avoid duplicate logging:**
Let callers decide whether to log.

**Examples:**
```go
// Bad - logs and returns
func Process() error {
    if err := step1(); err != nil {
        log.Errorf("step1 failed: %v", err)  // Don't log here
        return err  // Caller will also log
    }
}

// Good - just return
func Process() error {
    if err := step1(); err != nil {
        return fmt.Errorf("step1: %w", err)
    }
}

// Caller decides
if err := Process(); err != nil {
    log.Errorf("process failed: %v", err)  // Log once
}
```

**Use verbose logging for tracing:**
```go
// Good - verbose logs for debugging
func Process() error {
    log.V(2).Info("starting process")
    if err := step1(); err != nil {
        log.V(1).Infof("step1 failed, retrying: %v", err)
        return err
    }
    log.V(2).Info("process completed")
}
```

**ERROR level usage:**
- Reserve for actionable messages
- Avoid performance-impacting flushes
- Be cautious with PII in logs

### Program Initialization & Panics

**Initialization errors:**
Propagate to `main` with actionable messages.

**Examples:**
```go
// Good
func main() {
    cfg, err := LoadConfig("config.yaml")
    if err != nil {
        log.Fatalf("Failed to load config: %v", err)
    }
    // ...
}

// Bad - panic
func main() {
    cfg := MustLoadConfig("config.yaml")  // Panics on error
}
```

**Use `log.Fatal` for invariant violations:**
```go
// Good
if dbConn == nil {
    log.Fatal("database connection is nil - this should never happen")
}

// Bad
if dbConn == nil {
    panic("database connection is nil")
}
```

**When panic is acceptable:**
- API misuse detected at code review/test time (like `reflect` package)
- Internal panic-recover pairs within packages
- Never crossing package boundaries

**Examples:**
```go
// Acceptable - API misuse
func SetTimeout(d time.Duration) {
    if d < 0 {
        panic("timeout cannot be negative")
    }
}

// Acceptable - internal use only
func parseInternal(data string) (result int) {
    defer func() {
        if r := recover(); r != nil {
            result = 0  // Convert panic to zero value
        }
    }()
    return riskyParse(data)  // May panic
}
```

---

## Documentation Best Practices

### Key Documentation Principles

**Avoid restating obvious:**
Document non-obvious behavior only.

**Examples:**
```go
// Bad - obvious
// Count returns the count.
func Count() int

// Good - adds value
// Count returns the number of active users in the last 24 hours.
func Count() int
```

**Context parameters:**
Only document special expectations.

**Examples:**
```go
// Good - special requirement
// Process processes the request.
// The context must include user authentication credentials.
func Process(ctx context.Context, req *Request) error

// Unnecessary - obvious
// Process processes the request with the given context.
func Process(ctx context.Context, req *Request) error
```

**Cleanup requirements:**
Clearly explain.

**Examples:**
```go
// Good
// Open opens a database connection.
// The caller must call Close on the returned DB when done.
func Open(dsn string) (*DB, error)
```

### Concurrency Documentation

**Default assumption:**
Read-only operations are safe for concurrent use.

**Document mutating operations:**
```go
// Add adds an item to the cache.
// Add is not safe for concurrent use.
func (c *Cache) Add(key string, value interface{})
```

**Document internal mutations:**
```go
// Get retrieves an item from the LRU cache.
// Get updates internal access tracking and is not safe for concurrent use.
func (c *LRUCache) Get(key string) (interface{}, bool)
```

### Error Documentation

**Document significant errors:**
```go
var (
    // ErrNotFound indicates the requested resource doesn't exist.
    ErrNotFound = errors.New("not found")

    // ErrInvalid indicates invalid input data.
    ErrInvalid = errors.New("invalid input")
)

// Find retrieves a user by ID.
// Returns ErrNotFound if the user doesn't exist.
func Find(id int) (*User, error)
```

**Pointer vs value receivers:**
```go
// GetError returns a ValidationError.
// The returned error should be compared using errors.As,
// as it is a pointer type.
func GetError() error {
    return &ValidationError{}  // Pointer
}
```

### Godoc Formatting

**Paragraph separation:**
Require blank lines between paragraphs.

**Examples:**
```go
// Package user provides user management.
//
// The package includes authentication, authorization,
// and profile management functionality.
//
// Example usage:
//
//     u, err := user.Find(123)
//     if err != nil {
//         log.Fatal(err)
//     }
package user
```

**Code examples:**
Indent by two spaces for verbatim formatting.

**Examples:**
```go
// Process processes a request.
//
// Example:
//
//     req := &Request{ID: 123}
//     if err := Process(req); err != nil {
//         log.Fatal(err)
//     }
func Process(req *Request) error
```

**Runnable examples:**
Include in test files.

**Examples:**
```go
// In user_test.go
func ExampleFind() {
    user, err := Find(123)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Println(user.Name)
    // Output: Alice
}
```

**Headers:**
Single-line capital-letter headers get auto-formatted.

**Examples:**
```go
// Package user provides user management.
//
// Authentication
//
// The package supports multiple authentication methods...
//
// Authorization
//
// Authorization is role-based...
```

### Signal Boosting

**Comment counterintuitive code:**

**Examples:**
```go
// Good - explain unexpected pattern
if err == nil {
    return fmt.Errorf("expected error but got nil")
}

// Good - explain non-obvious check
if user.IsAdmin {
    // Admins bypass validation
    return nil
}
```

---

## Variable Declarations

### Initialization Patterns

**Prefer `:=` for non-zero values:**
```go
// Good
name := "Alice"
count := 42

// Less good
var name string = "Alice"
var count int = 42
```

**Use zero-value declarations:**
```go
// Good - zero value is ready for use
var count int
var users []User
var m map[string]int
```

**Use composite literals:**
```go
// Good - initial elements known
users := []User{
    {Name: "Alice"},
    {Name: "Bob"},
}
```

**Use `new()` for zero-value pointers:**
```go
// Good - zero value pointer
config := new(Config)

// Also good - explicit initialization
config := &Config{}

// Good - non-zero initialization
config := &Config{
    Timeout: 30 * time.Second,
}
```

### Size Hints & Preallocation

**Preallocate when size is known:**
```go
// Good - size known from input
users := make([]User, 0, len(ids))
for _, id := range ids {
    users = append(users, User{ID: id})
}

// Good - size known from algorithm
items := make([]Item, 100)
for i := range items {
    items[i] = generateItem(i)
}
```

**Don't preallocate unnecessarily:**
```go
// Bad - premature optimization
data := make([]byte, 0, 1024)  // Why 1024?

// Good - let runtime grow
var data []byte
```

**Base on benchmarking:**
```go
// Only if benchmarks show benefit
const estimatedSize = 1000
items := make([]Item, 0, estimatedSize)
```

### Channel Directions

**Always specify direction:**
```go
// Good
func send(ch chan<- int, val int) {
    ch <- val
}

func receive(ch <-chan int) int {
    return <-ch
}

// Bad - bidirectional
func send(ch chan int, val int) {
    ch <- val
}
```

**Benefits:**
- Prevents accidental double-closes
- Signals ownership intent
- Compiler enforces usage

---

## Function Design

### Argument Lists

**Keep signatures manageable:**
```go
// Bad - too many parameters
func CreateUser(firstName, lastName, email, phone, address, city, state, zip string, age int, isActive bool) error

// Good - use struct
type UserInfo struct {
    FirstName string
    LastName  string
    Email     string
    Phone     string
    Address   Address
    Age       int
    IsActive  bool
}

func CreateUser(info UserInfo) error
```

**Consider splitting complex functions:**
```go
// Bad - complex signature
func ProcessReport(ctx context.Context, userID int, startDate, endDate time.Time, format string, includeDetails, includeCharts bool, filters []Filter) (*Report, error)

// Good - split by use case
func GenerateBasicReport(ctx context.Context, userID int, period Period) (*Report, error)
func GenerateDetailedReport(ctx context.Context, userID int, period Period, options ReportOptions) (*Report, error)
```

### Option Structures

**Use for optional/configuration arguments:**
```go
// Good
type ServerOptions struct {
    Port    int
    Timeout time.Duration
    TLS     *TLSConfig
}

func NewServer(addr string, opts ServerOptions) (*Server, error) {
    // Use opts.Port, opts.Timeout, etc.
    // Omitted fields get zero values
}

// Usage
srv, err := NewServer("localhost", ServerOptions{
    Port:    8080,
    Timeout: 30 * time.Second,
    // TLS omitted
})
```

**Benefits:**
- Self-documenting calls
- Allows omitting defaults
- Easy to extend

**Never put `context.Context` in options:**
```go
// Bad
type Options struct {
    ctx     context.Context  // Never do this
    Timeout time.Duration
}

// Good
func Process(ctx context.Context, opts Options) error
```

### Variadic Options Pattern

**Use when most callers need no options:**
```go
type Option func(*Server)

func WithPort(port int) Option {
    return func(s *Server) {
        s.port = port
    }
}

func WithTimeout(d time.Duration) Option {
    return func(s *Server) {
        s.timeout = d
    }
}

func NewServer(addr string, opts ...Option) *Server {
    s := &Server{
        addr:    addr,
        port:    8080,  // default
        timeout: 30 * time.Second,  // default
    }
    for _, opt := range opts {
        opt(s)
    }
    return s
}

// Usage
srv := NewServer("localhost")  // All defaults
srv := NewServer("localhost", WithPort(9090), WithTimeout(60*time.Second))
```

**Options should accept parameters:**
```go
// Good
func WithFailFast(enable bool) Option

// Bad - signals presence only
func WithFailFast() Option
```

**Trade-offs:**
- Requires boilerplate
- Use only when benefits justify overhead
- Best for packages with many optional configurations

---

## Testing Best Practices

### Test Helpers vs. Assertions

**Test helpers:**
Perform setup/cleanup, call `t.Helper()`.

**Examples:**
```go
// Good - test helper
func setupDatabase(t *testing.T) *sql.DB {
    t.Helper()
    db, err := sql.Open("sqlite3", ":memory:")
    if err != nil {
        t.Fatalf("failed to open database: %v", err)
    }
    t.Cleanup(func() { db.Close() })
    return db
}
```

**Assertions:**
Hand-rolled assertion *wrapper* functions (re-wrapping `t.Errorf` behind a custom name) are not idiomatic — they lose the call-site context Go's own error messages give you for free.

**Examples:**
```go
// Bad - assertion helper wraps t.Errorf and loses context
func assertEqual(t *testing.T, got, want int) {
    if got != want {
        t.Errorf("got %d, want %d", got, want)
    }
}

// Good - inline validation, no bespoke wrapper
func TestCount(t *testing.T) {
    got := Count()
    want := 5
    if got != want {
        t.Errorf("Count() = %d, want %d", got, want)
    }
}
```

**devkit/saas exception:** the rule above targets *bespoke* assertion helpers layered on top of `testing.T`, not the `stretchr/testify` library. This codebase has standardized on testify (`assert`/`require`) — use it directly rather than hand-rolling equivalents:

```go
// Good - testify used directly, no local wrapper
func TestCount(t *testing.T) {
    got := Count()
    assert.Equal(t, 5, got)
}
```

**Return errors from validation code:**
```go
// Good - returns error
func validateUser(u *User) error {
    if u.Name == "" {
        return errors.New("name is required")
    }
    return nil
}

// Usage in test
func TestUser(t *testing.T) {
    if err := validateUser(user); err != nil {
        t.Errorf("validation failed: %v", err)
    }
}
```

### Designing Validation APIs

**Acceptance test packages:**
```go
// Package usertest provides validation for user.Store implementations.
package usertest

func TestStore(t *testing.T, newStore func() user.Store) {
    store := newStore()

    // Test Create
    u := &user.User{Name: "Alice"}
    if err := store.Create(u); err != nil {
        t.Errorf("Create failed: %v", err)
    }

    // Test Get
    got, err := store.Get(u.ID)
    if err != nil {
        t.Errorf("Get failed: %v", err)
    }
    if diff := cmp.Diff(u, got); diff != "" {
        t.Errorf("Get mismatch (-want +got):\n%s", diff)
    }
}
```

**Validation function pattern:**
```go
// Good - returns errors
func ValidateConfig(cfg *Config) error {
    var errs []error

    if cfg.Port < 0 {
        errs = append(errs, fmt.Errorf("port must be non-negative"))
    }

    if cfg.Timeout < 0 {
        errs = append(errs, fmt.Errorf("timeout must be non-negative"))
    }

    if len(errs) > 0 {
        return fmt.Errorf("invalid config: %v", errs)
    }
    return nil
}
```

### Real Transports in Integration Tests

**Use real client with test server:**
```go
// Good
func TestAPI(t *testing.T) {
    srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        // Test double server
        w.WriteHeader(http.StatusOK)
        json.NewEncoder(w).Encode(&Response{Status: "ok"})
    }))
    defer srv.Close()

    // Real HTTP client
    client := &Client{BaseURL: srv.URL}
    resp, err := client.Get("/status")
    if err != nil {
        t.Fatal(err)
    }
    // Verify response
}

// Bad - hand-implemented client
type FakeClient struct {
    Response *Response
    Err      error
}

func (c *FakeClient) Get(path string) (*Response, error) {
    return c.Response, c.Err
}
```

### Error Handling in Tests

**Without subtests:**
```go
// Good - continue after error
for _, tc := range tests {
    got := Process(tc.input)
    if got != tc.want {
        t.Errorf("Process(%v) = %v, want %v", tc.input, got, tc.want)
        continue  // Continue to next test case
    }
}
```

**With subtests:**
```go
// Good - Fatal in subtest
for _, tc := range tests {
    t.Run(tc.name, func(t *testing.T) {
        got := Process(tc.input)
        if got != tc.want {
            t.Fatalf("Process(%v) = %v, want %v", tc.input, got, tc.want)
        }
    })
}
```

**Helpers with setup:**
```go
// Good - Fatal when setup fails
func setupTest(t *testing.T) *TestContext {
    t.Helper()

    db, err := setupDB()
    if err != nil {
        t.Fatalf("setup failed: %v", err)  // Can't continue
    }

    return &TestContext{DB: db}
}
```

**Never Fatal from goroutines:**
```go
// Bad
go func() {
    if err := process(); err != nil {
        t.Fatal(err)  // Will panic - t.Fatal not safe from goroutines
    }
}()

// Good
errCh := make(chan error)
go func() {
    errCh <- process()
}()

if err := <-errCh; err != nil {
    t.Errorf("process failed: %v", err)
}
```

### Error Semantics in Tests

**Rule:** Don't use error message text as a proxy for error *type*. String-matching turns a unit test into a change detector — the test breaks the next time someone reworks a wrapped error's wording, even though behavior didn't change.

**Prefer `wantErr bool` when only presence/absence matters:**
```go
// Good
tests := []struct {
    name    string
    input   string
    want    string
    wantErr bool
}{
    {name: "valid", input: "100", want: "100"},
    {name: "invalid", input: "abc", wantErr: true},
}
for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        got, err := Parse(tt.input)
        if tt.wantErr {
            require.Error(t, err)
            return
        }
        require.NoError(t, err)
        assert.Equal(t, tt.want, got)
    })
}
```

**Prefer `errors.Is`/`errors.As` (or testify's `assert.ErrorIs`/`assert.ErrorAs`) when the error's identity matters:**
```go
// Good
_, err := Parse("abc")
assert.ErrorIs(t, err, ErrInvalidFormat)

// Bad - brittle, breaks if the message is reworded
assert.EqualError(t, err, "parse: invalid format")
```

`assert.Contains`/`assert.ErrorContains` on message text is acceptable only for checking that documented, human-facing context (e.g. a parameter name) is present — not for distinguishing which error case fired.

### Test Structure

**Scope setup appropriately:**
```go
// Bad - package-level setup affects all tests
var testDB *sql.DB

func init() {
    testDB, _ = setupDB()  // Slows down ALL tests
}

// Good - test-specific setup
func TestUsers(t *testing.T) {
    db := setupDB(t)  // Only for this test
    // ...
}
```

**Use t.Cleanup:**
```go
// Good - automatic cleanup
func TestProcess(t *testing.T) {
    file := createTempFile(t)
    t.Cleanup(func() {
        os.Remove(file)
    })
    // Use file...
}
```

**TestMain only when necessary:**
```go
// Use only when ALL tests need expensive shared setup
func TestMain(m *testing.M) {
    // Setup
    db := setupExpensiveDB()
    defer db.Close()

    // Run tests
    code := m.Run()

    // Teardown
    os.Exit(code)
}
```

**Name subtests like identifiers, not prose:**
```go
// Bad - slash collides with -run/-test_filter, and it's a sentence
t.Run("check that AM/PM parsing doesn't get confused", func(t *testing.T) { ... })

// Good - short, identifier-like, filterable
t.Run("am_pm_confusion", func(t *testing.T) { ... })
```

If a case needs a longer explanation, put it in a `desc` table field and surface it via `t.Errorf`/`t.Log` on failure, rather than stretching the subtest name.

**Match message detail to what's needed to fix the failure:** setup/fixture failures need less detail than assertion failures — `t.Fatalf("setup: failed to open database: %v", err)` doesn't need to repeat the test's input. For assertion failures, use `%q` for strings (surfaces whitespace/invisible characters) and `%+v` for small structs (prints field names alongside values).

### Field Names in Struct Literals

**Table-driven tests:**
```go
// Good - field names included
tests := []struct {
    name     string
    input    string
    expected int
    wantErr  bool
}{
    {
        name:     "valid input",
        input:    "123",
        expected: 123,
        wantErr:  false,
    },
    {
        name:     "invalid input",
        input:    "abc",
        expected: 0,
        wantErr:  true,
    },
}
```

**Benefits:**
- Explicit intentions
- Easy to modify
- Clear when cases span many lines

### Test Doubles & Local Variables

**Prefix test doubles:**
```go
// Good - prefixed
func TestProcess(t *testing.T) {
    stubDB := &StubDatabase{}
    fakeCache := &FakeCache{}
    spyLogger := &SpyLogger{}

    processor := New(stubDB, fakeCache, spyLogger)
    // ...
}

// Bad - ambiguous
func TestProcess(t *testing.T) {
    db := &StubDatabase{}
    cache := &FakeCache{}
    logger := &SpyLogger{}

    processor := New(db, cache, logger)  // Which are real?
}
```

---

## String Operations

### Concatenation Methods

**Simple cases - `+` operator:**
```go
s := "Hello, " + name + "!"
```

**Complex formatting - `fmt.Sprintf`:**
```go
msg := fmt.Sprintf("User %s has %d points", name, points)
```

**Piecemeal building - `strings.Builder`:**
```go
// Good - O(n) complexity
var b strings.Builder
for _, word := range words {
    b.WriteString(word)
    b.WriteString(" ")
}
result := b.String()

// Bad - O(n²) complexity
var result string
for _, word := range words {
    result += word + " "  // Creates new string each iteration
}
```

**Multi-line constants - backticks:**
```go
const template = `
<html>
    <body>
        <h1>{{.Title}}</h1>
    </body>
</html>
`
```

**Direct to `io.Writer` - `fmt.Fprintf`:**
```go
// Good - no temporary string
fmt.Fprintf(w, "User: %s, Points: %d\n", name, points)

// Bad - unnecessary temporary
msg := fmt.Sprintf("User: %s, Points: %d\n", name, points)
fmt.Fprint(w, msg)
```

---

## Global State

### Avoiding Package-Level State

**Prefer instance values:**
```go
// Bad - global state
var defaultClient *http.Client

func Get(url string) (*Response, error) {
    return defaultClient.Get(url)
}

// Good - explicit dependency
type Client struct {
    http *http.Client
}

func (c *Client) Get(url string) (*Response, error) {
    return c.http.Get(url)
}

// Usage
client := &Client{http: &http.Client{}}
resp, err := client.Get(url)
```

### When Global State Is Problematic

**Multiple independent functions with shared state:**
```go
// Bad
var cache = make(map[string]string)

func Get(key string) string {
    return cache[key]
}

func Set(key, value string) {
    cache[key] = value
}

// Tests can't run in parallel due to shared cache
```

**Order-dependent tests:**
```go
// Bad
func TestGet(t *testing.T) {
    Set("key", "value")  // Depends on global state
    got := Get("key")
    // ...
}

func TestSet(t *testing.T) {
    Set("key", "new")  // Modifies global state
    // Can't run in parallel with TestGet
}
```

### Safe Uses of Global State

**Logically constant values:**
```go
// Good - registry doesn't change
package image

var formats = make(map[string]Format)

func RegisterFormat(name string, format Format) {
    formats[name] = format  // Only at init time
}
```

**Provide both instance and package-level APIs:**
```go
// Good pattern
package logger

// Instance API
type Logger struct {
    output io.Writer
}

func New(w io.Writer) *Logger {
    return &Logger{output: w}
}

func (l *Logger) Info(msg string) {
    fmt.Fprintln(l.output, msg)
}

// Package-level convenience (thin wrapper)
var std = New(os.Stderr)

func Info(msg string) {
    std.Info(msg)
}
```

**Reset capability for testing:**
```go
// Good - testable
package metrics

var counters = make(map[string]int)

func Increment(name string) {
    counters[name]++
}

func Reset() {
    counters = make(map[string]int)
}

// Test
func TestMetrics(t *testing.T) {
    defer Reset()  // Clean up after test
    Increment("requests")
    // ...
}
```

---

## Concurrency

### errgroup Package

**Coordinate related operations:**
```go
import "golang.org/x/sync/errgroup"

func ProcessFiles(files []string) error {
    g := new(errgroup.Group)

    for _, file := range files {
        file := file  // Capture for goroutine
        g.Go(func() error {
            return processFile(file)
        })
    }

    // Wait for all to complete; returns first error
    return g.Wait()
}
```

**With context:**
```go
func ProcessFiles(ctx context.Context, files []string) error {
    g, ctx := errgroup.WithContext(ctx)

    for _, file := range files {
        file := file
        g.Go(func() error {
            select {
            case <-ctx.Done():
                return ctx.Err()
            default:
                return processFile(ctx, file)
            }
        })
    }

    return g.Wait()
}
```

### Concurrency Safety Documentation

**Document safety:**
```go
// Cache is safe for concurrent use by multiple goroutines.
type Cache struct {
    mu    sync.RWMutex
    items map[string]Item
}

// Get retrieves an item from the cache.
// Get is safe for concurrent use.
func (c *Cache) Get(key string) (Item, bool) {
    c.mu.RLock()
    defer c.mu.RUnlock()
    item, ok := c.items[key]
    return item, ok
}
```

**Document unsafe operations:**
```go
// Buffer is not safe for concurrent use.
type Buffer struct {
    data []byte
}

// Write appends data to the buffer.
// Write is not safe for concurrent use.
func (b *Buffer) Write(p []byte) {
    b.data = append(b.data, p...)
}
```

### Channel Direction Patterns

**Producer-consumer:**
```go
// Producer sends to send-only channel
func produce(ch chan<- int) {
    for i := 0; i < 10; i++ {
        ch <- i
    }
    close(ch)
}

// Consumer receives from receive-only channel
func consume(ch <-chan int) {
    for val := range ch {
        fmt.Println(val)
    }
}

// Coordinator
func main() {
    ch := make(chan int)
    go produce(ch)
    consume(ch)
}
```

---

## Summary Checklist

### Naming
- [ ] Package names are lowercase, no underscores
- [ ] Avoid generic package names (util, common, helper)
- [ ] Function names avoid repetition with package/receiver
- [ ] Variable names proportional to scope
- [ ] Test doubles named by behavior

### Error Handling
- [ ] Errors are structured for programmatic inspection
- [ ] Use `%w` for wrapping when inspection needed
- [ ] Add meaningful context, avoid redundancy
- [ ] Avoid duplicate logging (let callers decide)
- [ ] Document significant errors returned

### Documentation
- [ ] All exported names have doc comments
- [ ] Comments avoid restating obvious
- [ ] Concurrency safety documented when non-obvious
- [ ] Cleanup requirements clearly explained

### Functions & Variables
- [ ] Long argument lists converted to option structs
- [ ] Context always first parameter
- [ ] Channel directions specified
- [ ] Preallocate slices/maps only when benchmarked

### Testing
- [ ] Test helpers call `t.Helper()`
- [ ] Avoid assertion libraries
- [ ] Use `t.Error` for mismatches, `t.Fatal` for setup failures
- [ ] Scope setup to specific tests
- [ ] Never call `t.Fatal` from goroutines

### Global State
- [ ] Avoid package-level state when possible
- [ ] Provide instance APIs
- [ ] Document and provide reset for testing

### Strings & Concurrency
- [ ] Use `strings.Builder` for piecemeal construction
- [ ] Use `errgroup` for coordinated operations
- [ ] Document concurrency safety explicitly
