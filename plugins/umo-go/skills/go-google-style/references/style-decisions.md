# Go Style Decisions - Detailed Rules

This document contains specific style decisions from the Google Go Style Guide. These are normative rules for consistent Go code.

## Table of Contents

- [Naming](#naming)
- [Error Handling](#error-handling)
- [Formatting & Literals](#formatting--literals)
- [Function & Control Flow](#function--control-flow)
- [Imports & Packages](#imports--packages)
- [Language Features](#language-features)
- [Commentary](#commentary)
- [Common Libraries](#common-libraries)
- [Testing](#testing)

---

## Naming

### Underscores

**Rule:** Avoid underscores in Go identifiers.

**Exceptions:**
- Generated code packages (e.g., `foo_proto`)
- Test files (`*_test.go`)
- Test-only packages (`package_test` suffix for black box tests)
- Low-level OS/cgo libraries matching C naming

### Package Names

**Rules:**
- Use lowercase letters and numbers only
- Keep multi-word names unbroken: `tabwriter` not `tabWriter` or `tab_writer`
- Avoid generic names: `util`, `common`, `helper`, `api`, `types`
- Keep names short and concise

**Examples:**
```go
// Good
package tabwriter
package oauth2
package k8s

// Bad
package tab_writer
package oAuth2
package utils
```

**Import renaming:**
- Generated packages with underscores must be renamed at import
- Use descriptive package names that won't tempt renaming

### Receiver Names

**Rules:**
- Keep short: one or two letters
- Abbreviate the type itself
- Apply consistently across all methods for the type

**Examples:**
```go
func (t *Tray) Method() { }
func (ri *ResearchInfo) Method() { }
func (w *ReportWriter) Method() { }

// Bad - inconsistent
func (t *Tray) Method1() { }
func (tray *Tray) Method2() { }  // Inconsistent with Method1
```

### Constants

**Rules:**
- Use MixedCaps (not SCREAMING_SNAKE_CASE)
- Name by role, not value
- Exported constants start uppercase
- Unexported constants start lowercase

**Examples:**
```go
// Good
const MaxPacketSize = 512
const ExecuteBit = 1

// Bad
const MAX_PACKET_SIZE = 512
const kMaxBufferSize = 1024
```

### Initialisms

**Rule:** Maintain consistent case within each initialism.

**Examples:**
```go
// Good
var URLParser
var url string
var XMLAPI

// Bad
var UrlParser  // Mixed case within initialism
var Url string
```

**Special cases:** Match standard prose: `iOS`, `gRPC`, `DDoS`

### Getters

**Rule:** Do not use "Get" prefix unless the concept inherently uses "get".

**Examples:**
```go
// Good
func (c *Client) Counts() *Counts
func (db *DB) ComputeStats() *Stats

// Bad
func (c *Client) GetCounts() *Counts

// Acceptable when "get" is part of the concept
func (r *Request) GetHeader(name string) string
```

**Alternatives for time-consuming operations:**
- `Compute` for calculations
- `Fetch` for remote operations

### Variable Names

**Principle:** Length proportional to scope size, inversely proportional to usage frequency.

**Small scope (1-7 lines):** Shorter names acceptable
```go
for i, v := range items {
    // i and v are fine here
}
```

**Medium scope (8-15 lines):** More descriptive
```go
userCount := len(users)
maxRetries := 5
```

**Large scope (15+ lines):** Full clarity required
```go
authenticatedUserCount := countAuthenticatedUsers()
maximumAllowedRetries := config.GetMaxRetries()
```

**Avoid redundancy:**
```go
// Bad - omit types from names
var numUsers int      // Use userCount
var usersInt int      // Use count or userCount

// Bad - omit context-clear information
func (u *UserCounter) UserCount() int {
    var userCount int  // Just use "count" since context is clear
}

// Good
func (u *UserCounter) Count() int {
    var count int
}
```

**Single-letter variables acceptable for:**
- Loop indices: `i`, `j`, `k`
- Coordinates: `x`, `y`, `z`
- Method receivers: `t`, `c`
- Common interfaces: `r` for `io.Reader`, `w` for `io.Writer`

### Repetition - Avoid Redundancy

**Package vs. exported symbol:**
```go
// Bad
widget.NewWidget()
widget.WidgetController

// Good
widget.New()
widget.Controller
```

**Variable vs. type:**
```go
// Bad
var janeDoeWidget widget.Widget

// Good - compiler knows the type
var janeDoe widget.Widget
```

**Context vs. local names:**
```go
// Bad
func (w *Widget) WidgetName() string {
    var widgetName string
}

// Good
func (w *Widget) Name() string {
    var name string
}
```

---

## Error Handling

### Returning Errors

**Rules:**
- Errors are always the last return parameter
- Return `nil` for successful operations
- Return concrete `error` type (not pointer types like `*os.PathError`)

**Examples:**
```go
// Good
func Open(name string) (*File, error)
func Process(data []byte) (Result, error)

// Bad
func Open(name string) (error, *File)
func Process(data []byte) (*ProcessError, Result)
```

**Context cancellation:**
Functions taking `context.Context` should return errors to signal cancellation.

### Error Strings

**Rules:**
- No capitalization unless proper nouns, acronyms, or exported names
- No ending punctuation
- User-facing logged messages should be capitalized

**Examples:**
```go
// Good
fmt.Errorf("failed to connect to database")
fmt.Errorf("invalid URL: %s", url)
fmt.Errorf("failed to process UserID %d", id)

// Bad
fmt.Errorf("Failed to connect to database")
fmt.Errorf("invalid url: %s", url)
fmt.Errorf("failed to connect to database.")
```

### Handling Errors

**Rule:** Make deliberate choices about error handling.

**Three options:**
1. Handle immediately
2. Return to caller
3. Call `log.Fatal`/`panic` (exceptional cases only)

**Never discard with `_` without explanation:**
```go
// Bad
result, _ := SomeFunction()

// Good - if you must ignore
result, err := SomeFunction()
// Ignoring error because [reason]: explicitly impossible/handled elsewhere
_ = err
```

### In-band Errors

**Rule:** Avoid returning -1, null, or empty string as error signals.

**Examples:**
```go
// Bad
func Find(key string) int {
    // returns -1 on error
}

// Good
func Find(key string) (int, bool) {
    // returns index and found boolean
}

// Also good
func Find(key string) (int, error) {
    // returns index and error
}
```

### Error Flow

**Rule:** Check errors before proceeding with normal code.

**Pattern:**
```go
// Good - error handling first
result, err := DoSomething()
if err != nil {
    return err
}
// Normal code continues here
processResult(result)

// Bad - normal code in else
result, err := DoSomething()
if err == nil {
    processResult(result)
} else {
    return err
}
```

**Benefits:** Improves readability, follows "line of sight" principle.

---

## Formatting & Literals

### Literal Field Names

**Rules:**
- **Required** for external package types (avoid coupling)
- **Optional but recommended** for package-local types with many fields

**Examples:**
```go
// Required - external package
return &pb.UserRequest{
    Name:  name,
    Email: email,
}

// Recommended - clarity with many fields
return &User{
    Name:     name,
    Email:    email,
    IsActive: true,
    Role:     "admin",
}
```

### Matching Braces

**Rule:** Multi-line literals must have closing brace at same indentation as opening.

**Examples:**
```go
// Good
items := []Item{
    {Name: "foo"},
    {Name: "bar"},
}

// Bad
items := []Item{
    {Name: "foo"},
    {Name: "bar"},
    }  // Wrong indentation
```

### Cuddled Braces

**Rules:** Permitted only when:
1. Indentation matches
2. Inner values are literals or proto builders (not variables)

**Examples:**
```go
// Good - cuddled braces
return []*Item{{
    Name: "foo",
}, {
    Name: "bar",
}}

// Also good - not cuddled
return []*Item{
    {Name: "foo"},
    {Name: "bar"},
}

// Bad - mixed variables
return []*Item{{
    Name: name,  // Variable, not literal
}}
```

### Repeated Type Names

**Rule:** Omit repeated type names in slice/map literals when clarity maintained.

**Examples:**
```go
// Good - types omitted
items := []*Item{
    {Name: "foo"},
    {Name: "bar"},
}

// Also acceptable - types explicit
items := []*Item{
    &Item{Name: "foo"},
    &Item{Name: "bar"},
}

// Bad - redundant with no benefit
items := []*Item{
    &Item{Name: "foo"},
    &Item{Name: "bar"},
}
```

### Zero-value Fields

**Rule:** Omit zero-value fields when clarity isn't lost.

**Exception:** Table-driven tests often benefit from explicit field names.

**Examples:**
```go
// Good - zero values omitted
user := &User{
    Name: "Alice",
    // Age: 0,  // Omitted
    // IsActive: false,  // Omitted
}

// Good in tests - explicit for clarity
tests := []struct{
    name     string
    input    int
    expected int
}{
    {name: "zero", input: 0, expected: 0},
    {name: "positive", input: 5, expected: 10},
}
```

### Nil Slices

**Rules:**
- Prefer `var t []string` over `t := []string{}`
- No functional difference from `==` operator perspective
- APIs should not force distinction between nil and empty slices
- Use `len(s) == 0` for emptiness checks, not `s == nil`

**Examples:**
```go
// Good
var items []Item
if len(items) == 0 {
    // Handle empty
}

// Bad
items := []Item{}
if items == nil {  // Won't work as expected
    // Handle empty
}
```

---

## Function & Control Flow

### Function Formatting

**Rules:**
- Keep signature on single line when possible
- Factor out local variables to shorten argument lists
- Don't add inline comments to individual arguments
- Breaking permitted when aiding understanding based on semantic groupings

**Examples:**
```go
// Good
func Process(ctx context.Context, user *User, options *Options) error

// Good - grouped by semantics
func CreateReport(
    ctx context.Context,
    userID int, userName string,
    startDate, endDate time.Time,
) (*Report, error)

// Bad - inline comments
func Process(
    ctx context.Context,  // request context
    user *User,          // user to process
) error
```

### Conditionals & Loops

**Rules:**
- `if` statements should not break across lines
- Extract boolean operands to avoid indentation confusion
- Keep `switch` clauses on single lines
- Place variable on left of equality: `result == "foo"` not Yoda style

**Examples:**
```go
// Good
if result == "success" && count > 0 {
    // Handle
}

// Good - complex condition extracted
isValid := result == "success" &&
           count > 0 &&
           user.IsActive
if isValid {
    // Handle
}

// Bad - Yoda style
if "success" == result {
    // Handle
}
```

### Switch & Break

**Rules:**
- Don't use redundant `break` at end of `switch` clauses (Go auto-breaks)
- Use comment to clarify empty clause purpose
- Note: `break` in switch within `for` loop doesn't exit the loop

**Examples:**
```go
// Good
switch status {
case "success":
    process()
case "pending":
    // Intentionally do nothing
case "error":
    handleError()
}

// Bad
switch status {
case "success":
    process()
    break  // Redundant
}

// Gotcha - break in nested switch
for {
    switch status {
    case "done":
        break  // Only breaks switch, not loop!
    }
}

// Correct - use label
Loop:
for {
    switch status {
    case "done":
        break Loop  // Breaks loop
    }
}
```

---

## Imports & Packages

### Import Renaming

**Rules:**
- Local names must follow package naming rules (lowercase, no underscores)
- Rename to avoid collisions; prefer renaming the most local import
- Generated proto packages: rename to remove underscores, add `pb` suffix
- Rename with `pkg` suffix when shadowing common variable names

**Examples:**
```go
// Good - proto package
import (
    userpb "gitlab.company.com/api/user_service/proto"
)

// Good - avoid collision
import (
    "crypto/rand"

    mathrand "math/rand"
)

// Good - avoid shadowing
import (
    urlpkg "net/url"
)

func Process() {
    url := urlpkg.Parse(...)  // url variable doesn't shadow package
}
```

### Import Grouping

**Order:**
1. Standard library packages
2. Project and vendored packages
3. Protocol Buffer imports
4. Side-effect imports

**Examples:**
```go
import (
    // Standard library
    "context"
    "fmt"
    "time"

    // Project packages
    "gitlab.company.com/project/auth"
    "gitlab.company.com/project/users"

    // Protocol buffers
    userpb "gitlab.company.com/api/user_proto"

    // Side effects
    _ "gitlab.company.com/project/metrics"
)
```

### Blank Imports

**Rules:**
- Only in main packages or tests requiring side effects
- Avoid in library packages
- Exceptions: bypass nogo checks or with `//go:embed` directive

**Examples:**
```go
// Good - main package
import (
    _ "gitlab.company.com/project/metrics"  // Initialize metrics
)

// Good - embed
import (
    _ "embed"
)

//go:embed template.html
var template string
```

### Dot Imports

**Rule:** Do not use. Always use qualified names.

**Examples:**
```go
// Bad
import . "fmt"

func main() {
    Println("hello")  // Unclear where Println comes from
}

// Good
import "fmt"

func main() {
    fmt.Println("hello")  // Clear
}
```

---

## Language Features

### Copying

**Rules:**
- Avoid copying structs with `sync.Mutex` or similar non-copyable types
- `bytes.Buffer` contains aliasing risks
- Don't copy if methods are on `*T`
- API should return pointers when struct contains non-copyable fields

**Examples:**
```go
// Bad
type Counter struct {
    mu    sync.Mutex
    count int
}

func (c Counter) Inc() {  // Bad - value receiver copies mutex
    c.mu.Lock()
    defer c.mu.Unlock()
    c.count++
}

// Good
func (c *Counter) Inc() {  // Pointer receiver
    c.mu.Lock()
    defer c.mu.Unlock()
    c.count++
}
```

### Panic

**Rules:**
- Don't use for normal error handling
- For `main` and init code, prefer `log.Exit` or `log.Fatal`
- Acceptable for "impossible" bugs caught in review/testing
- "Must" functions acceptable for package initialization

**Examples:**
```go
// Bad - normal error should return error
func LoadConfig(path string) Config {
    data, err := os.ReadFile(path)
    if err != nil {
        panic(err)  // Bad
    }
    // ...
}

// Good
func LoadConfig(path string) (Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return Config{}, err
    }
    // ...
}

// Acceptable - compile-time regex
var emailRegex = regexp.MustCompile(`^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$`)
```

### Must Functions

**Rules:**
- Named `MustXYZ` for setup helpers that panic on failure
- Call only during early program startup, not on user input
- Should only be used when impossible to handle errors normally

**Examples:**
```go
// Good - initialization only
var emailRegex = regexp.MustCompile(`^[a-z]+@[a-z]+\.[a-z]{2,}$`)

// Bad - user input
func ProcessEmail(email string) {
    // Don't use MustCompile here with user input
    regex := regexp.MustCompile(email)  // Bad
}
```

### Goroutine Lifetimes

**Rules:**
- Make clear when/whether goroutines exit
- Use `context.Context` for cancellation
- Use `sync.WaitGroup` for synchronization
- Document goroutine exit conditions
- Avoid goroutine leaks

**Examples:**
```go
// Good - clear lifecycle
func (s *Server) Run(ctx context.Context) error {
    var wg sync.WaitGroup

    wg.Add(1)
    go func() {
        defer wg.Done()
        <-ctx.Done()
        // Cleanup
    }()

    // ...

    wg.Wait()
    return nil
}

// Bad - unclear lifecycle
func (s *Server) Run() {
    go func() {
        // When does this exit? Leak potential!
        for {
            s.process()
        }
    }()
}
```

### Interfaces

**Rules:**
- Define in consuming package, not implementing package
- Return concrete types, not interfaces
- Don't export test double implementations
- Design for testing with public API of real implementations
- Don't define before use; wait for realistic usage example

**Examples:**
```go
// Good - consumer defines interface
package reporting

type DataStore interface {
    GetUser(id int) (*User, error)
}

func GenerateReport(store DataStore) *Report {
    // ...
}

// Bad - implementation package exports interface
package database

type DataStore interface {  // Bad - let consumers define their needs
    GetUser(id int) (*User, error)
    GetOrder(id int) (*Order, error)
    // Many methods the consumer might not need
}
```

### Generics

**Rules:**
- Acceptable where fulfilling business requirements
- Avoid premature use; conventional approaches often sufficient
- Document exported APIs with examples
- Don't use just because algorithm doesn't care about type
- Avoid creating DSLs or assertion frameworks

**Examples:**
```go
// Good - clear benefit
func Keys[K comparable, V any](m map[K]V) []K {
    keys := make([]K, 0, len(m))
    for k := range m {
        keys = append(keys, k)
    }
    return keys
}

// Bad - unnecessary
func Add[T int | int64 | float64](a, b T) T {
    return a + b  // Just use multiple functions or interface
}
```

### Pass Values

**Rules:**
- Don't pass pointers to save bytes for small fixed-size types
- Exception: protocol buffer messages (handle by pointer)
- Exception: large structs or those with pointer fields

**Examples:**
```go
// Good - small struct, pass by value
type Point struct {
    X, Y int
}

func Distance(p1, p2 Point) float64 {
    // ...
}

// Good - large struct or with pointers, pass by pointer
type User struct {
    ID       int
    Name     string
    Settings *Settings
    // Many fields...
}

func ProcessUser(u *User) error {
    // ...
}
```

### Receiver Types

**Value receiver for:**
- Slices (no reslice/realloc)
- Built-in types
- Small plain data
- Maps, functions, channels

**Pointer receiver for:**
- Mutation needed
- Contains non-copyable fields (`sync.Mutex`)
- Large structs
- Concurrent modifications
- Contains pointers to mutables

**Rule:** Prefer consistency - all methods on type use same receiver kind.

**Examples:**
```go
// Good - consistent pointer receivers
type Counter struct {
    count int
}

func (c *Counter) Inc() {
    c.count++
}

func (c *Counter) Value() int {  // Pointer even though read-only
    return c.count              // Consistency with Inc
}

// Bad - mixed receivers
func (c *Counter) Inc() {
    c.count++
}

func (c Counter) Value() int {  // Value receiver - inconsistent
    return c.count
}
```

### Type Aliases

**Rule:** Use type definitions (`type T1 T2`) for new types. Use aliases (`type T1 = T2`) rarely—primarily for migration.

**Examples:**
```go
// Good - new type
type UserID int

// Rare - alias for migration
type OldUserID = UserID  // Temporary during migration
```

### Format String Verb %q

**Rule:** Prefer `%q` for printing strings in quotes over manual quotation marks.

**Examples:**
```go
// Good
fmt.Printf("name: %q\n", name)  // name: "Alice" or name: ""

// Bad
fmt.Printf("name: \"%s\"\n", name)  // Harder to read, empty string unclear
```

### Type any

**Rule:** Prefer `any` over `interface{}` in new code (Go 1.18+).

**Examples:**
```go
// Good - modern
func Print(v any) {
    fmt.Println(v)
}

// Acceptable - legacy code
func Print(v interface{}) {
    fmt.Println(v)
}
```

---

## Commentary

### Line Length

**Rules:**
- Aim for 80 columns on narrow terminals
- No hard cutoff
- Wrap at punctuation when possible
- Avoid jagged wrapping on small screens
- Include long URLs if they help

### Doc Comments

**Rules:**
- All exported names require doc comments
- Unexported types/functions with non-obvious behavior should have them
- Full sentences beginning with name (article optional)
- Appear in Godoc, surfaced by IDEs

**Examples:**
```go
// Good
// Process processes the user request and returns a response.
func Process(req *Request) (*Response, error)

// Good - without article
// UserCache stores user data for quick retrieval.
type UserCache struct

// Bad
// processes the request
func Process(req *Request) (*Response, error)

// Bad - doesn't start with name
// This function processes the user request.
func Process(req *Request) (*Response, error)
```

### Comment Sentences

**Rules:**
- Complete sentences: capitalized and punctuated
- Fragments: no requirements
- Doc comments always complete sentences
- End-of-line comments: can be phrases

**Examples:**
```go
// Complete sentence
// Process handles the incoming request.
func Process()

// Fragment OK in inline comment
count := 0  // number of items processed
```

### Examples

**Rules:**
- Provide runnable examples in test files (`*_test.go`)
- Examples appear in Godoc
- If unfeasible, provide code in comments following formatting conventions

**Examples:**
```go
// In *_test.go file
func ExampleNew() {
    client := pkg.New("config.json")
    // Output shows in Godoc
}
```

### Named Result Parameters

**Rules:**
- Omit if types are clear from function name
- Include if returning 2+ parameters of same type
- Include if names suggest required actions by caller
- Don't use to avoid variable declarations
- Acceptable if value changed in deferred closure

**Examples:**
```go
// Good - same types need names
func Split(s string, sep string) (before, after string, found bool)

// Good - clear without names
func Parse(data []byte) (*User, error)

// Good - deferred modification
func Process() (err error) {
    defer func() {
        if err != nil {
            err = fmt.Errorf("process failed: %w", err)
        }
    }()
    // ...
}

// Bad - unnecessary
func Count() (count int) {
    count = 0
    return count
}
```

### Package Comments

**Rules:**
- Appear immediately before package clause (no blank line)
- Single package comment per package
- For `main` packages: use binary name from BUILD file
- Can be multiline; use `doc.go` if extraordinarily long

**Examples:**
```go
// Package users provides user management functionality.
//
// It handles user authentication, authorization, and profile management.
package users
```

---

## Common Libraries

### Flags

**Rules:**
- Flag names in snake_case
- Variables holding flag values in camelCase
- Define only in `package main`
- Libraries should not export flags as side effect
- Global flag variables in their own `var` group after imports

**Examples:**
```go
var (
    userName   = flag.String("user_name", "", "Name of the user")
    maxRetries = flag.Int("max_retries", 3, "Maximum retry attempts")
)
```

### Logging

**Uses:** Internal `log` package variant or `glog`.

**Rules:**
- `log.Info(v)` equivalent to `log.Infof("%v", v)` - prefer non-formatting when not needed
- `log.Fatal` aborts with stacktrace
- `log.Exit` without stacktrace
- No `log.Panic`

### Contexts

**Rules:**
- Always first parameter in functions
- Never add context as struct member
- Don't create custom context types; always use `context.Context`
- Immutable; safe to pass same context to multiple calls
- Test helpers should accept context parameter

**Exceptions:**
- HTTP handlers (from `req.Context()`)
- Streaming RPC (from `Context()` method)
- Entrypoint functions (use `context.Background()` or `tb.Context()`)

**Examples:**
```go
// Good
func Process(ctx context.Context, data []byte) error

// Bad - context in struct
type Processor struct {
    ctx context.Context  // Bad
}

// Bad - context not first
func Process(data []byte, ctx context.Context) error
```

### crypto/rand

**Rule:** Never use `math/rand` for keys/security. Use `crypto/rand.Reader` and format as hex/base64.

**Examples:**
```go
// Good
token := make([]byte, 32)
_, err := io.ReadFull(rand.Reader, token)
if err != nil {
    return err
}
key := hex.EncodeToString(token)

// Bad - not cryptographically secure
token := rand.Int63()  // math/rand - insecure
```

---

## Testing

### Useful Test Failures

**Messages should include:**
- Cause of failure
- Inputs resulting in error
- Actual result
- Expected result

**Examples:**
```go
// Good
t.Errorf("Parse(%q) = %v, want %v", input, got, want)

// Bad
t.Errorf("unexpected result")
```

### Assertion Libraries — devkit/saas convention

**Google's rule:** Do not build or reach for assertion libraries; prefer plain `if` checks plus `cmp.Equal`/`cmp.Diff`. The rationale is that hand-rolled assertion helpers tend to swallow context and fragment the developer experience.

**This codebase's convention overrides that default:** `stretchr/testify` (`assert`/`require`) is already the standard across devkit and saas — the vast majority of existing `_test.go` files use it, and its output already satisfies Google's "useful test failures" bar (identifies the values compared, shows got/want equivalents, keeps the diff readable). **Use testify for new tests** instead of introducing raw `if`/`t.Errorf` chains or switching to `cmp` — consistency with the existing suite wins here. Reach for `cmp.Diff(want, got, protocmp.Transform())` only where testify cannot express the comparison well, e.g. protobuf messages or values needing `cmpopts` semantics.

**`require` vs `assert` — the load-bearing distinction:**
- `require.*` — stops the test immediately (`t.FailNow`). Use for preconditions and setup: a failed `require.NoError(t, err)` before using the resulting value, since continuing would panic or produce meaningless follow-on failures.
- `assert.*` — records the failure and continues (`t.Fail`). Use for the actual value checks you want reported even if other checks in the same test also fail.

```go
// Good
got, err := money.Parse(tt.input)
require.NoError(t, err)          // can't inspect got if this failed
assert.Equal(t, tt.want, got.String())

// Bad — assert.NoError lets a nil got flow into the next line and panic
got, err := money.Parse(tt.input)
assert.NoError(t, err)
assert.Equal(t, tt.want, got.String())
```

### Test Function Requirements

**Format:** `YourFunc(%v) = %v, want %v`

**Rules:**
- Identify the function being tested in failure message
- Include function inputs if short
- Place got before want
- Use "got" and "want" terminology

**Examples:**
```go
got := Sum(1, 2)
want := 3
if got != want {
    t.Errorf("Sum(1, 2) = %d, want %d", got, want)
}
```

### Comparisons

**Scalar values:**
```go
if got != want {
    t.Errorf("got %v, want %v", got, want)
}
```

**Complex structures:**
```go
if diff := cmp.Diff(want, got); diff != "" {
    t.Errorf("Result mismatch (-want +got):\n%s", diff)
}
```

**Proto messages:**
```go
if diff := cmp.Diff(want, got, protocmp.Transform()); diff != "" {
    t.Errorf("Proto mismatch (-want +got):\n%s", diff)
}
```

**Testify equivalents:**
```go
assert.Equal(t, want, got)                                   // scalars and comparable structs
assert.Empty(t, cmp.Diff(want, got, protocmp.Transform()))    // proto messages via cmp
```

### Full Structure Comparisons

**Rule:** Build the complete expected value and compare it in one shot instead of hand-rolling a field-by-field chain of checks with bespoke messages.

```go
// Bad — hand-rolled, easy to miss a field, inconsistent messages
if got.Name != want.Name {
    t.Errorf("Name = %q, want %q", got.Name, want.Name)
}
if got.Comments != want.Comments {
    t.Errorf("Comments = %d, want %d", got.Comments, want.Comments)
}

// Good — one comparison, testify reports every differing field
want := BlogPost{Type: "blogPost", Comments: 2, Body: "Hello, world!"}
assert.Equal(t, want, got)
```

Exception: when the struct has irrelevant fields (timestamps, generated IDs) that would obscure intent, it's fine to compare only the relevant fields explicitly, or zero out the irrelevant fields on `got` before comparing.

### Test Execution

**Rules:**
- Keep tests running after failures to report all issues
- Use `t.Error` for mismatches
- Use `t.Fatal` for unexpected conditions
- `t.Fatal` appropriate when subsequent tests would be meaningless

**Examples:**
```go
// Good
data, err := ReadFile("test.txt")
if err != nil {
    t.Fatal(err)  // Can't continue without data
}

if len(data) == 0 {
    t.Error("expected non-empty data")  // Continue with other checks
}
```

**Table-driven tests:**
```go
for _, tc := range tests {
    t.Run(tc.name, func(t *testing.T) {
        got := Process(tc.input)
        if got != tc.want {
            t.Fatalf("Process(%v) = %v, want %v", tc.input, got, tc.want)
        }
    })
}
```

### Test Error Semantics

**Rule:** Never string-match on `err.Error()` to distinguish error kinds — error text is for humans and can change without warning, turning the test into a change detector. Prefer `errors.Is`/`errors.As`, or reduce to presence/absence with a `wantErr bool` table field.

```go
// Bad — brittle: breaks the moment the error message is reworded
assert.ErrorContains(t, err, "invalid number")

// Good — presence/absence is all that matters
tests := []struct {
    name    string
    input   string
    wantErr bool
}{
    {name: "valid", input: "100"},
    {name: "invalid string", input: "not-a-number", wantErr: true},
}
// ...
if tt.wantErr {
    require.Error(t, err)
    return
}
require.NoError(t, err)

// Good — semantic error identity when the kind matters
_, err := money.Parse(tt.input)
assert.ErrorIs(t, err, money.ErrInvalidFormat)
```

It is fine to use `assert.Contains`/`assert.ErrorContains` to check that an error message includes a specific parameter name or piece of context the package under test is documented to always include — the rule is about not using message text as a proxy for error *type*.

### Subtest Naming

**Rule:** Keep `t.Run` names identifier-like and short — they double as `-run`/`-test_filter` arguments.

- Avoid `/` in subtest names — it collides with the `TestName/SubtestName` filter syntax and makes some cases unfilterable.
- Avoid long prose descriptions; if a case needs a longer explanation, put it in a `desc` table field and print it as part of the failure message via `t.Errorf`/`t.Log`, not in the subtest name itself.

```go
// Bad
t.Run("check that AM/PM parsing doesn't get confused", ...)

// Good
t.Run("am_pm_confusion", ...)
```

### Level of Detail

**Rule:** Match message detail to what a maintainer actually needs to fix the failure.

- Assertion failures on function output: identify the function and inputs (see Test Function Requirements above).
- Setup/fixture failures: a short message is enough — `t.Fatalf("setup: failed to open database: %v", err)` doesn't need the full test input.
- Use `%q` for strings so whitespace/invisible characters are visible, and `%+v` for small structs so field names are printed alongside values.

### Stable Results

**Rule:** Avoid comparing formatted/serialized output that may change.

**Examples:**
```go
// Bad - JSON formatting may change
gotJSON := toJSON(result)
wantJSON := `{"name":"Alice","age":30}`
if gotJSON != wantJSON {
    t.Error("mismatch")
}

// Good - parse and compare semantically
var got, want User
json.Unmarshal([]byte(gotJSON), &got)
json.Unmarshal([]byte(wantJSON), &want)
if diff := cmp.Diff(want, got); diff != "" {
    t.Errorf("mismatch: %s", diff)
}
```

---

## Quick Reference Table

| Category | Rule | Example |
|----------|------|---------|
| **Package Names** | lowercase, no underscores | `tabwriter`, `oauth2` |
| **Receiver Names** | 1-2 letters | `t *Tray`, `ri *ResearchInfo` |
| **Constants** | MixedCaps, by role | `MaxPacketSize` not `MAX_PACKET_SIZE` |
| **Initialisms** | Consistent case | `URL` or `url`, never `Url` |
| **Getters** | No "Get" prefix | `Counts()` not `GetCounts()` |
| **Errors** | Last parameter | `func F() error` |
| **Context** | First parameter | `func F(ctx context.Context, ...)` |
| **Must Functions** | `MustXYZ` convention | `regexp.MustCompile()` |
| **Nil Slices** | `var s []T` | Not `s := []T{}` |
| **Panic** | Avoid, use errors | Only for impossible bugs |
| **Interfaces** | Consumer defines | Not implementation package |
| **Line Length** | Aim for 80 columns | No hard limit |
| **Flags** | snake_case | `max_retries` |
| **Test Assertions** | testify (`assert`/`require`) | `require`=stop, `assert`=continue |
| **Test Errors** | `errors.Is`/`wantErr bool` | Never string-match `err.Error()` |
