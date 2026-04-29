# umo-agentic-core

Marketplace core for UMO agentic delivery.

This plugin owns the shared lifecycle that functional, domain, language, platform,
and repo-binding plugins must compose with. It is intentionally small and
progressive-disclosure first: always-on rules define invariants, while task
skills load only when needed.

## Owns

- SDLC phases and transitions
- Planning phase semantics
- Beads as the default planning substrate
- Acceptance criteria and dependency rules
- Memory workflow
- Docs lifecycle
- Quality evidence
- Review protocol
- Closeout semantics
- Adoption modes and KPI reporting guidance
- Plugin composition validation rules

## Does Not Own

- Language-specific lint, type, test, or dependency commands
- Platform-specific browser, mobile, or infrastructure evidence
- Domain or regulatory policy
- Functional workflows such as service audit scoring
- Repo-specific paths, service names, aliases, or exceptions

## Composition Contract

Functional plugins must depend on `umo-agentic-core` and delegate lifecycle,
memory, planning, quality, review, and closeout concerns to it. In v1, there is
no separate planning plugin. Planning semantics and beads remain part of core.

See `.cursor-plugin/plugin.json` for the machine-readable ownership and
validation surfaces.

## Included

- Rules for lifecycle, planning, memory, docs, evidence, review, closeout, adoption, and composition
- Skills for memory workflow, bead planning, research/design, implementation routing, review, docs lifecycle, and repo setup
- Commands for task start, quality evidence, review, docs promotion, and exceptions

## Repo Setup

Cursor plugins do not install `AGENTS.md` or arbitrary template files as plugin
components. Use the `umo-agent-setup` skill to create or update repo-local
bindings and templates after installing the plugin.
