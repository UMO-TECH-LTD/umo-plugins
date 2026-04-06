# umo-engineering-standards

Reusable engineering standards for AI-assisted development.

This plugin is intentionally self-contained. It does not depend on DAVID docs,
beads, memory tools, or any project-specific directory layout.

## Included

- Rules: `quality-loop`, `tdd-first`, `dependency-management`
- Skills: `quality-loop`, `tdd-first`, `dependency-management`
- Commands: `quality`, `commit`

## Scope

Use this plugin in TypeScript or JavaScript repositories that want:

- immediate lint and typecheck discipline after edits
- test-first implementation
- deterministic dependency upgrades with verification
- conventional commit structure

## Notes

The guidance is repo-agnostic. Commands refer to the nearest relevant package
or project root rather than any fixed service layout.
