---
description: End-to-end MR workflow — parse intent, auto-choose branch via protected + open-MR heuristic, commit changes, push and create a GitLab MR immediately, and sync JIRA. Uses glab (preferred) or GitLab MCP. The JIRA Task key is mandatory in both the branch and the MR title. Ported from the UMO saas repo /mr workflow.
---

# /umo-jira-tracker:mr

## Naming standard

- **Branch format:** `{type}/{JIRA-KEY}-{short-description}` — short-description is 2–5 words in kebab-case. (e.g. `feat/PAY-1234-add-kafka-retry`)
- **MR title format:** `{type}(scope): lowercase imperative subject (JIRA-KEY)` — Conventional Commits with the JIRA key in parentheses at the **end**, which keeps the title commitlint-safe. (e.g. `feat(publisher): add kafka retry (PAY-1234)`)

The scope is optional; the type and the trailing key are not.

## The merge gate — why the key is mandatory

**No MR merges without a JIRA Task, and the merge commit references the task.**
This is an org-level backstop, and it is load-bearing in two directions:

- It is what makes bead-to-Jira promotion automatic. Decompose freely in Beads;
  anything that ends in a merge acquires a Jira Task by definition, so nobody has
  to make a judgment call about when a step became a unit of delivery.
- It is what the **merged-PR automation keys off**. The automation flips the Task
  to `Done` when the MR merges, reading the key from the branch and title. A CI
  check fails an MR whose title carries no valid key.

So this command does **not** proceed without a key. If none can be resolved, help
the developer create or find the Task rather than working around it — see
Phase 1c.

For MR creation internals (glab flags, GitLab MCP call), use the `gitlab-mr` skill from your skills list.

---

# Create Merge Request

## Overview

End-to-end MR workflow: parse intent from natural language, manage branches, organize changes into logical conventional commits, **push and create a GitLab MR immediately**, and sync JIRA. Do **not** wait for a commit-plan or MR-preview approval — the developer's request is the approval. JIRA mutations still require explicit approval (Phase 7).

## Phase 1: Parse Input and Clarify

### Step 1a — Detect active bead

Before parsing user input, check for a currently claimed bead:

```bash
bd claimed --json 2>/dev/null
# fallback if 'claimed' subcommand is not available:
bd list --status in-progress --json 2>/dev/null
```

If a claimed bead is found, extract its JIRA key from the `jira:` label (e.g. label `jira:PAY-1234` → key `PAY-1234`). Treat this as the **candidate JIRA key**.

### Step 1b — Reconcile with user input

Extract the following from the user's free-form input. Ask only when a value is truly ambiguous.

| Parameter | How to detect | Default |
|-----------|---------------|---------|
| **JIRA key** | Regex `[A-Z]+-\d+` in input (e.g. `PAY-1234`) | Candidate from active bead (step 1a) |
| **Branch strategy** | Explicit keywords: "current branch", "new branch", "rename branch"; otherwise | **Auto** (Phase 2 heuristic) |
| **Target branch** | Keywords: "target dev", "target main", "into develop" | `dev` (from `.umo/jira-tracker.json` `gitlab.targetBranch`) |
| **Additional context** | Anything else the developer wrote | None |

**JIRA key reconciliation rules:**

- User provided a key **and** it matches the active bead → use it, no confirmation needed.
- User provided a key **different** from the active bead's key → show both and ask:
  ```
  Active bead: [PAY-1234] {bead title}
  You mentioned: PAY-9999
  Which JIRA Task should this MR be linked to? (PAY-1234 / PAY-9999)
  ```
- No key in user input, active bead found → use the bead key and report it post-fact (no yes/no gate).
- No key in user input, no active bead → go to **Step 1c**.

Do **not** ask "new vs current vs rename" on empty input. Do not ask for target branch when config/default applies. The Task is the one thing worth stopping for — see Step 1c.

### Step 1c — No JIRA key resolved

Do not proceed. The MR cannot merge without a Task, and a CI check will fail the
title regardless, so continuing here only produces an MR that has to be renamed.

```
This MR needs a JIRA Task — no MR merges without one, and the merge commit
references it. The merged-PR automation also reads the key from the branch and
title to flip the Task to Done.

  1. Give me the key, if the Task already exists.
  2. Create one now:
     /umo-jira-tracker:create task --parent <SLICE-KEY> --title "..."
  3. If this is tech debt with no obvious home, its home is your squad's
     standing tech-health slice [TH-<KEY>-S0].

Which?
```

If the developer insists on an MR with no key, say plainly that it will fail the
CI title check and will not merge, and stop. Do not build a keyless branch name
or title.

## Phase 2: Branch Setup

### Resolve current branch and target

```bash
git branch --show-current
```

Store as `{current-branch}`. Target is `{target-branch}` from Phase 1 / `.umo/jira-tracker.json` (default `dev`).

### Branch heuristic (no asking)

Explicit developer overrides always win when clear ("use current branch", "rename …", "create new branch").

Otherwise, decide automatically:

1. **Protected / target branch** — if `{current-branch}` equals `{target-branch}`, or is `main`, `master`, or `dev`:
   - Warn briefly: feature work should be on a separate branch.
   - **Always create a new branch** (see below). Do not ask for confirmation. Do not stay on the protected branch unless the developer explicitly overrides.

2. **Otherwise** — treat `{current-branch}` as the developer's feature branch. Detect open MRs (**glab preferred**, GitLab MCP fallback):

```bash
glab mr list --source-branch "{current-branch}"
```

If `glab` is unavailable, use GitLab MCP:

```
CallMcpTool -> gitlab / search
  scope: "merge_requests"
  search: "{current-branch}"
  project_id: "{gitlab-project-id}"
  state: "opened"
```

- **No open MR** for this source branch → **reuse** `{current-branch}` (developer-created feature branch).
- **Open MR exists** → **reuse** `{current-branch}`; show the MR URL; push and update that MR path — do **not** create a second branch or a duplicate MR.

If neither tool is available and the branch is not protected: reuse `{current-branch}` and mention `glab mr list` after auth.

### Create new branch (when heuristic says create)

Naming convention: `{type}/{JIRA-KEY}-{short-description}` (short-description: 2–5 words, kebab-case)

Available types: `feat`, `fix`, `hotfix`, `chore`, `refactor`, `test`, `docs`, `ci`, `perf`, `build`

- The JIRA key is mandatory: `feat/PAY-1234-add-kafka-retry`
- Multiple JIRA keys: `feat/PAY-1234-PAY-1235-login-refactor`
- Derive `{short-description}` from the JIRA summary (if fetched in Phase 3) or from the diff, stripping the slice coordinate prefix — it is already carried by the key. Do **not** stop to confirm the branch name.

```bash
git checkout -b {branch-name}
```

### Rename current branch (only when the developer explicitly asks)

```bash
git branch -m {old-name} {new-name}
```

## Phase 3: Fetch JIRA Context

The key is mandatory by now (Phase 1c). If the Atlassian MCP is available:

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
   - **Summary** (for the MR title and branch name — drop the slice coordinate prefix)
   - **Description** (for "What this MR does?" and "Why?")
   - **Acceptance criteria** (for "How to Test")
   - **Type** (Task or Bug — drives the branch type prefix)
   - **Parent Slice key and summary** (for the MR description's JIRA Task line)

Check the type while you are here. If the key resolves to a **Slice**, **Flow** or **Request**, stop and say so: an MR delivers a Task or fixes a Bug, and linking it to a container would put the wrong thing in front of the merged-PR automation.

If the Atlassian MCP is unavailable, continue with the key the developer gave — the branch and title still carry it, which is what CI and the automation need. Build the description from commit messages and developer input instead.

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

### Step 4.3: Plan Commits Internally

For each commit, determine:

| Attribute | Description |
|-----------|-------------|
| **Type** | `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert` |
| **Scope** | Optional — affected area (e.g., `auth`, `api`, `config`) |
| **Breaking** | Does it break backward compatibility? Add `!` if yes |
| **Description** | Imperative mood, concise summary |
| **Files** | List of files to include in this commit |
| **Order** | Sequence matters — dependencies before dependents |

Do **not** present a commit plan and wait for "yes/no/adjust". Plan silently, then execute in Step 4.4.

For multi-line commit messages, use heredoc syntax:

```bash
git commit -m "$(cat <<'EOF'
feat(auth): add user authentication service

Implement JWT-based authentication with refresh token support.

Closes: #123
EOF
)"
```

**Later adjustment** — only if the developer asks after commits exist:

- **"merge 2 and 3"** — combine commits
- **"split commit 2"** — break into smaller commits
- **"change type of commit 1 to chore"** — modify commit type
- **"add file X to commit 2"** — reassign files
- **"reorder: 2, 1, 3"** — change commit sequence

### Step 4.4: Execute Commits Immediately

For each planned commit, in order:

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

4. **Report progress (post-fact, not a gate):**
   ```
   Commit 1/N created: feat(auth): add user authentication service
   Commit 2/N created: feat(api): add login and logout endpoints
   ...
   ```

### Step 4.5: Post-commit Verification

After all commits are created (or if the working tree was already clean), verify the branch has diverged from the target:

```bash
git log {target-branch}..HEAD --oneline
```

If there are zero commits ahead of the target, warn the developer: "No commits to include in the MR. Aborting." and stop.

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

## Phase 5: Push

Build MR title and description internally (see templates below), then **push immediately** — do not wait for preview approval.

```bash
git push -u origin HEAD
```

Report branch and draft title briefly after push (informational only).

## Phase 6: Create MR

Use this order:

1. **GitLab MCP** (when available and working) — see the `gitlab-mr` skill → `references/mcp.md`
2. **`glab` CLI** (when MCP is unavailable or fails) — see the `gitlab-mr` skill from your skills list
3. **Manual** — copy title and description into the GitLab UI

If an open MR already exists for the source branch (Phase 2), do not create a duplicate — push updates and report the existing URL (update description via GitLab tools only when needed).

### Resolve project ID

If `gitlab.projectId` is null in `.umo/jira-tracker.json`, resolve it now:

```bash
REPO_NAME=$(git remote get-url origin | sed 's/.*\/\([^/]*\)\.git/\1/')
glab api "projects?search=${REPO_NAME}&membership=true" \
  | python3 -c "import json,sys; p=json.load(sys.stdin); [print(x['id'], x['path_with_namespace']) for x in p]"
```

If multiple matches, pick the one matching the remote path; if still ambiguous, ask once. Persist the numeric ID to `.umo/jira-tracker.json` `gitlab.projectId`.

### With GitLab MCP

Read `user.gitlabUserId` from `.umo/jira-tracker.json`. Include `assignee_ids` if set:

```
CallMcpTool -> gitlab / create_merge_request
  id: "{gitlab-project-id}"
  title: "{MR title}"
  source_branch: "{source-branch}"
  target_branch: "{target-branch}"
  description: "{MR description}"
  assignee_ids: ["{user.gitlabUserId}"]   // omit if null in config
```

Report the MR URL to the developer on success.

### With glab (fallback when MCP is unavailable)

Run from the **repository root** (where `origin` points at the GitLab project). Read the `gitlab-mr` skill (from your skills list) for full flags and troubleshooting.

**Non-interactive create** (after push):

Read `user.gitlabUserId` from `.umo/jira-tracker.json`. If set, add `--assignee`:

```bash
glab mr create \
  --target-branch "{target-branch}" \
  --source-branch "{source-branch}" \
  --title "{MR title}" \
  --description "{MR description markdown}" \
  --assignee "{user.gitlabUsername}" \
  --yes \
  --no-editor
```

Omit `--assignee` if `user.gitlabUsername` is null in config.

On success, print the MR URL (`glab mr view` or the command output).

### Without GitLab MCP or glab

Output the MR title and description as a copyable markdown block so the developer can create the MR manually in the GitLab UI.

## Phase 7: JIRA Update (requires approval)

Execute when the Atlassian MCP is available.

> **Do not transition the JIRA Task.** Two reasons, each sufficient on its own. Creating an MR does not mean the work is finished — the developer may open several MRs for one Task. And **Task Done belongs to the merged-PR automation**, which fires on merge and reads the key from the branch and title; transitioning from here would race it and claim a state this command has not verified. `/umo-jira-tracker:close` handles the explicit case.

Delegate to the `jira-sync-back` skill `/mr` complete flow, which performs:

1. **Operation A — Comment**: post an MR-created comment to the JIRA ticket.

   Draft:
   ```markdown
   MR created: {MR_URL}

   ### Changes
   - {commit message 1}
   - {commit message 2}
   ```

2. **Operation C — Description update**: append (or extend) the MR delivery section in the JIRA ticket description with the MR URL, branch, one-line summary, and commit list.

Both previews are shown together before any action. Developer can approve both, approve individually, or skip either.

If the developer declines the JIRA update entirely, skip it.

---

## MR Title Format

```
{type}(scope): lowercase imperative subject (JIRA-KEY)
```

Conventional Commits with the JIRA key in parentheses at the **end** — this keeps
the title commitlint-safe while still carrying the key that CI checks for and that
the merged-PR automation reads.

- Scope is optional; the type and the trailing key are not.
- Subject is lowercase, imperative, no trailing period.
- Derive the subject from the JIRA summary or the commits, dropping the slice
  coordinate prefix — the key already locates the work.

Example: `feat(publisher): add kafka retry (PAY-1234)`

There is no keyless form. See Phase 1c.

## MR Description Template

```markdown
## JIRA Task
[{JIRA-KEY}](https://umotech.atlassian.net/browse/{JIRA-KEY}) — under slice [{SLICE-KEY}](https://umotech.atlassian.net/browse/{SLICE-KEY})

## What this MR does?
{Auto-generated from JIRA description + bead Notes + commit analysis}

## Why?
{From JIRA ticket context or developer input}

## Changes Made
{Bullet list generated from git log {target-branch}..HEAD --oneline}

## How to Test
{From JIRA acceptance criteria / bead Refined AC if available, otherwise leave placeholder}

## Checklist
- [ ] Added tests
- [ ] Updated documentation
- [ ] Self-reviewed code
```

Omit the slice link from the JIRA Task line if the Task's parent could not be resolved.

## Branch Naming Convention

Format: `{type}/{JIRA-KEY}-{short-description}`

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

- **Bug** → `fix/`
- **Task** → from the nature of the change: `feat/`, `refactor/`, `chore/`, `test/`, `docs/`, `ci/`, `perf/`, `build/`. Pick from the diff; ask only if it is genuinely ambiguous.

Flow, Slice and Request never appear here — an MR delivers a Task or fixes a Bug.

## Example Invocations

**Explicit — current branch with a JIRA Task:**

```
/umo-jira-tracker:mr in current branch using JIRA task PAY-1234
```

Parsed: branch strategy = current (explicit), JIRA key = PAY-1234, target = dev. Commits/push/MR run immediately.

**No input — auto branch heuristic:**

```
/umo-jira-tracker:mr
```

On target/protected → create new branch automatically. On a feature branch with no open MR → reuse it. On a feature branch with an open MR → reuse and update. Uses the claimed bead's JIRA key; stops at Phase 1c if there is none. No branch-strategy quiz.

**New branch with a JIRA Task:**

```
/umo-jira-tracker:mr create new branch for PAY-5678
```

Parsed: branch strategy = new (explicit), JIRA key = PAY-5678, target = dev. Agent fetches the JIRA summary to derive the branch name and proceeds immediately.

**No JIRA key available:**

```
/umo-jira-tracker:mr push current branch and create MR
```

No claimed bead, no key in the input → Phase 1c. The command helps the developer find or create the Task, and does not build a keyless branch or title. This is the one stop that survives the no-gates rule.
