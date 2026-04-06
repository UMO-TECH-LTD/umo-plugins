---
name: quality-loop
description: Lint and typecheck after every file change. Use when implementing, fixing lint errors, or before wrapping up a task.
---

# Quality Loop

Load when implementing, refactoring, or cleaning up errors. The goal is to keep the
working tree continuously healthy instead of batching breakage.

## The loop

```text
1. Edit code
2. Run the formatter or linter with autofix when available
3. Run typecheck
4. Read every reported error
5. Fix all errors in the same pass
6. Re-run checks until clean
7. Then move to the next file or task
```

## Default commands

Use the repo's existing tooling. In Bun or TypeScript repos, the default loop is:

```bash
bunx @biomejs/biome check --write .
tsc --noEmit
bun test
```

If the repository uses another stack, use the equivalent configured commands.

## Rules

- Never move on while the current change set still has lint or type errors.
- Do not add inline suppressions unless the reason is explicit and justified.
- Treat typecheck failures as first-class errors, not cleanup work for later.
- Prefer the smallest correct fix over speculative refactors.

## Common fixes

| Problem | Typical fix |
|---------|-------------|
| unused import | remove it |
| implicit or explicit `any` | replace with a real type or `unknown` |
| mutable variable not reassigned | change `let` to `const` |
| overly complex function | extract named helper functions |
| console logging in app code | use the project's logger abstraction |
