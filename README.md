# umo-plugins

The team marketplace bundles several plugins; **`umo-brain`** provides DAVID **organizational memory**: **Brain MCP** (`david-brain`) and the **`brain-harness`** rule. GitLab MCP is **not** part of that bundle — add it separately in Cursor if you need it.

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
```

---
