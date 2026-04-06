# umo-brain (plugin package)

Shared plugin package for both Cursor and Codex.

## Manifests

- Cursor: `.cursor-plugin/plugin.json`
- Codex: `.codex-plugin/plugin.json`

## MCP config

- Cursor uses: `mcp.json`
- Codex uses: `.mcp.json`

Both files currently contain the same MCP server config.

## Codex integration

1. Add this plugin to your Codex marketplace file (`<repo>/.agents/plugins/marketplace.json` or `~/.agents/plugins/marketplace.json`).
2. Point `source.path` to this plugin directory.
3. Install/enable the plugin from Codex UI.
