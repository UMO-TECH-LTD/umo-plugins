# umo-sdlc

UMO SDLC plugin. It standardizes documentation buckets, Beads planning,
SDLC how-to guidance, and repo health diagnostics across UMO repos.
SaaS is the reference rollout target; other repos should adopt through thin
local `AGENTS.md` steering.

The structure follows Cursor's model for customization:

- file-scoped rules stay concise;
- compact skills provide actionable workflows;
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
│   ├── docs.mdc
│   ├── how-to.mdc
│   ├── planning.mdc
│   └── sdd.mdc
└── skills/
    ├── docs/
    │   ├── SKILL.md
    │   ├── references/
    │   │   └── docs-shape.md
    │   └── assets/
    │       ├── doc-meta.template.md
    │       ├── service-catalog.template.json
    │       └── service-catalog.v1.schema.json
    ├── planning/
    │   ├── SKILL.md
    │   ├── references/
    │   │   ├── planning-lifecycle.md
    │   │   ├── beads-issue-shape.md
    │   │   └── beads-label-taxonomy.md
    │   └── assets/
    │       ├── epic.template.md
    │       ├── postmortem-followup.template.md
    │       ├── spike.template.md
    │       └── task.template.md
    └── how-to/
        ├── SKILL.md
        ├── references/
        │   ├── agents-steering.md
        │   └── repo-adoption.md
        └── assets/
            └── agents-snippet.template.md
```

## Skills

`skills/docs/SKILL.md` is the docs lifecycle skill. Its `paths` frontmatter scopes
it to docs buckets, service passports and `AGENTS.md`, service catalog
sidecars, the `umo-sdlc` plugin, and docs subagents.

It handles:

- docs setup;
- docs audit;
- doc lifecycle;
- ADR/proposal/guide/reference/incident classification;
- Markdown-first `PASSPORT.md`;
- `reference/service.catalog.json`.

`skills/planning/SKILL.md` owns the planning lifecycle inside UMO SDLC. It
turns research, accepted proposals, postmortems, and user intent into reviewed
Beads issue graphs: epics, tasks, spikes, dependencies, labels, comments,
close reasons, and execution handoffs.

`skills/how-to/SKILL.md` is the human and agent entry point for explaining
SDLC, Spec-Driven Development (SDD), and Test-Driven Development (TDD)
workflows, navigating repo knowledge, adapting a repo to
`umo-sdlc`, and running repository health diagnostics. It checks local
`AGENTS.md` steering, docs bucket readiness, Beads availability, planning
hygiene, SaaS service fact traceability, and delegates deep repairs to `docs`
or `planning`.

`rules/sdd.mdc` is the lightweight SDD router. It connects unclear intent to
durable docs, accepted docs to Beads planning, ready implementation to
test-first work, and finished work to evidence closeout without broad file
globs.

Generic memory, review, and quality evidence remain owned by
`umo-agentic-core`. `umo-sdlc` owns UMO bucket shape, doc-meta, service
passports, catalog sidecars, document type templates, planning lifecycle,
Beads planning substrate, how-to guidance, and repo adoption diagnostics.

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

Docs and Beads are agent memory and engineering control surfaces. Docs preserve
durable context and decisions; Beads turn accepted intent into structured,
reviewable, executable work.

## License

UNLICENSED. UMO internal.
