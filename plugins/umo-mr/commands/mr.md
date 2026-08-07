---
description: End-to-end MR workflow — parse intent, autodetect the default branch, auto-choose branch via protected-branch + open-MR heuristic, organize changes into logical conventional commits, push and create a GitLab MR immediately, and optionally sync JIRA. Uses glab (preferred) or GitLab MCP (fallback). Applies trunk-based, squash-merge, commitlint-safe conventions by default, overridable per repo via .umo/mr.json. Invoke this command whenever the developer asks to create, open, or push a merge request, or whenever you decide finished work should become one. Ported from the UMO saas repo /mr workflow.
---

# /mr

## Overview

End-to-end MR workflow: parse intent from natural language, autodetect the repo's default branch, choose the source branch via the Phase 2 heuristic (or explicit developer override), organize changes into logical conventional commits, **push and create a GitLab MR immediately**, and optionally link a JIRA ticket. Do **not** wait for a commit-plan or MR-preview approval — the developer's request to create commits or an MR is the approval.

**Use this command whenever the developer asks to create/open/push a merge request or PR, or whenever you determine that completed work is ready to ship as one.** It is the org-default entry point for MR creation — never call `glab mr create` or a GitLab MCP `create_merge_request` tool directly outside of this flow.

This command is **repo-agnostic**. It ships with UMO's default conventions (ported from the `saas` repo: trunk-based development, squash merge, Conventional Commit MR titles with the JIRA key in parentheses at the end), but every default can be overridden per repo via an optional `.umo/mr.json` config file. If that file is missing, proceed with the defaults below — do not ask the developer to create it unless a default clearly does not fit (e.g. no `origin` remote, or a non-GitLab remote).

## Repo config (optional, `.umo/mr.json`)

If present at the repo root, read it and use its values instead of the defaults documented in each phase below. Never fail if it's missing or partial — merge whatever keys exist with defaults.

```json
{
    "gitlab": {
        "remote": "origin",
        "projectId": null,
        "targetBranch": "main",
        "mrTool": "glab",
        "squash": true
    },
    "jira": {
        "enabled": true,
        "baseUrl": "https://umotech.atlassian.net",
        "defaultProjectKey": null
    },
    "commit": {
        "allowedTypes": ["feat", "fix", "refactor", "chore", "test", "docs", "ci", "perf", "build", "revert"],
        "maxSubjectLength": 120
    },
    "mrTemplatePath": ".gitlab/merge_request_templates/Default.md",
    "user": {
        "gitlabUsername": null
    }
}
```

See the `gitlab-mr` skill and this plugin's `README.md` for the full schema and field meanings.

## Phase 1: Parse Input and Clarify

Extract the following from the user's free-form input. Ask only when a value is truly ambiguous and cannot be defaulted or auto-detected.

| Parameter              | How to detect                                                                                                                | Default                          |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| **JIRA key**           | Regex `[A-Z]+-\d+` in input (e.g. `CWN-1234`)                                                                                | None (optional)                  |
| **Branch strategy**    | Explicit keywords: "current branch", "rename branch", "create new branch"; otherwise                                         | **Auto** (Phase 2 heuristic)     |
| **Target branch**      | Keywords: "target main", "into main", "into develop"; else `.umo/mr.json` → `gitlab.targetBranch`; else autodetect (Phase 2) | Autodetected repo default branch |
| **Additional context** | Anything else the developer wrote                                                                                            | None                             |

Do **not** ask "new vs current vs rename" on empty `/mr` input. Branch choice is decided in Phase 2. Explicit overrides still win when clear.

If the input is empty or unclear, ask only what's actually missing (e.g. optional JIRA key). Do not ask for the target branch — it is autodetected in Phase 2 unless the developer names one explicitly.

## Phase 2: Branch Setup

### Autodetect the default/target branch

Resolve the target branch before doing anything else, in this order:

1. Explicit developer input from Phase 1 (e.g. "target main", "into develop").
2. `.umo/mr.json` → `gitlab.targetBranch`, if set.
3. Autodetect the repo's actual default branch:

```bash
git remote show origin | sed -n '/HEAD branch/s/.*: //p'
# or, if that's slow/unavailable:
git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'
```

4. If autodetection fails (no remote, detached HEAD, ambiguous result), fall back to checking for `main` then `master` locally/remotely, and if still unclear, ask the developer.

Do not hardcode `main` — many repos differ, and this command must work across the whole org. Store the resolved value as `{target-branch}` for use in every phase below.

### Resolve current branch

```bash
git branch --show-current
```

Store as `{current-branch}`.

### Branch heuristic (no asking)

Explicit developer overrides always win when clear ("use current branch", "rename …", "create new branch").

Otherwise, decide automatically:

1. **Protected / target branch** — if `{current-branch}` equals `{target-branch}`, or is `main`, `master`, or `dev`:
    - Warn briefly: feature work should be on a short-lived branch.
    - **Always create a new branch** (see below). Do not ask for confirmation. Do not stay on the protected branch unless the developer explicitly overrides.

2. **Otherwise** — treat `{current-branch}` as the developer's feature branch. Detect open MRs (**glab preferred**, GitLab MCP fallback):

```bash
glab mr list --source-branch "{current-branch}"
```

If `glab` is not installed or not authenticated, fall back to the GitLab MCP:

```
CallMcpTool -> GitLab / search
  scope: "merge_requests"
  search: "{current-branch}"
  project_id: "{gitlab-project-id}"
  state: "opened"
```

- **No open MR** for this source branch → **reuse** `{current-branch}` (developer-created feature branch).
- **Open MR exists** → **reuse** `{current-branch}`; show the MR URL; push and update that MR path — do **not** create a second branch or a duplicate MR.

If neither `glab` nor the GitLab MCP is available, and the branch is not protected: reuse `{current-branch}` and mention the developer can verify with `glab mr list` after `glab auth login`.

### Create new branch (when heuristic says create)

Naming convention: `{type}/{JIRA-KEY}-{short-description}` — branch from `{target-branch}`.

- Allowed types: `feat/`, `fix/`, `refactor/`, `docs/`, `chore/`, `test/`, `ci/`, `perf/`, `build/`
- If a JIRA key is available, include it: `feat/CWN-1234-add-kafka-retry`
- If no JIRA key: `feat/add-kafka-retry`
- Derive `{short-description}` from the JIRA summary (if fetched in Phase 3) or from the diff. Do **not** stop to confirm the branch name.

```bash
git fetch origin {target-branch}
git checkout -b {branch-name} origin/{target-branch}
```

### Rename current branch (only when the developer explicitly asks)

```bash
git branch -m {old-name} {new-name}
```

### Resolve remote and project

```bash
git remote get-url origin
```

`glab` resolves the GitLab project from the current directory's remote automatically — no explicit ID needed for most `glab` commands, so this step usually requires no extra work when using `glab`. If you need a numeric project ID anyway (e.g. for a GitLab MCP fallback), check `.umo/mr.json` → `gitlab.projectId` first, then resolve it via the GitLab MCP `search` tool (`scope: "projects"`, matching the org/repo path parsed from the remote URL).

## Phase 3: Fetch JIRA Context (optional)

Skip this phase entirely if `.umo/mr.json` sets `jira.enabled: false`.

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

## Phase 4: Commit Changes

```bash
git status
```

### Step 4.1: Analyze Changes

Gather information about all uncommitted work:

```bash
git status
git log --oneline -10
git diff HEAD
```

Read the content of each changed file to understand what was implemented.

> **Optional formatting gate:** if the repo has a formatter convention for the language(s) touched (e.g. `go fmt`, `prettier`, `gofmt`, a `lint-staged` config), run it before planning commits and fold any resulting diffs into the relevant commit. Detect this from the repo's own tooling (e.g. `go.mod` presence, `package.json` `lint-staged`/`prettier` config) rather than assuming — this is a per-repo detail, not a UMO MR default.

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

| Attribute       | Description                                                                                  |
| --------------- | -------------------------------------------------------------------------------------------- |
| **Type**        | `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert` |
| **Scope**       | Optional — affected area (e.g., `auth`, `api`, `config`, or service name in a monorepo)      |
| **Breaking**    | Does it break backward compatibility? Add `!` if yes                                         |
| **Description** | Imperative mood, concise summary                                                             |
| **Files**       | List of files to include in this commit                                                      |
| **Order**       | Sequence matters — dependencies before dependents                                            |

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

If there are zero commits ahead of the target branch, warn the developer: "No commits to include in the MR. Aborting." and stop.

### Commit Message Reference

Individual commit types matter for code organisation; if the repo squash-merges (the UMO default), the **MR title** drives any automated release/SemVer tooling — see "Squash merge & release" below.

| Type       | When to Use                            |
| ---------- | -------------------------------------- |
| `feat`     | New feature for users                  |
| `fix`      | Bug fix for users                      |
| `docs`     | Documentation only                     |
| `refactor` | Code restructuring, no behavior change |
| `perf`     | Performance improvement                |
| `test`     | Adding/fixing tests                    |
| `build`    | Build system, dependencies             |
| `ci`       | CI/CD configuration                    |
| `chore`    | Maintenance, tooling                   |
| `revert`   | Reverting previous commit              |

- **Description**: Imperative mood ("add" not "added"), **lowercase** (commitlint `subject-case` — no leading `CWN-1234`, no Capitalized words), no trailing dot
- **JIRA in MR title**: end with `(JIRA-KEY)` — e.g. `fix(statistic): trigger patch release (CWN-6215)`
- **Body**: Explain motivation and context, wrap at 72 characters
- **Breaking changes**: Avoid `feat!`/`BREAKING CHANGE:` unless explicitly agreed with the platform/DevOps team — most UMO repos avoid major bumps; prefer `feat` instead.

## Pipeline gates (check before merge)

If the target repo runs an MR pipeline (check `.gitlab-ci.yml` for a `commitlint` job or similar), warn the developer about these common blocking checks when relevant:

- **`commitlint`**: validates the MR title against Conventional Commits. **Blocks the pipeline** when invalid. Fix the title in GitLab (Edit → Title) and re-run — no push needed.
- **Migration checks** (for repos with SQL migrations): missing lock-timeout headers, destructive DDL, or code+destructive-migration mixed in one MR often require an expand/contract split and a dedicated label (e.g. `contract-migration`).
- **Secret/vulnerability scans** (e.g. `gitleaks`, image/dependency scanning): typically blocking — no secrets, no unfixed critical vulnerabilities.

Treat this section as informational; do not assume every repo has these jobs — inspect the repo's own CI config if you need certainty.

## Phase 5: Push

Build MR title and description internally (see templates below), then **push immediately** — do not wait for preview approval.

```bash
git push -u origin HEAD
```

Report branch and draft title briefly after push (informational only).

## Phase 6: Create MR

Use this order:

1. **`glab` CLI** (default/preferred) — see the `gitlab-mr` skill
2. **GitLab MCP** (fallback, when `glab` is not installed, not authenticated, or fails) — unless `.umo/mr.json` sets `gitlab.mrTool: "mcp"`, in which case try MCP first and fall back to `glab`
3. **Manual** — copy title and description into the GitLab UI, if neither is available

If an open MR already exists for the source branch (Phase 2), do not create a duplicate — push updates and report the existing URL (update description via GitLab tools only when needed).

### With glab (default)

Requires **glab ≥ v1.103.0** (`glab version`; upgrade with `brew upgrade glab`). Run from the **repository root** (where `origin` points at the GitLab project). Read the `gitlab-mr` skill for full flags and troubleshooting.

**Non-interactive create** (after push):

```bash
glab mr create \
  --target-branch "{target-branch}" \
  --source-branch "{source-branch}" \
  --title "{MR title}" \
  --description "{MR description markdown}" \
  --squash-before-merge \
  --yes \
  --no-editor
```

Omit `--squash-before-merge` if `.umo/mr.json` sets `gitlab.squash: false`.

**Auto-fill** from commits (optional):

```bash
glab mr create --fill --squash-before-merge --yes --target-branch "{target-branch}"
```

On success, print the MR URL (`glab mr view` or the command output).

### With GitLab MCP (fallback when glab is unavailable or fails)

Resolve the GitLab project ID as described in Phase 2 ("Resolve remote and project"). Then create the MR:

```
CallMcpTool -> GitLab / create_merge_request
  id: "{gitlab-project-id}"
  title: "{MR title}"
  source_branch: "{source-branch}"
  target_branch: "{target-branch}"
  description: "{MR description}"
```

Report the MR URL to the developer on success.

### Without glab or GitLab MCP

Output the MR title and description as a copyable markdown block so the developer can create the MR manually in the GitLab UI.

## Phase 7: JIRA Update (optional, requires approval)

Only execute if a JIRA key was provided, the Atlassian MCP is available, and `.umo/mr.json` does not set `jira.enabled: false`.

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

3. **Show the developer what will be posted and which status transition is proposed.** Never update JIRA without explicit approval.

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

## Squash merge & release

Squash merge is the UMO default (`gitlab.squash: true`). When enabled, the MR title becomes the single squash commit on the target branch, so it must be a valid Conventional Commit — some repos (e.g. `saas`) read it in CI to determine a SemVer bump for changed services.

- `feat(scope): …` → **minor** bump; `fix(scope): …` / `perf(scope): …` / `revert(scope): …` → **patch** bump (where release automation is configured)
- `chore:`, `refactor:`, `test:`, `docs:`, `ci:`, `build:` → **no release** created for that merge
- Avoid `feat!` / `BREAKING CHANGE:` — most UMO repos avoid major bumps; agree with the platform/DevOps team first
- If the repo has no release automation, this section is informational only — still keep MR titles Conventional-Commit-valid for consistency and commitlint.

## MR Title Format

If the repo squash-merges (the UMO default), the MR title **is** the squash-merge commit and must follow Conventional Commits and pass **commitlint** (`subject-case`, type allow-list, max length from `.umo/mr.json` → `commit.maxSubjectLength`, default 120).

**Template:** `{type}({scope}): {lowercase imperative subject} ({JIRA-KEY})`

- **JIRA key at the end** in parentheses — e.g. `(CWN-5485)`. Do **not** put `CWN-1234` at the start of the subject; uppercase ticket keys fail `subject-case`.
- **Subject:** lowercase imperative mood (`add`, not `Add` or `added`); no trailing dot; no Capitalized words.
- **Scope:** affected area or service name(s) — e.g. `statistic`, `payment-engine`. Multi-service/multi-area: list every changed one — `fix(payment-engine,transactions-engine-web): …`
- **Without JIRA key:** omit the parentheses — e.g. `chore(exchange): deprecate nestjs implementation, preserve docs only`

**Good examples (from UMO CI / merged MRs):**

```
feat(exchange): integrate feature-script with verbose rpc logging
fix(transactions-engine): propagate child-workflow failures to parent
refactor!: rename payment-orchestrator service to payment-orchestration (CWN-5485)
chore(exchange): deprecate nestjs implementation, preserve docs only
fix(statistic): trigger patch release (CWN-6215)
```

**Common commitlint failures:**

| Rule           | Bad                                              | Good                                               |
| -------------- | ------------------------------------------------ | -------------------------------------------------- |
| `subject-case` | `fix(statistic): CWN-6215 trigger patch release` | `fix(statistic): trigger patch release (CWN-6215)` |
| `subject-case` | `feat(auth): Add user login`                     | `feat(auth): add user login`                       |
| trailing dot   | `fix(api): handle timeout.`                      | `fix(api): handle timeout`                         |
| type           | `feature(statistic): …`                          | `feat(statistic): …`                               |

Allowed types (default, overridable via `.umo/mr.json` → `commit.allowedTypes`): `feat`, `fix`, `refactor`, `chore`, `test`, `docs`, `ci`, `perf`, `build`, `revert`. Avoid `feat!` / `BREAKING CHANGE:` unless agreed with the platform/DevOps team.

## MR Description Template

Use the repo's own MR template if one exists at `.gitlab/merge_request_templates/Default.md` (or the path set in `.umo/mr.json` → `mrTemplatePath`). Otherwise fall back to this default:

```markdown
## JIRA Ticket

[{JIRA-KEY}]({jira-base-url}/browse/{JIRA-KEY})

## What this MR does?

{Auto-generated from JIRA description + commit analysis}

## Why?

{From JIRA ticket context or developer input}

## Changes Made

{Bullet list generated from git log {target-branch}..HEAD --oneline}

## How to Test

{From JIRA acceptance criteria if available, otherwise leave placeholder}

## Checklist

- [ ] Added tests
- [ ] Updated documentation
- [ ] Self-reviewed code
```

`{jira-base-url}` defaults to `https://umotech.atlassian.net`, overridable via `.umo/mr.json` → `jira.baseUrl`.

When no JIRA key is provided, omit the "JIRA Ticket" section entirely.

## Branch Naming Convention

Format: `{type}/{JIRA-KEY}-{short-description}` (or `{type}/{short-description}` without JIRA). When creating a new branch, always branch from the autodetected target/trunk branch (see Phase 2).

| Type        | When to use                |
| ----------- | -------------------------- |
| `feat/`     | New feature                |
| `fix/`      | Bug fix                    |
| `refactor/` | Code restructuring         |
| `docs/`     | Documentation              |
| `chore/`    | Maintenance, tooling       |
| `test/`     | Adding or fixing tests     |
| `ci/`       | CI/CD configuration        |
| `perf/`     | Performance improvement    |
| `build/`    | Build system, dependencies |

Derive the type from the JIRA issue type when available:

- Story / Feature -> `feat/`
- Bug -> `fix/`
- Task / Sub-task -> `feat/`
- Epic -> `feat/`

## Example Invocations

**Explicit — override to stay on the current branch, with JIRA ticket:**

```
/mr in current branch using JIRA ticket CWN-1234
```

Parsed: branch strategy = current (explicit override), JIRA key = CWN-1234, target = autodetected default branch. Commits/push/MR run immediately.

**No input — auto branch heuristic:**

```
/mr
```

On target/protected → create new branch automatically. On a feature branch with no open MR → reuse it. On a feature branch with an open MR → reuse and update. Agent autodetects the target branch and proceeds immediately (optional JIRA only if useful).

**New branch with JIRA ticket:**

```
/mr create new branch for CWN-5678
```

Parsed: branch strategy = new (explicit), JIRA key = CWN-5678, target = autodetected default branch. Agent fetches JIRA summary to derive branch name and proceeds immediately.

**No JIRA, plain request:**

```
/mr push current branch and create MR
```

Parsed: branch strategy = current (explicit override), no JIRA, target = autodetected default branch. MR description built from commits only; push and create immediately.

**No JIRA, generic request (most common case):**

```
/mr
```

or

```
create an MR for this
```

Parsed: branch strategy = auto (Phase 2 heuristic), target = autodetected default branch. Agent commits, pushes, and creates/updates the MR without preview gates.
