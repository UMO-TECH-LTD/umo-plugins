---
description: Analyze changes, group them into atomic conventional commits, create the commits immediately, and generate an MR description. Follows STD-JIRA naming — JIRA key in commit footer and MR title. Ported from the UMO saas repo commit workflow.
---

# /umo-jira-tracker:commit

## Naming standard

> Based on the internal Confluence standard **"STD-JIRA and GitLab Branch/MR Naming"**.

- **Branch:** `{type}/{JIRA-KEY}-{short-description}` — types: `feat`, `fix`, `hotfix`, `chore`, `refactor`, `test`, `docs`, `ci`, `perf`, `build`; short-description 2–5 words kebab-case.
- **Commit:** `type(scope): description` (Conventional Commits) — include JIRA key in footer (`Closes: CWN-1234`) or branch name.
- **MR title:** `{JIRA-KEY}: {Description}` — conventional type prefix is **not** required in MR titles, only in commit messages.

If a JIRA key is associated with the current branch (detectable from branch name pattern `{type}/{KEY}-{slug}`) or from the currently claimed bead, include it in the MR title: `{KEY}: {description}`.

---

# Create Conventional Commits

## Overview

Analyze completed work, organize changes into logical commits, and create well-structured commit messages following the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification.

This command helps split a batch of changes into atomic, meaningful commits grouped by feature or purpose. When the developer asks to commit, **plan internally and create commits immediately** — do not present a plan and wait for "yes/no/adjust".

## Workflow

### Step 1: Analyze Current State

Gather information about all changes:

```bash
# See all changed files (staged and unstaged)
git status

# View recent commits for style consistency
git log --oneline -10

# Get full diff of all changes
git diff HEAD
```

Read the content of each changed file to understand what was implemented.

### Step 2: Categorize Changes by Topic

Group related changes into logical commits. Consider:

- **By feature**: All files related to a single feature together
- **By layer**: Sometimes separating domain/service/infra makes sense
- **By type**: Tests separate from implementation, docs separate from code
- **Dependencies first**: Config/dependency changes before code that uses them

Each commit should be:
- **Atomic**: Can be reverted independently
- **Buildable**: Code compiles/runs after this commit
- **Logical**: Changes belong together conceptually

### Step 3: Plan Commits Internally

For each commit, determine:

| Attribute | Description |
|-----------|-------------|
| **Type** | `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert` |
| **Scope** | Optional - affected area (e.g., `auth`, `api`, `config`) |
| **Breaking** | Does it break backward compatibility? Add `!` if yes |
| **Description** | Imperative mood, concise summary |
| **Files** | List of files to include in this commit |
| **Order** | Sequence matters - dependencies before dependents |

Do **not** show a proposed-commit preview and wait for approval. Proceed to Step 4 immediately.

For multi-line commit messages, use heredoc syntax:

```bash
git add file1 file2
git commit -m "$(cat <<'EOF'
feat(auth): add user authentication service

Implement JWT-based authentication with refresh token support.

Closes: #123
EOF
)"
```

### Step 4: Execute Commits Immediately

For each commit in order:

1. **Stage specific files:**
   ```bash
   git add <file1> <file2> ...
   ```

2. **Create commit with conventional message:**
   ```bash
   git commit -m "$(cat <<'EOF'
   type(scope): description

   Optional body with context.

   Footer: value
   EOF
   )"
   ```

3. **Verify before proceeding to next:**
   ```bash
   git log -1 --stat
   ```

4. **Report progress (post-fact, not a gate):**
   ```
   ✓ Commit 1/N created: feat(auth): add user authentication service
   ✓ Commit 2/N created: feat(api): add login and logout endpoints
   ...
   ```

### Step 5: Generate MR Description

After all commits are created:

1. **Read committed changes only:**
   ```bash
   # Get commits on current branch not in dev/main/master
   git log dev..HEAD --oneline

   # View full content of those commits
   git log dev..HEAD --stat -p
   ```

2. **Ignore uncommitted changes** - Only analyze what was committed, not staged/unstaged changes

3. **Detect JIRA key** from current branch name (regex `[A-Z]+-\d+`) or from the currently claimed bead's `jira:` label.

4. **Generate MR description** with title and copyable markdown snippet:

**MR Title:** `{JIRA-KEY}: Brief description of the overall change`
(Without JIRA key: `type(scope): description`)

**MR Description (copy this):**

```markdown
## JIRA Ticket
[{JIRA-KEY}](https://umotech.atlassian.net/browse/{JIRA-KEY})

## What this MR does?
[Describe the new feature or the bug fix]

## Why?
[Explain the motivation for the change]

## Changes Made
* [Change 1]
* [Change 2]

## How to Test
1. [Step 1]
2. [Step 2]

## Checklist
- [ ] Added tests
- [ ] Updated documentation
- [ ] Self-reviewed code
```

## Commit Type Reference

| Type | When to Use | SemVer |
|------|-------------|--------|
| `feat` | New feature for users | MINOR |
| `fix` | Bug fix for users | PATCH |
| `docs` | Documentation only | - |
| `style` | Formatting, whitespace | - |
| `refactor` | Code restructuring, no behavior change | - |
| `perf` | Performance improvement | - |
| `test` | Adding/fixing tests | - |
| `build` | Build system, dependencies | - |
| `ci` | CI/CD configuration | - |
| `chore` | Maintenance, tooling | - |
| `revert` | Reverting previous commit | - |

## Breaking Changes

If a commit introduces breaking changes:
- Add `!` after type/scope: `feat(api)!: change response format`
- Or add footer: `BREAKING CHANGE: description of what breaks`

## Message Guidelines

- **Description**: Imperative mood ("add" not "added"), lowercase, no period
- **Body**: Explain motivation and context, wrap at 72 characters
- **Footer**: Reference issues (`Closes: #123`), note breaking changes

## Example Session

```
User: /umo-jira-tracker:commit

AI: Analyzing changes, then creating commits...

[Runs git status, git diff HEAD, reads changed files]

✓ Commit 1/3 created: build(deps): add redis client dependency
✓ Commit 2/3 created: feat(cache): add Redis cache service with TTL support
✓ Commit 3/3 created: feat(api): add cache headers to API responses

All 3 commits created successfully!

---

## MR Description

**MR Title:** `CWN-4567: Add Redis caching with API response headers`

**MR Description (copy this):**

```markdown
## JIRA Ticket
[CWN-4567](https://umotech.atlassian.net/browse/CWN-4567)

## What this MR does?
Adds Redis-based caching service with TTL support and integrates cache headers into API responses for improved performance.

## Why?
Reduce database load and improve API response times for frequently accessed data.

## Changes Made
* Added Redis client dependency
* Implemented cache service with TTL support and comprehensive tests
* Added cache middleware for HTTP responses
* Integrated caching in user handler

## How to Test
1. Start Redis locally: `docker run -p 6379:6379 redis`
2. Run the service: `make run`
3. Hit `/api/users` endpoint twice, verify second request uses cache header

## Checklist
- [ ] Added tests
- [ ] Updated documentation
- [ ] Self-reviewed code
```
```

## Later Adjustments

If the developer asks to modify commits **after** they were created:

- **"merge 2 and 3"** - Combine commits
- **"split commit 2"** - Break into smaller commits
- **"change type of commit 1 to chore"** - Modify commit type
- **"add file X to commit 2"** - Reassign files
- **"reorder: 2, 1, 3"** - Change commit sequence
