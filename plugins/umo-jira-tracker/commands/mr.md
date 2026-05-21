---
description: End-to-end MR workflow — parse intent, manage branches, commit changes, push, create a GitLab MR, and sync JIRA. Uses glab (preferred) or GitLab MCP. Follows STD-JIRA branch and MR naming. Ported from the UMO saas repo /mr workflow.
---

# /umo-jira-tracker:mr

## Naming standard

> Based on the internal Confluence standard **"STD-JIRA and GitLab Branch/MR Naming"**.

- **Branch format:** `{type}/{JIRA-KEY}-{short-description}` — short-description is 2–5 words in kebab-case. (e.g. `feat/CWN-1234-add-kafka-retry`)
- **MR title format:** `{JIRA-KEY}: {Short description}` — JIRA key at the start triggers GitLab's automatic ticket linking. Conventional commit types (`feat:`, `fix:`) are for commit messages only and are **not** required in MR titles. (e.g. `CWN-1234: Add Kafka retry`)

For MR creation internals (glab flags, GitLab MCP call), use the `gitlab-mr` skill from your skills list.

---

# Create Merge Request

## Overview

End-to-end MR workflow: parse intent from natural language, manage branches, organize changes into logical conventional commits, push with developer approval, create a GitLab MR, and sync JIRA.

## Phase 1: Parse Input and Clarify

Extract the following from the user's free-form input. If any are ambiguous or missing, ask the developer before proceeding.

| Parameter | How to detect | Default |
|-----------|---------------|---------|
| **JIRA key** | Regex `[A-Z]+-\d+` in input (e.g. `CWN-1234`) or from claimed bead's `jira:` label | None (optional) |
| **Branch strategy** | Keywords: "current branch", "new branch", "rename branch" | Ask |
| **Target branch** | Keywords: "target dev", "target main", "into develop" | `dev` (from `.umo/jira-tracker.json` `gitlab.targetBranch`) |
| **Additional context** | Anything else the developer wrote | None |

If the input is empty or unclear, ask:

1. Do you want to use the current branch, create a new one, or rename the current branch?
2. Is there a JIRA ticket for this work? (optional)
3. What is the target branch? (default: from config or `dev`)

## Phase 2: Branch Setup

### Main branch guard

```bash
git branch --show-current
```

If the current branch is `main`, `master`, or `dev`:

- **STOP.** Warn the developer: "You are on `main`/`dev`. Per convention, feature work should be on a separate branch."
- Ask for confirmation: create a new branch, or explicitly override to stay on the protected branch.
- Only proceed if the developer explicitly confirms after the warning.

### Branch strategies

**Use current branch (non-protected):**

```bash
git branch --show-current
```

Show the branch name and confirm with the developer.

**Create new branch:**

Naming convention: `{type}/{JIRA-KEY}-{short-description}` (short-description: 2–5 words, kebab-case)

Available types: `feat`, `fix`, `hotfix`, `chore`, `refactor`, `test`, `docs`, `ci`, `perf`, `build`

- If a JIRA key is available, include it: `feat/CWN-1234-add-kafka-retry`
- Multiple JIRA keys: `feat/CWN-1234-CWN-1235-login-refactor`
- If no JIRA key: `feat/add-kafka-retry`
- Derive `{short-description}` from the JIRA summary (if fetched in Phase 3) or ask the developer.

```bash
git checkout -b {branch-name}
```

**Rename current branch:**

```bash
git branch -m {old-name} {new-name}
```

### Check for existing MR

**Preferred:** GitLab MCP — check whether an MR already exists for this branch:

```
CallMcpTool -> gitlab / search
  scope: "merge_requests"
  search: "{branch-name}"
  project_id: "{gitlab-project-id}"
  state: "opened"
```

If an MR already exists, show it to the developer and ask whether to update it or abort.

**If GitLab MCP is unavailable:** use `glab` (see the `gitlab-mr` skill from your skills list):

```bash
glab mr list --source-branch "{branch-name}"
```

If `glab` is not installed or not authenticated, skip this check and mention that the developer can run `glab mr list` after `glab auth login`.

## Phase 3: Fetch JIRA Context (optional)

If a JIRA key was provided and the Atlassian MCP is available:

1. Get the cloud ID (once per session):

```
CallMcpTool -> Atlassian / getAccessibleAtlassianResources
```

2. Fetch the ticket:

```
CallMcpTool -> Atlassian / getJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{JIRA-KEY}"
```

3. Extract and store for later use:
   - **Summary** (for MR title and branch name)
   - **Description** (for "What this MR does?" and "Why?")
   - **Acceptance criteria** (for "How to Test")
   - **Priority and type** (for branch type prefix if creating a new branch)

If the Atlassian MCP is unavailable or no JIRA key was given, skip this phase. The MR description will be built from commit messages and developer input instead.

Also check the currently claimed bead for context (Notes, Refined AC) to enrich the MR description.

## Phase 4: Commit Changes

```bash
git status
```

- **If working tree is clean:** skip to the divergence check at the end of this phase (commits already exist on the branch).
- **If there are uncommitted changes:** follow Steps 4.1–4.5 below to create well-structured commits.

### Step 4.1: Analyze Changes

Gather information about all uncommitted work:

```bash
git status
git log --oneline -10
git diff HEAD
```

Read the content of each changed file to understand what was implemented.

### Step 4.2: Categorize Changes by Topic

Group related changes into logical commits. Consider:

- **By feature**: All files related to a single feature together
- **By layer**: Sometimes separating domain/service/infra makes sense
- **By type**: Tests separate from implementation, docs separate from code
- **Dependencies first**: Config/dependency changes before code that uses them

Each commit must be:
- **Atomic**: Can be reverted independently
- **Buildable**: Code compiles/runs after this commit
- **Logical**: Changes belong together conceptually

### Step 4.3: Prepare and Present Commit Plan

For each proposed commit, determine:

| Attribute | Description |
|-----------|-------------|
| **Type** | `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert` |
| **Scope** | Optional — affected area (e.g., `auth`, `api`, `config`) |
| **Breaking** | Does it break backward compatibility? Add `!` if yes |
| **Description** | Imperative mood, concise summary |
| **Files** | List of files to include in this commit |
| **Order** | Sequence matters — dependencies before dependents |

Present the plan to the developer in this format:

```
## Proposed Commits

### Commit 1 of N
**Message:** `type(scope): description`
**Files:**
- path/to/file1
- path/to/file2

**Rationale:** Why these files belong together

**Commands:**
git add path/to/file1 path/to/file2
git commit -m "type(scope): description"

---

(repeat for all commits)

## Summary
- Total commits: N
- Types: X feat, Y fix, Z chore
- Breaking changes: Yes/No

Ready to proceed? (yes/no/adjust)
```

For multi-line commit messages, use heredoc syntax:

```bash
git commit -m "$(cat <<'EOF'
feat(auth): add user authentication service

Implement JWT-based authentication with refresh token support.

Closes: #123
EOF
)"
```

**Adjustment protocol** — if the developer wants changes:

- **"merge 2 and 3"** — combine commits
- **"split commit 2"** — break into smaller commits
- **"change type of commit 1 to chore"** — modify commit type
- **"add file X to commit 2"** — reassign files
- **"reorder: 2, 1, 3"** — change commit sequence

Revise the plan and re-present until the developer approves.

### Step 4.4: Execute Commits (after approval)

For each commit in the approved plan, in order:

1. **Stage specific files:**
   ```bash
   git add <file1> <file2> ...
   ```

2. **Create commit with conventional message:**
   ```bash
   git commit -m "type(scope): description"
   ```

3. **Verify before proceeding to next:**
   ```bash
   git log -1 --stat
   ```

4. **Report progress:**
   ```
   Commit 1/N created: feat(auth): add user authentication service
   Commit 2/N created: feat(api): add login and logout endpoints
   ...
   ```

### Step 4.5: Post-commit Verification

After all commits are created (or if the working tree was already clean), verify the branch has diverged from the target:

```bash
git log dev..HEAD --oneline
```

If there are zero commits ahead of `dev`, warn the developer: "No commits to include in the MR. Aborting." and stop.

### Commit Message Reference

| Type | When to Use |
|------|-------------|
| `feat` | New feature for users |
| `fix` | Bug fix for users |
| `docs` | Documentation only |
| `style` | Formatting, whitespace |
| `refactor` | Code restructuring, no behavior change |
| `perf` | Performance improvement |
| `test` | Adding/fixing tests |
| `build` | Build system, dependencies |
| `ci` | CI/CD configuration |
| `chore` | Maintenance, tooling |
| `revert` | Reverting previous commit |

- **Description**: Imperative mood ("add" not "added"), lowercase, no period
- **Body**: Explain motivation and context, wrap at 72 characters
- **Breaking changes**: Add `!` after type/scope (`feat(api)!: change response format`) or footer (`BREAKING CHANGE: description`)

## Phase 5: Preview and Push (approval gate)

Build and display a full preview for the developer:

```
## MR Preview

**Branch:** {source-branch} -> {target-branch}

**Commits:**
{output of git log dev..HEAD --oneline}

**MR Title:** {draft title}

**MR Description:**
{draft description — see MR Description Template below}

---

Ready to push and create MR? (yes / adjust / abort)
```

- **Do NOT push until the developer approves.**
- If the developer says "adjust", ask what to change and update the preview.
- On approval:

```bash
git push -u origin HEAD
```

## Phase 6: Create MR

Use this order:

1. **GitLab MCP** (when available and working) — see the `gitlab-mr` skill → `references/mcp.md`
2. **`glab` CLI** (when MCP is unavailable or fails) — see the `gitlab-mr` skill from your skills list
3. **Manual** — copy title and description into the GitLab UI

### Resolve project ID

If `gitlab.projectId` is null in `.umo/jira-tracker.json`, resolve it now:

```bash
REPO_NAME=$(git remote get-url origin | sed 's/.*\/\([^/]*\)\.git/\1/')
glab api "projects?search=${REPO_NAME}&membership=true" \
  | python3 -c "import json,sys; p=json.load(sys.stdin); [print(x['id'], x['path_with_namespace']) for x in p]"
```

Present matches, ask the developer to confirm, and persist the numeric ID to `.umo/jira-tracker.json` `gitlab.projectId`.

### With GitLab MCP

```
CallMcpTool -> gitlab / create_merge_request
  id: "{gitlab-project-id}"
  title: "{MR title}"
  source_branch: "{source-branch}"
  target_branch: "{target-branch}"
  description: "{MR description}"
```

Report the MR URL to the developer on success.

### With glab (fallback when MCP is unavailable)

Run from the **repository root** (where `origin` points at the GitLab project). Read the `gitlab-mr` skill (from your skills list) for full flags and troubleshooting.

**Non-interactive create** (after push):

```bash
glab mr create \
  --target-branch "{target-branch}" \
  --source-branch "{source-branch}" \
  --title "{MR title}" \
  --description "{MR description markdown}" \
  --yes \
  --no-editor
```

On success, print the MR URL (`glab mr view` or the command output).

### Without GitLab MCP or glab

Output the MR title and description as a copyable markdown block so the developer can create the MR manually in the GitLab UI.

## Phase 7: JIRA Update (optional, requires approval)

Only execute if a JIRA key was provided AND the Atlassian MCP is available.

1. Draft a comment for the JIRA ticket:

```markdown
MR created: {MR_URL}

### Changes
{bullet list of commits}
```

2. Look up available transitions:

```
CallMcpTool -> Atlassian / getTransitionsForJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{JIRA-KEY}"
```

3. **Show the developer what will be posted and which status transition is proposed** (use `jira.transitionOnMr` from config, default `"In Review"`). Never update JIRA without explicit approval.

4. On approval:

```
CallMcpTool -> Atlassian / addCommentToJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{JIRA-KEY}"
  commentBody: "{comment}"
```

```
CallMcpTool -> Atlassian / transitionJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{JIRA-KEY}"
  transition: { "id": "{transition-id}" }
```

If the developer declines the JIRA update, skip it.

---

## MR Title Format

- With JIRA key: `{JIRA-KEY}: {Short description from JIRA summary or commits}`
- Without JIRA key: `{type}: {description from commits}` (conventional commit style)

## MR Description Template

```markdown
## JIRA Ticket
[{JIRA-KEY}](https://umotech.atlassian.net/browse/{JIRA-KEY})

## What this MR does?
{Auto-generated from JIRA description + bead Notes + commit analysis}

## Why?
{From JIRA ticket context or developer input}

## Changes Made
{Bullet list generated from git log dev..HEAD --oneline}

## How to Test
{From JIRA acceptance criteria / bead Refined AC if available, otherwise ask developer or leave placeholder}

## Checklist
- [ ] Added tests
- [ ] Updated documentation
- [ ] Self-reviewed code
```

When no JIRA key is provided, omit the "JIRA Ticket" section entirely.

## Branch Naming Convention

Format: `{type}/{JIRA-KEY}-{short-description}` (or `{type}/{short-description}` without JIRA)

| Type | When to use |
|------|-------------|
| `feat/` | New feature |
| `fix/` | Bug fix |
| `hotfix/` | Critical production fix |
| `refactor/` | Code restructuring |
| `docs/` | Documentation |
| `chore/` | Maintenance, tooling |
| `test/` | Adding or fixing tests |
| `ci/` | CI/CD configuration |
| `perf/` | Performance improvement |
| `build/` | Build system, dependencies |

Derive the type from the JIRA issue type when available:
- Story / Feature -> `feat/`
- Bug -> `fix/`
- Task / Sub-task -> `feat/` (or ask developer)
- Epic -> `feat/`

## Example Invocations

**Explicit — current branch with JIRA ticket:**

```
/umo-jira-tracker:mr in current branch using JIRA ticket CWN-1234
```

Parsed: branch strategy = current, JIRA key = CWN-1234, target = dev.

**Interactive — no input:**

```
/umo-jira-tracker:mr
```

Agent asks: branch strategy? JIRA key? target branch? Then proceeds through all phases.

**New branch with JIRA ticket:**

```
/umo-jira-tracker:mr create new branch for CWN-5678
```

Parsed: branch strategy = new, JIRA key = CWN-5678, target = dev. Agent fetches JIRA summary to derive branch name.

**No JIRA, current branch:**

```
/umo-jira-tracker:mr push current branch and create MR
```

Parsed: branch strategy = current, no JIRA, target = dev. MR description built from commits only.
