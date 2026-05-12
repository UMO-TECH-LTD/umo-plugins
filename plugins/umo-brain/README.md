# umo-brain (plugin package)

Cursor and Codex bundle for **Brain MCP** and the **`brain-harness`** rule.

## Manifests

- Cursor: `.cursor-plugin/plugin.json`
- Codex: `.codex-plugin/plugin.json`

## MCP

- Cursor: `mcp.json`
- Codex: `.mcp.json`

Both define **`david-brain`** only (Bearer `${env:BRAIN_MCP_API_KEY}`). Add other MCP servers in your user or project Cursor config if needed.

## Rules

- `rules/brain-harness.mdc` — `alwaysApply` behavior for recall, feedback, and writeback.

## Codex

1. Add this directory to your Codex marketplace (`source.path`).
2. Install/enable from the Codex UI.
