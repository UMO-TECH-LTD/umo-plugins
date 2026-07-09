# glab CLI reference for MR creation

Extended flag reference for `glab mr create`, used as the **default/preferred** path in Phase 6 of `/mr`. GitLab MCP is the fallback when `glab` is unavailable, unauthenticated, or fails.

## Version requirement

`--squash-before-merge` requires **glab ≥ v1.103.0**.

```bash
glab version
brew upgrade glab   # macOS
```

## Authentication

```bash
glab auth login
# or, for non-interactive/CI use:
export GITLAB_TOKEN="<personal-or-project-access-token-with-api-scope>"
```

## Common flags

| Flag | Purpose |
|------|---------|
| `--target-branch <branch>` | Target/base branch for the MR (autodetected repo default branch — see `/mr` Phase 2; do not hardcode `main`) |
| `--source-branch <branch>` | Source branch (defaults to current branch if omitted) |
| `--title "<title>"` / `-t` | MR title — must be Conventional-Commit-valid if the repo squash-merges |
| `--description "<desc>"` / `-d` | MR description (markdown) |
| `--squash-before-merge` | Enforce squash merge on this MR (UMO default; omit if repo disables squash) |
| `--fill` | Populate title/description from the branch's commits |
| `--fill-commit-body` | With `--fill`, include full commit bodies in the description |
| `--yes` | Skip interactive confirmation prompts |
| `--no-editor` | Don't open `$EDITOR` for title/description — required for non-interactive use |
| `--assignee <username>` | Assign the MR to a GitLab user |
| `--label <label>` | Add a label (repeatable) |
| `-R group/subgroup/repo` | Target a repo other than the current directory's `origin` |

## Reading MRs

```bash
glab mr list --source-branch "<branch-name>"
glab mr view <iid>
glab mr view --web        # open in browser
glab mr view <iid> --web
```

## Full non-interactive example

```bash
glab mr create \
  --target-branch "{target-branch}" \
  --source-branch "$(git branch --show-current)" \
  --title "fix(payment-engine): handle nil pointer on refund (CWN-5678)" \
  --description "$(cat <<'EOF'
## JIRA Ticket
[CWN-5678](https://umotech.atlassian.net/browse/CWN-5678)

## What this MR does?
Fixes a nil pointer dereference in the refund handler.

## Why?
Crash reported in production logs when refund amount is zero.

## Changes Made
- Guard against nil transaction reference before dereferencing
- Add regression test

## How to Test
1. Trigger a refund with amount = 0
2. Confirm no panic and a graceful error response

## Checklist
- [x] Added tests
- [ ] Updated documentation
- [x] Self-reviewed code
EOF
)" \
  --squash-before-merge \
  --yes \
  --no-editor
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `401 Unauthorized` | Not authenticated, or token expired/missing scope | `glab auth login`, or refresh `GITLAB_TOKEN` with `api` scope |
| `404 project not found` | Wrong project resolved from remote, or private repo without access | Pass `-R group/subgroup/repo` explicitly; verify remote URL |
| Editor opens instead of using flags | Missing `--no-editor` or title/description not passed via flags | Always pass `-t`/`-d` (or `--title`/`--description`) with `--no-editor` |
| `--squash-before-merge: unknown flag` | glab version too old | `brew upgrade glab` to ≥ v1.103.0 |
| MR created against wrong target branch | `--target-branch` omitted, defaulted to repo's GitLab default branch | Always pass `--target-branch` explicitly |
