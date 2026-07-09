---
name: gitlab-mr
description: Lower-level reference skill for creating GitLab merge requests. Covers glab CLI (preferred/default) and GitLab MCP (fallback when glab is unavailable or fails). Used by commands/mr.md. Also usable standalone when glab is unavailable.
---

# GitLab Merge Requests via glab (preferred), GitLab MCP fallback

> **Do not call this skill directly to create an MR.**
> MR creation must always go through the `/mr` command flow (`commands/mr.md`), which handles branch setup, commit planning, full preview, and optional JIRA sync.
> This skill is invoked **only** from Phase 6 of that command — as the primary glab-based path, or as the reference for the GitLab MCP fallback call. Using it outside of that flow can produce MRs with the wrong title format or missing approval.

## Naming & squash rules (UMO defaults, trunk-based development)

These are the org-default conventions ported from the `saas` repo. Override per repo via `.umo/mr.json` (see this plugin's `README.md`).

- **Target branch:** autodetected from the repo's default branch (commonly `main`) — never `release` or other long-lived branches unless the repo's `.umo/mr.json` says otherwise. See `/mr` Phase 2 for the autodetection order.
- **MR title = squash commit** (when squash-merge is enabled, the UMO default) → must pass **commitlint** if the repo has it (blocks CI); may drive an automated SemVer release bump.
  - Format: `type(scope): lowercase imperative subject (JIRA-KEY)` — e.g. `feat(payment-engine): add webhook handler (CWN-1234)`
  - Put JIRA key in **parentheses at the end** — not `CWN-1234 add …` (uppercase prefix fails `subject-case`)
  - Subject: lowercase imperative, no trailing dot, no Capitalized words
  - Releasable (cut a tag, where release automation exists): `feat` (minor), `fix` / `perf` / `revert` (patch)
  - Non-releasable (no tag): `chore`, `refactor`, `test`, `docs`, `ci`, `build`
  - Allowed types (default): `feat, fix, refactor, chore, test, docs, ci, perf, build, revert` — max 120 chars
  - Multi-scope: `fix(payment-engine,transactions-engine-web): handle nil pointer (CWN-5678)`
- **Squash merge:** pass `--squash-before-merge` when creating the MR (default UMO behavior) so GitLab enforces a single squash commit. Omit it if `.umo/mr.json` sets `gitlab.squash: false`.

## Prerequisites

- [glab](https://gitlab.com/gitlab-org/cli) **≥ v1.103.0** installed — `glab version` to verify; `brew upgrade glab` to update. (`--squash-before-merge` was added in v1.103.0.)
- Authenticated: `glab auth login` (or `GITLAB_TOKEN` / `GITLAB_ACCESS_TOKEN` with `api` scope for non-interactive use).

## Resolve project

From the repo root:

```bash
git remote get-url origin
git remote get-url origin | sed -n 's/.*gitlab.com[:/]\(.*\)\.git/\1/p'
```

`glab` uses the current directory's Git remote by default; no `-R` needed unless operating on another project. If you need a numeric project ID for the GitLab MCP, resolve it via the MCP `search` tool (`scope: "projects"`, matching the parsed remote path) rather than hardcoding one — project IDs differ per repo and per UMO organization/group.

## Check for an existing open MR (branch)

```bash
glab mr list --source-branch "<branch-name>"
```

If one exists, show the web URL (`glab mr view <iid> --web` or paste URL from list).

## Create MR (non-interactive)

Replace title, branch, and description as needed. Target the resolved/autodetected target branch and pass `--squash-before-merge` unless squash is disabled for the repo.

```bash
glab mr create \
  --target-branch "{target-branch}" \
  --source-branch "$(git branch --show-current)" \
  --title "feat(scope): short imperative summary (CWN-1234)" \
  --description "$(cat <<'EOF'
## JIRA Ticket
[CWN-1234](https://umotech.atlassian.net/browse/CWN-1234)

## What this MR does?
...

## Why?
...

## Changes Made
- ...

## How to Test
...

## Checklist
- [ ] Added tests
- [ ] Updated documentation
- [ ] Self-reviewed code
EOF
)" \
  --squash-before-merge \
  --yes \
  --no-editor
```

Shortcuts:

- **`--fill`** — title/description from commits; use with **`--yes`** to skip prompts.
- **`--fill --fill-commit-body`** — multi-commit bodies in description.

**Avoid** `--fill` if you need a custom template; use `-t` and `-d` instead.

## After creation

```bash
glab mr view --web
# or
glab mr list --source-branch "$(git branch --show-current)"
```

## Troubleshooting

| Issue | What to try |
|-------|-------------|
| `401` / auth | `glab auth login` or set `GITLAB_TOKEN` |
| Wrong project | `glab mr create -R group/subgroup/repo ...` |
| Editor opens | Pass `-d "..."` and `--no-editor` |

## GitLab MCP equivalent (fallback)

When `glab` is not installed, not authenticated, or a call fails, fall back to the GitLab MCP:

```
CallMcpTool -> GitLab / create_merge_request
  id: "{gitlab-project-id}"
  title: "{MR title}"
  source_branch: "{source-branch}"
  target_branch: "{target-branch}"
  description: "{MR description}"
```

Resolve `{gitlab-project-id}` via the MCP `search` tool (`scope: "projects"`) if it isn't already known, and check for existing MRs first:

```
CallMcpTool -> GitLab / search
  scope: "merge_requests"
  search: "{branch-name}"
  project_id: "{gitlab-project-id}"
  state: "opened"
```

See `references/mcp.md` for the full call shapes and `references/glab.md` for extended glab flag reference.

## Relationship to `/mr` command

Order of preference for **creating** an MR:

1. **`glab mr create`** (this skill) — default/preferred.
2. GitLab MCP `create_merge_request` when `glab` is missing, unauthenticated, or errors (or when `.umo/mr.json` explicitly sets `gitlab.mrTool: "mcp"`, in which case try MCP first).
3. Manual: paste title/description into GitLab UI (last resort).

In all cases: use the resolved/autodetected target branch, squash enabled by default, MR title in Conventional Commit format with the JIRA key at the end when applicable.
