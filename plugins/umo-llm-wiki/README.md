# umo-llm-wiki

Read-only plugin for querying the UMO process library in Confluence.

Bundles the official [Atlassian MCP](https://mcp.atlassian.com) and an
`llm-wiki-ask` skill that grounds every answer in the **LLM-MIRROR** folder
in the UMO Process Library space (`PM1`). No writes, no comments, no JIRA
mutations — pure retrieval.

---

## What's in the wiki

| Type | Pages |
|------|------:|
| Decisions (ADRs) | 102 |
| People | 39 |
| Concepts | 23 |
| Topics | 16 |
| Services | 15 |
| Teams | 6 |
| **Total** | **201** |

All pages are mirrored from the internal `llm-wiki` repo. Freshness equals
the last mirror run (see the [log page](https://umotech.atlassian.net/wiki/spaces/PM1/pages/792298725)).

---

## Install

### Claude (Claude Code / Claude Cowork)

1. Add this directory to your Claude plugin sources:
   ```
   source: ./plugins/umo-llm-wiki
   ```
2. Enable `umo-llm-wiki` from the Claude plugin manager.
3. On first use, Claude will prompt you to authenticate with Atlassian OAuth.
   Follow the browser flow — no API keys are stored in the plugin.

### Cursor

1. Add this directory to your Cursor plugin sources:
   ```json
   { "source": "plugins/umo-llm-wiki" }
   ```
2. Enable `umo-llm-wiki` in Cursor Settings → Plugins.
3. On first query, Cursor will open an Atlassian OAuth browser window.

### Codex

1. Add this directory to your Codex marketplace (`source.path`):
   ```
   plugins/umo-llm-wiki
   ```
2. Install and enable from the Codex UI.
3. Atlassian OAuth runs on first use — no credentials in config files.

---

## Try it — sample prompts

```
What does the ADR say about our database technology choice?
```

```
Who owns the payments service and which team is responsible for it?
```

```
What concepts exist around the onboarding domain?
```

The skill will read the index, fetch the most relevant pages, and return a
cited answer with Confluence URLs you can open directly.

---

## What this plugin won't do

- Create or update Confluence pages
- Leave comments (inline or footer)
- Create, edit, or transition JIRA issues
- Add worklogs to JIRA

If you ask it to do any of these, it will refuse and point you to Confluence
directly.

---

## Limits

- **Freshness**: answers reflect the last mirror run, not real-time edits.
  Check the [mirror log](https://umotech.atlassian.net/wiki/spaces/PM1/pages/792298725)
  to see when pages were last synced.
- **Scope**: only pages under the `LLM-MIRROR` folder in `PM1` are queried.
  Other Confluence spaces are not searched.
- **Authentication**: requires an active Atlassian session with read access
  to `PM1`. The plugin does not store credentials.

---

## Future

Once a dedicated `llm-wiki` MCP server is available it will replace the
bundled Atlassian MCP here. The skill, references, and manifests will remain
unchanged — only `mcp.json` / `.mcp.json` will be swapped.

---

## Manifests

| Host | File |
|------|------|
| Claude | `.claude-plugin/plugin.json` |
| Cursor | `.cursor-plugin/plugin.json` |
| Codex | `.codex-plugin/plugin.json` |

MCP config: `mcp.json` (Cursor) · `.mcp.json` (Claude/Codex)
