---
name: commit
description: Stage and commit changes as one logical unit with a conventional commit message.
---

Stage and commit changes in the current repository. Execute the git commands directly.

## Rules

- One logical unit per commit.
- Do not mix unrelated work in one commit.
- Use conventional commit format.
- Do not push unless explicitly asked.

## Steps

1. Run `git status` and `git diff` to inspect the current change set.
2. Group files into one logical unit.
3. Stage only those files.
4. Write a conventional commit message.
5. Run `git commit`.

## Conventional commit format

```text
<type>(<scope>): <subject>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `build`, `ci`

Examples:

- `feat(api): add rate limit middleware`
- `fix(auth): handle expired session token`
- `test(parser): cover empty input`
- `docs: clarify local setup`

## Commit quality

- Subject is imperative.
- Subject stays under 72 characters.
- Scope is optional but useful.
- If the change is too broad for one message, split it into multiple commits.
