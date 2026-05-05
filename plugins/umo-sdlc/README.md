# umo-sdlc

UMO SDLC plugin. It standardizes documentation buckets across UMO repos and
steers agents to one compact `docs` skill for setup, audit, and lifecycle work.

The structure follows Cursor's model for customization:

- file-scoped rules stay concise;
- one skill provides the actionable workflow;
- detailed templates live under the skill's `references/`;
- JSON/schema/templates live under the skill's `assets/`.

See Cursor docs: [Agent Skills](https://cursor.com/docs/skills) and
[Rules](https://cursor.com/docs/rules).

## Plugin Layout

```text
plugins/umo-sdlc/
├── README.md
├── .cursor-plugin/
│   └── plugin.json
├── .codex-plugin/
│   └── plugin.json
├── assets/
│   └── umo.svg
├── rules/
│   └── docs.mdc
└── skills/
    └── docs/
        ├── SKILL.md
        ├── references/
        │   └── docs-shape.md
        └── assets/
            ├── doc-meta.template.md
            ├── service-catalog.template.json
            └── service-catalog.v1.schema.json
```

## Skill

`skills/docs/SKILL.md` is the single docs skill. Its `paths` frontmatter scopes
it to docs buckets, SaaS service passports and `AGENTS.md`, service catalog
sidecars, the `umo-sdlc` plugin, and docs subagents.

It handles:

- docs setup;
- docs audit;
- doc lifecycle;
- ADR/proposal/guide/reference/incident classification;
- Markdown-first `PASSPORT.md`;
- `reference/service.catalog.json`.

Generic docs lifecycle remains owned by `umo-agentic-core`; `umo-sdlc` owns the
UMO bucket shape, doc-meta, service passports, catalog sidecars, and document
type templates.

## Core Model

- Service bucket: `services/<svc>/docs/`
- Library bucket: `docs/`
- Managed service passport: `services/<svc>/docs/PASSPORT.md`
- Machine catalog: `services/<svc>/docs/reference/service.catalog.json`

Some repos still have legacy root passports at `services/<svc>/PASSPORT.md`.
Treat them as migration sources; do not strip YAML frontmatter or rewrite them
unless the task is an explicit service docs migration.

Proposal state:

- `draft`
- `accepted`
- `rejected`
- `implemented`
- `archived`

Do not use `decided` as status. `Decided:` can be metadata.

## Agentic SDLC Goal

Docs are agent memory and engineering control surfaces. They should help
engineers and agents move from intent to structured, reviewable, executable
work.

## License

UNLICENSED. UMO internal.
