# umo-plugins

Tri-platform plugin marketplace shipping two UMO plugins to **Cursor**, **Codex**, and **Claude Code** (Claude Desktop / CLI / Claude.ai for Teams):

- **`umo-brain`** — DAVID **organizational memory**: **Brain MCP** (`david-brain`) plus the **`brain-harness`** rule / skill / SessionStart hook.
- **`umo-sdlc`** — Markdown-first docs buckets, typed document lifecycles, service passports, `service.catalog.json` sidecars, Beads planning, SDD/TDD routing, and repo health diagnostics. Skills (`docs`, `planning`, `how-to`) plus slash commands (`/sdd`, `/docs`, `/planning`, `/how-to`).

GitLab MCP is **not** bundled — add it separately in your host if you need it.

| Host | Marketplace file | Plugin manifest | MCP file |
|---|---|---|---|
| **Cursor** | `.cursor-plugin/marketplace.json` | `plugins/<n>/.cursor-plugin/plugin.json` | `plugins/<n>/mcp.json` |
| **Codex** | per-plugin (point Codex at `plugins/<n>/`) | `plugins/<n>/.codex-plugin/plugin.json` | `plugins/<n>/.mcp.json` |
| **Claude Code** | `.claude-plugin/marketplace.json` | `plugins/<n>/.claude-plugin/plugin.json` | inline in plugin manifest (`mcpServers`) |

**Everything below is the full developer guide** (one place).

---

## What this plugin does

| | |
|--|--|
| **Rules** | `brain-harness` (`alwaysApply` — trigger-based recall, mandatory feedback, capability-aware writeback) |
| **MCP** | `david-brain` in bundled `mcp.json` / `.mcp.json` |

The **`brain-harness`** rule applies in **any** repo once **umo-brain** is installed — no per-project `.cursor` needed.

---

## How brain-harness works

The bundled `brain-harness` rule is designed to keep agent attention on DAVID brain without bloating the prompt:

- **Session start:** `david_whoami` (role, allowed tools, session mode, distill readiness) then `david_recall` then `david_feedback` on every returned memory
- **Three MCP surfaces:** **tools** for dynamic actions, **prompts** (`brain.start-task`, `brain.capture-learning`, etc.) for packaged workflows, **resources** (`brain://reference/*`) for stable policy markdown — see rule for full tables
- **Parameters:** `memory_scope` (tier filter on recall) vs `memory_space` (four-tier: self / knowledge / episodic / operational) vs `domain_scope` on remember — deprecated `scope` alias with conflict detection
- **During work:** recall again only at high-value triggers (unfamiliar code, design choices, repeated failure)
- **Structured recall output:** markdown + fenced JSON block with ids, scores, types, spaces for programmatic follow-up
- **After every recall:** `david_feedback` on returned memories; operational memories **promote** to knowledge after 3 cumulative helpful rows (server-side)
- **Writeback:** `david_remember` (11 types incl. `observation`/`tension`) only for durable learnings; write-time **quality gate** rejects too-short titles/content; namespace default to `global` returns a warning; handle permission failures explicitly
- **Session mode:** agent JWTs carry a risk budget (`autonomous`/`supervised`/`propose`/`unrestricted`); `david_whoami` exposes the effective mode
- **Consolidation (admin):** `david_consolidate` deduplicates within same namespace and `memory_space`

It is intentionally **tool-first** and **just-in-time**. Brain is treated as long-term memory, not as a scratchpad or a giant prompt dump.

---

## 1. Install

1. Open **Cursor**
2. **Settings** → **Plugins** (or **Marketplace** / **Plugins** in the sidebar)
3. Find **umo-brain** (or your team's marketplace bundle, e.g. **umo-plugins**)
4. **Install** / enable → **Developer: Reload Window** or restart Cursor  

If it's not listed, ask your team how the plugin is shipped.

---

## 2. API keys

You need **`BRAIN_MCP_API_KEY`**. Never commit it — env vars or Cursor Secrets.

### Brain — `BRAIN_MCP_API_KEY`

1. **[https://david.umo.dev/](https://david.umo.dev/)** → sign in  
2. **Settings → API Keys** → create a key  
3. Copy once → set **`BRAIN_MCP_API_KEY`** where Cursor reads env (see [macOS](#macos-api-keys-for-cursor))  

Brain MCP URL (bundled): **`https://mcp.umo.dev/mcp`** (VPN if your org requires it).

### Optional: GitLab elsewhere in Cursor

If you use GitLab from agents, configure a GitLab MCP (for example `@zereight/mcp-gitlab`) under **Cursor → MCP** — not in `plugins/umo-brain/mcp.json`.

---

## 3. Turn MCP on

**Features** → **Model Context Protocol** — enable **`david-brain`** (and any GitLab MCP you added separately).

---

## macOS: API keys for Cursor

This plugin's `mcp.json` uses **`${env:VAR}`** for secrets. Cursor expands that from the environment — see [MCP](https://cursor.com/docs/context/mcp) and [Config interpolation](https://cursor.com/docs/context/mcp#config-interpolation).

| Variable | Role |
|----------|------|
| `BRAIN_MCP_API_KEY` | Bearer for **david-brain** |

**Why `~/.zshenv`:** **Cursor.app** does not load **`~/.zshrc`** for GUI launches. **`~/.zshenv`** is loaded for zsh and is the supported place to define exports so **`${env:BRAIN_MCP_API_KEY}`** is not empty.

1. Add the value from [§2](#2-api-keys) to **`~/.zshenv`** (create the file if it does not exist):

   ```bash
   export BRAIN_MCP_API_KEY="…"
   ```

2. **Quit Cursor completely** and open it again (or **Command Palette** → `MCP: Restart All MCP Servers`).
3. **View → Output → channel MCP** — confirm **david-brain** starts without errors.

### Other setups (Remote SSH, Linux, Windows, cloud agents, …)

We only document **macOS + `~/.zshenv`** above. For anything else, use **Cursor's documentation** — start here:

- **[Model Context Protocol (MCP)](https://cursor.com/docs/context/mcp)** — configuration, tools, troubleshooting  
- **[Config interpolation](https://cursor.com/docs/context/mcp#config-interpolation)** — `${env:VAR}` and how Cursor resolves it  

---

## Environment variables (reference)

```bash
BRAIN_MCP_API_KEY=<david.umo.dev → Settings → API Keys>
GITHUB_TOKEN=<optional: needed for Claude Code background auto-updates from this private repo>
```

---

## Claude Code (Desktop, CLI, Claude.ai for Teams)

This repo is also a [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces). It's the same content as the Cursor marketplace, exposed through Claude Code's plugin format.

### What ships to Claude Code

| Plugin | Components |
|---|---|
| `umo-brain` | `david-brain` HTTP MCP (`https://mcp.umo.dev/mcp`, bearer `${BRAIN_MCP_API_KEY}`) + `brain-harness` skill + SessionStart hook that nudges the agent into the recall/feedback/writeback workflow at every session start |
| `umo-sdlc` | Skills: `docs`, `planning`, `how-to`. Slash commands: `/umo-sdlc:sdd`, `/umo-sdlc:docs`, `/umo-sdlc:planning`, `/umo-sdlc:how-to` |

The Cursor `rules/*.mdc` files are **Cursor-only**; in Claude Code the rule content is delivered through the matching skill or slash command. The `brain-harness` rule's `alwaysApply: true` semantics are replicated by combining a model-invokable skill with a `SessionStart` hook.

### 1. Install Claude Code

[code.claude.com](https://code.claude.com) — Desktop and CLI distributions. Corporate Claude Teams accounts work the same as personal; marketplaces sync to Claude.ai's plugin surface.

### 2. Set the API key (and optionally `GITHUB_TOKEN`)

```bash
export BRAIN_MCP_API_KEY="<from david.umo.dev → Settings → API Keys>"

# Optional but recommended for private-repo background auto-updates:
export GITHUB_TOKEN="<PAT with read:repo on this mirror>"
```

Put these in `~/.zshenv` on macOS (same reason as for Cursor — GUI launches don't load `~/.zshrc`), or in your shell rc on Linux. The Claude Code MCP block uses standard `${BRAIN_MCP_API_KEY}` interpolation.

### 3. Add the marketplace

Pick one of these — they correspond to the choices in the team marketplace incident postmortem (`docs/incidents/2026-05-12-team-marketplace-private-plugin-load-failure.md`).

**Option A — private GitHub mirror (default, requires per-developer git auth):**

```bash
# In an interactive Claude Code session
/plugin marketplace add <org>/<repo>
/plugin install umo-brain@umo-plugins
/plugin install umo-sdlc@umo-plugins

# Or non-interactively
claude plugin marketplace add <org>/<repo>
claude plugin install umo-brain@umo-plugins
claude plugin install umo-sdlc@umo-plugins
```

This is the **same root cause class** as the Cursor team marketplace incident: Claude Code uses `git clone` under the hood. Developers without GitHub credentials on the laptop will fail with `fatal: could not read Username for 'https://github.com'`. Mitigations:

- `gh auth login` or a `git-credential-*` helper for interactive use.
- `GITHUB_TOKEN` (or `GH_TOKEN`) in the environment for **background auto-updates** — Claude Code can't prompt at startup, so without a token, background updates silently fail.
- For airgapped or locked-down environments, use Option B below.

**Option B — internal git host (no GitHub dependency):**

```bash
/plugin marketplace add https://gitlab.<your-org>.com/platform/umo-plugins.git
```

Works the same as Option A, but auth flows through whatever helper your laptops already use for the internal git server (typically org SSO).

**Option C — pre-seeded container image (no per-developer git auth):**

For corporate Claude Teams rolling Claude Code through a managed image, pre-populate the plugins cache at build time:

```bash
# Build-time, inside the corporate image:
CLAUDE_CODE_PLUGIN_CACHE_DIR=/opt/claude-seed \
  claude plugin marketplace add <org>/<repo>
CLAUDE_CODE_PLUGIN_CACHE_DIR=/opt/claude-seed \
  claude plugin install umo-brain@umo-plugins
CLAUDE_CODE_PLUGIN_CACHE_DIR=/opt/claude-seed \
  claude plugin install umo-sdlc@umo-plugins

# Runtime, in the image's user environment:
export CLAUDE_CODE_PLUGIN_SEED_DIR=/opt/claude-seed
```

Claude Code reads from the seed without re-cloning. `git pull` never runs on the user's laptop, so the private-GitHub failure class is eliminated. Note: seed-managed marketplaces are read-only; auto-updates are disabled.

For a deeper treatment of the trade-offs (Cursor and Claude both apply), read the postmortem: [`docs/incidents/2026-05-12-team-marketplace-private-plugin-load-failure.md`](./docs/incidents/2026-05-12-team-marketplace-private-plugin-load-failure.md).

### 4. Pre-trust the marketplace for your team (optional)

Add the marketplace to managed settings so team members are prompted automatically when they trust the project folder. Put this in `~/.claude/settings.json` (user scope) or `.claude/settings.json` (project scope, committed to your repo):

```json
{
  "extraKnownMarketplaces": {
    "umo-plugins": {
      "source": {
        "source": "github",
        "repo": "<org>/<repo>"
      }
    }
  },
  "enabledPlugins": {
    "umo-brain@umo-plugins": true,
    "umo-sdlc@umo-plugins": true
  }
}
```

For corporate lockdown, your platform team can also set [`strictKnownMarketplaces`](https://code.claude.com/docs/en/settings#strictknownmarketplaces) in managed settings to whitelist only this marketplace.

### 5. Verify

```bash
/plugin marketplace list
/plugin            # opens the plugin picker — confirm umo-brain and umo-sdlc are installed and enabled
```

In a fresh session you should:

1. See the `umo-brain` SessionStart message (one-line brain workflow reminder).
2. See `david_whoami`, `david_recall`, `david_feedback`, `david_remember`, `david_invalidate` available as tools from the `david-brain` MCP server.
3. Have `/umo-sdlc:sdd`, `/umo-sdlc:docs`, `/umo-sdlc:planning`, `/umo-sdlc:how-to` available as slash commands.
4. Be able to ask "use the brain-harness skill" and have Claude load it; skills `docs`, `planning`, `how-to` are auto-invokable by description for relevant tasks.

### 6. Validate locally before publishing

```bash
./scripts/validate-claude.sh
```

This parses every manifest, checks SKILL/command frontmatter, and runs `claude plugin validate .` if the CLI is on PATH. Run it before pushing changes to the marketplace branch — Claude Code refuses to load plugins with malformed `plugin.json` or `hooks.json`.

---

## Repo layout

```text
cursor-umo-brain/
├── .claude-plugin/marketplace.json       ← Claude Code marketplace catalog
├── .cursor-plugin/marketplace.json       ← Cursor team marketplace catalog
├── plugins/
│   ├── umo-brain/
│   │   ├── .claude-plugin/plugin.json    ← Claude (inline mcpServers + skills + hooks)
│   │   ├── .cursor-plugin/plugin.json    ← Cursor
│   │   ├── .codex-plugin/plugin.json     ← Codex
│   │   ├── skills/brain-harness/SKILL.md ← Claude skill
│   │   ├── hooks/{hooks.json,session-start.sh}  ← Claude SessionStart nudge
│   │   ├── rules/brain-harness.mdc       ← Cursor alwaysApply rule
│   │   ├── mcp.json / .mcp.json          ← Cursor / Codex MCP configs
│   │   └── assets/
│   └── umo-sdlc/
│       ├── .claude-plugin/plugin.json    ← Claude (skills + commands)
│       ├── .cursor-plugin/plugin.json    ← Cursor
│       ├── .codex-plugin/plugin.json     ← Codex
│       ├── skills/{docs,planning,how-to}/  ← Shared by Cursor + Codex + Claude
│       ├── commands/{sdd,docs,planning,how-to}.md  ← Claude slash commands
│       ├── rules/{docs,planning,how-to,sdd}.mdc    ← Cursor rules
│       └── assets/
└── scripts/
    └── validate-claude.sh
```

---

