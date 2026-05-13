# umo-sdlc

UMO SDLC plugin. Standardizes documentation buckets, Beads planning,
SDLC how-to guidance, and repo health diagnostics. Repos adopt it through a
thin local `AGENTS.md` that points at this plugin's rules and skills.

## Layout

```text
plugins/umo-sdlc/
├── .cursor-plugin/   # Cursor manifest
├── .codex-plugin/    # Codex manifest
├── .claude-plugin/   # Claude Code manifest
├── rules/            # Cursor rules
├── skills/           # Skills (each with references/ and assets/)
├── commands/         # Claude Code slash commands
└── assets/
```
