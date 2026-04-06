---
name: tdd-first
description: Write or update failing tests before implementation. Use when adding new behavior or changing existing behavior.
---

# TDD First

Load when implementing new behavior, fixing a bug, or changing an existing contract.
The core discipline is simple: make the requirement executable before writing code.

## Required sequence

```text
1. Read the requirement
2. Write or update a test that expresses the requirement
3. Run the test and confirm it fails for the right reason
4. Implement the smallest change that can pass
5. Run the test and confirm it passes
6. Run the broader project checks to catch regressions
```

## What to test

- happy path behavior
- one error or invalid-input path
- one edge condition or boundary case

## What to assert

Prefer observable behavior:

- returned values
- produced output
- persisted state
- emitted events
- explicit errors

Avoid coupling tests to internal implementation details unless those calls are the contract.

## When tests feel hard

That usually means the code is too entangled. Extract pure functions or narrower units
so the behavior can be tested directly.
