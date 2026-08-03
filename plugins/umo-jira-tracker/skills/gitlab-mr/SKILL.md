---
name: gitlab-mr
description: Lower-level reference skill for creating GitLab merge requests. Covers glab CLI (preferred) and GitLab MCP (when available). Used by commands/mr.md. Also usable standalone when MCP is unavailable or fails.
---

# GitLab Merge Requests via glab (MCP fallback)

> **Do not call this skill directly to create an MR.**
> MR creation must always go through the `/umo-jira-tracker:mr` command flow (`commands/umo-jira-tracker:mr.md`), which handles branch setup, commit planning, full preview, assignee, description template, and JIRA sync.
> This skill is invoked **only** from Phase 6 of that command as the glab fallback when GitLab MCP is unavailable. Using it outside of that flow produces MRs with wrong title format, missing assignee, and no JIRA update.

Use when the GitLab MCP is unavailable or fails, and the `/umo-jira-tracker:mr` command flow has already reached Phase 6. Also used by `/umo-jira-tracker:mr` as the **preferred CLI fallback** after MCP.

## Naming standard

- **Branch:** `{type}/{JIRA-KEY}-{short-description}` — type one of `feat`, `fix`, `hotfix`, `chore`, `refactor`, `test`, `docs`, `ci`, `perf`, `build`; short-description 2–5 words kebab-case. e.g. `feat/PAY-1234-add-kafka-retry`
- **MR title:** `{type}(scope): lowercase imperative subject (JIRA-KEY)` e.g. `feat(publisher): add kafka retry (PAY-1234)` — Conventional Commits with the JIRA key in parentheses at the **end**, which keeps the title commitlint-safe.
- **Commit:** `type(scope): description` (Conventional Commits); include the JIRA key in the footer or the branch name.

**The JIRA key is mandatory.** No MR merges without a JIRA Task, the merge commit references it, a CI check fails a title that lacks it, and the merged-PR automation reads it to flip the Task to Done. Never construct a keyless branch or title here.

## Prerequisites

- [glab](https://gitlab.com/gitlab-org/cli) installed (`glab version`).
- Authenticated: `glab auth login` (or `GITLAB_TOKEN` / `GITLAB_ACCESS_TOKEN` with `api` scope).

See `references/glab.md` for install, auth, and troubleshooting details.
See `references/mcp.md` for GitLab MCP setup and `create_merge_request` usage.

## Resolve project

From the repo root:

```bash
git remote get-url origin
```

`glab` uses the current directory's Git remote by default. For a different project use `-R group/subgroup/repo`.

**Auto-resolve project ID** (store in `.umo/jira-tracker.json` after first resolution):

```bash
REPO_NAME=$(git remote get-url origin | sed 's/.*\/\([^/]*\)\.git/\1/')
glab api "projects?search=${REPO_NAME}&membership=true" \
  | python3 -c "import json,sys; p=json.load(sys.stdin); [print(x['id'], x['path_with_namespace']) for x in p]"
```

Present matches to the developer. Persist confirmed ID to `gitlab.projectId` in `.umo/jira-tracker.json` so future runs skip resolution.

## Check for an existing open MR (branch)

```bash
glab mr list --source-branch "<branch-name>"
```

If one exists, show the web URL (`glab mr view <iid> --web` or paste URL from list).

## Create MR (non-interactive)

Replace title, branch, and description as needed. Always include `--assignee` using `user.gitlabUsername` from `.umo/jira-tracker.json` — GitLab does **not** auto-assign the MR author as the assignee.

```bash
glab mr create \
  --target-branch {target-branch} \
  --source-branch "$(git branch --show-current)" \
  --title "{type}(scope): lowercase imperative subject ({JIRA-KEY})" \
  --assignee {user.gitlabUsername} \
  --description "$(cat <<'EOF'
## JIRA Task
[{JIRA-KEY}](https://umotech.atlassian.net/browse/{JIRA-KEY})

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
  --yes \
  --no-editor
```

Shortcuts:

- **`--fill`** — title/description from commits; sets `--push` behavior; use with **`--yes`** to skip prompts.
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
| Can't find project | Use `glab api "projects?search=<name>&membership=true"` |
| MR has no assignee | Re-assign with `glab mr update <iid> --assignee <gitlabUsername>`; add `--assignee` to the create command next time |

## Relationship to `/umo-jira-tracker:mr`

Order of preference for **creating** an MR:

1. GitLab MCP `create_merge_request` when configured and working (see `references/mcp.md`).
2. **`glab mr create`** (this skill) when MCP is missing or errors.
3. Manual: paste title/description into GitLab UI (last resort).
