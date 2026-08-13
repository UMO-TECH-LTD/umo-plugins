---
name: go-quality-gates
description: The gates a Go service change must pass before it is called done — gofmt before staging, golangci-lint, build and test, and the GOWORK=off variants that reproduce CI when a local workspace is active. Use before committing Go changes, before opening or updating an MR, or whenever about to claim a Go change builds, passes, or is fixed.
---

# Go quality gates

No completion claim without fresh output. Run the gates, read them, then speak.

## Order

From the service directory (`services/<service>/` in a monorepo, repo root in a
single-module repo):

```bash
go fmt ./...                       # or gofmt -l -w . — before staging, always
golangci-lint run ./...            # or `make lint` if the service defines it
go build ./...
go test ./...
```

`go fmt` comes **before** `git add`, not after — see
`references/gofmt-before-commit.md` for what the CI formatting job rejects.

## When a `go.work` is active

A workspace silently changes what you are testing: the platform modules resolve
from a local checkout instead of the released tag. Repeat the last two gates the
way CI will run them before you open or un-draft an MR:

```bash
GOWORK=off go build ./... && GOWORK=off go test ./...
```

Green with the workspace and red without it means `go.mod` does not stand on its
own — the usual causes are a stripped `go.sum` entry or a version that was never
released. See the `go-local-module-dev` skill.

## Rules

- Run each gate fresh for the change in hand. "It passed earlier" is not evidence.
- Read the whole output and check the exit code — a non-zero exit with a
  plausible-looking tail is still a failure.
- Fix what the gate reports; do not disable a linter to make it green. If a
  `//nolint` is genuinely warranted, it carries a reason on the same line.
- One line changed is still a change: the gates apply.
