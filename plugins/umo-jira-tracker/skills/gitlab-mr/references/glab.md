# glab CLI Reference

## Install

```bash
brew install glab          # macOS
# or download from https://gitlab.com/gitlab-org/cli/-/releases
```

## Authenticate

```bash
glab auth login
# or set environment variable (non-interactive, e.g. CI):
export GITLAB_TOKEN="<your-token-with-api-scope>"
# On macOS put in ~/.zshenv so GUI apps (Cursor) see it
```

Check status:

```bash
glab auth status
```

## Resolve project

From the repo root — `glab` uses the current directory's Git remote by default; no `-R` needed unless operating on another project:

```bash
git remote get-url origin
```

Auto-resolve project ID (store in `.umo/jira-tracker.json` `gitlab.projectId` after first resolution):

```bash
REPO_NAME=$(git remote get-url origin | sed 's/.*\/\([^/]*\)\.git/\1/')
glab api "projects?search=${REPO_NAME}&membership=true" \
  | python3 -c "import json,sys; p=json.load(sys.stdin); [print(x['id'], x['path_with_namespace']) for x in p]"
```

Present the matches to the developer and ask which numeric ID is correct. Persist the choice.

## Check for an existing open MR

```bash
glab mr list --source-branch "<branch-name>"
```

If one exists, show the web URL (`glab mr view <iid> --web`).

## Create MR (non-interactive)

```bash
glab mr create \
  --target-branch "{target-branch}" \
  --source-branch "$(git branch --show-current)" \
  --title "{MR title}" \
  --description "$(cat <<'EOF'
{MR description markdown}
EOF
)" \
  --yes \
  --no-editor
```

Shortcuts:

- **`--fill`** — title/description from commits; use with **`--yes`** to skip prompts.
- **`--fill --fill-commit-body`** — multi-commit bodies in description.

**Avoid** `--fill` if you need a custom template; use `--title` and `--description` instead.

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
| Editor opens | Pass `--description "..."` and `--no-editor` |
| Can't find project | Use numeric ID via `glab api projects?search=<name>` |
