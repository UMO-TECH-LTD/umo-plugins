# umo-effect

Cursor / Codex / Claude Code plugin for **Effect-TS**-aware agents.

## What it ships

- **`rules/effect-awareness.mdc`** — `alwaysApply: true`. Keeps Effect orientation in context (when to load the skill, research order, local source). Does not force Effect into unrelated work.
- **`skills/effect-ts/`** — **effect-ts** skill and `references/` guides (upstream-style bundle), unchanged.

## Install

Same flow as other `umo-plugins` — add the marketplace, install **`umo-effect`**, reload.

For source checkout expectations, see `skills/effect-ts/references/setup.md` inside the skill.
