# umo-plugins

Plugin marketplace shipping plugins to **Cursor**, **Codex**, and **Claude Code**:

- **`umo-brain`** — Brain MCP (`david-brain`) plus the `brain-harness` rule / skill / SessionStart hook for persistent memory across agent sessions.
- **`umo-sdlc`** — Markdown-first docs buckets, typed document lifecycles, service passports, `service.catalog.json` sidecars, Beads planning, and SDD/TDD routing. Ships skills (`docs`, `planning`, `how-to`) and slash commands (`/sdd`, `/docs`, `/planning`, `/how-to`).
- **`umo-effect`** — **Effect-TS**: always-on **`effect-awareness`** rule plus the **`effect-ts`** skill (`skills/effect-ts/`, guides under `references/`). Load the skill when work involves Effect; the rule keeps orientation in context.
- **`umo-jira-tracker`** — Automates the daily JIRA developer workflow: syncs unresolved tickets into a local Beads database (Story-as-epic mapping), drives bead-by-bead work with AC refinement, creates GitLab MRs via `glab`/GitLab MCP using STD-JIRA naming, and syncs outcomes (MR links, transitions, new sub-tasks) back to JIRA with approval gates. Ships skills (`jira-tracker-setup`, `jira-sync`, `jira-bead-bridge`, `gitlab-mr`, `jira-sync-back`) and slash commands (`/setup`, `/sync`, `/work`, `/create`, `/commit`, `/mr`, `/close`).
- **`umo-mr`** — Org-default `/mr` command for creating GitLab merge requests in any repo, active whenever the developer or agent wants to create one: parses intent, autodetects the repo's default branch, always creates a new branch, plans conventional commits, previews, pushes, creates the MR via `glab` (preferred) or GitLab MCP (fallback), and optionally syncs JIRA. Ships trunk-based, squash-merge, commitlint-safe defaults (ported from the `saas` repo), overridable per repo via `.umo/mr.json`. Ships the `gitlab-mr` skill, the `/mr` command, and an always-on rule.
- **`umo-go`** — **Go** on the UMO platform: the **`go-coder`** agent, an always-on **`go-awareness`** rule, and the house Go skill set — `go-hex-service`, `go-service-architect`, `go-google-style`, `go-atlas-migrations`, `go-local-module-dev` (the `go.work` loop for unreleased `proto-api` / `devkit`), `go-dockerfile`, `go-quality-gates`, plus the devkit clients (`nats-events`, `featurescript-client`, `auditlog-client`, `remote-config`, `sentry-integration`, `pyroscope-integration`). Mostly vendored from the `saas` repo's Cursor skills and rules so Claude Code and Codex can load them too.

| Host | Marketplace file | Plugin manifest | MCP config |
|---|---|---|---|
| Cursor | `.cursor-plugin/marketplace.json` | `plugins/<name>/.cursor-plugin/plugin.json` | `plugins/<name>/mcp.json` |
| Codex | per-plugin (point Codex at `plugins/<name>/`) | `plugins/<name>/.codex-plugin/plugin.json` | `plugins/<name>/.mcp.json` |
| Claude Code | `.claude-plugin/marketplace.json` | `plugins/<name>/.claude-plugin/plugin.json` | inline in plugin manifest (`mcpServers`) |

## Requirements

Set `BRAIN_MCP_API_KEY` in your shell environment.

```bash
export BRAIN_MCP_API_KEY="<your key>"
```

On macOS, put the export in `~/.zshenv` so GUI launches (Cursor.app, Claude Desktop) see it. See [Cursor MCP docs](https://cursor.com/docs/context/mcp) for config interpolation details (`${env:VAR}`).

The Brain MCP endpoint is configured by the plugin.

## Install

### Cursor

1. Settings → **Plugins**.
2. Add this marketplace and install `umo-brain`, `umo-sdlc`, `umo-mr`, and/or `umo-effect`.
3. Reload the window.
4. Enable the `david-brain` MCP server under **Features → Model Context Protocol**.

### Claude Code

```bash
/plugin marketplace add <org>/<repo>
/plugin install umo-brain@umo-plugins
/plugin install umo-sdlc@umo-plugins
```

Non-interactively:

```bash
claude plugin marketplace add <org>/<repo>
claude plugin install umo-brain@umo-plugins
claude plugin install umo-sdlc@umo-plugins
```

### Codex

Point Codex at `plugins/<plugin-name>/` and install from the Codex UI.

## Verify

```bash
/plugin marketplace list
/plugin
```

In a fresh session you should see:

- The `david-brain` MCP tools available: `david_whoami`, `david_recall`, `david_feedback`, `david_remember`, `david_invalidate`.
- For `umo-sdlc`: skills `docs`, `planning`, `how-to`, and slash commands `/umo-sdlc:sdd`, `/umo-sdlc:docs`, `/umo-sdlc:planning`, `/umo-sdlc:how-to`.
- For `umo-effect`: always-on rule `effect-awareness.mdc`, skill **`effect-ts`** with guides under `skills/effect-ts/references/`.

## Validate locally

```bash
./scripts/validate-claude.sh
```

Parses every manifest, checks SKILL/command frontmatter, and runs `claude plugin validate .` if the CLI is on PATH.

## Repo layout

```text
.
├── .claude-plugin/marketplace.json
├── .cursor-plugin/marketplace.json
├── plugins/
│   ├── umo-brain/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── .cursor-plugin/plugin.json
│   │   ├── .codex-plugin/plugin.json
│   │   ├── skills/brain-harness/SKILL.md
│   │   ├── hooks/{hooks.json,session-start.sh}
│   │   ├── rules/brain-harness.mdc
│   │   ├── mcp.json
│   │   └── .mcp.json
│   ├── umo-sdlc/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── .cursor-plugin/plugin.json
│   │   ├── .codex-plugin/plugin.json
│   │   ├── skills/{docs,planning,how-to}/
│   │   ├── commands/{sdd,docs,planning,how-to}.md
│   │   └── rules/{docs,planning,how-to,sdd}.mdc
│   ├── umo-effect/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── .cursor-plugin/plugin.json
│   │   ├── .codex-plugin/plugin.json
│   │   ├── skills/effect-ts/
│   │   └── rules/effect-awareness.mdc
│   ├── umo-jira-tracker/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── .cursor-plugin/plugin.json
│   │   ├── .codex-plugin/plugin.json
│   │   ├── skills/{jira-tracker-setup,jira-sync,jira-bead-bridge,gitlab-mr,jira-sync-back}/
│   │   ├── commands/{setup,sync,work,create,commit,mr,close}.md
│   │   └── rules/jira-tracker.mdc
│   └── umo-mr/
│       ├── .claude-plugin/plugin.json
│       ├── .cursor-plugin/plugin.json
│       ├── .codex-plugin/plugin.json
│       ├── skills/gitlab-mr/{SKILL.md,references/{glab.md,mcp.md}}
│       ├── commands/mr.md
│       └── rules/umo-mr.mdc
└── scripts/validate-claude.sh
```
