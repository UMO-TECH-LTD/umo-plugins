<!-- doc-meta -->
> **Status:** active
> **Type:** reference
> **Owner:** UMO Platform Team
> **Updated:** 2026-05-05

# Repo Adoption And Health

Repos adopt `umo-sdlc` through thin local steering, not by copying plugin rules
into `AGENTS.md`.

The reference rollout target is a large multi-service monorepo with multiple
stacks, shared docs, service passports, Beads, and cross-team planning needs.

## Adoption Modes

| Mode | Meaning | Blocking |
|------|---------|----------|
| Observe | Explain guidance and report gaps without changing files unless asked. | No |
| Assist | Suggest docs/planning/Beads workflows and use templates by default. | No |
| Evidence | Require closeout evidence or explicit "not needed" rationale. | No CI blocking |
| Enforced | Block selected workflows for missing SDLC evidence after owner sign-off. | Yes |

No repo starts in enforced mode.

## Rollout Order

1. Install or update `umo-sdlc`.
2. Add root `AGENTS.md` steering.
3. Keep service `AGENTS.md` files service-specific.
4. Run a `how-to` health check in observe mode.
5. Fix safe local steering and docs bucket gaps.
6. Move to assist mode once steering is clear.
7. Move to evidence/enforced only after owner sign-off and KPI review.

## Diagnostic Checklist

Root steering:

- mentions `umo-sdlc`;
- points docs lifecycle to `docs`;
- points Beads decomposition work to `task`;
- points setup, explanation, repo navigation, adoption, and health diagnostics
  to `how-to`;
- keeps repo commands and service registry local;
- does not duplicate full plugin rules.

Service steering:

- identifies service, stack, commands, ownership, dependencies, and sharp
  edges;
- points docs / task / how-to work back to `umo-sdlc`;
- does not redefine plugin-wide Beads labels, priorities, lifecycle phases, or
  closeout rules.

Docs readiness:

- root and service docs buckets have required folders;
- managed Markdown has doc-meta;
- document types match locations;
- service passports and service catalogs are consistent where present.

Task / Beads readiness:

- Beads is initialized when the repo claims Beads usage;
- local Beads command policy is explicit;
- accepted proposals, PRDs, and postmortems can be turned into rich, traceable bead trees via the `task` skill;
- labels and closeout rules do not conflict with UMO taxonomy.

Service navigation readiness:

- root `AGENTS.md` service registry maps active services to passports;
- service `AGENTS.md` and passports agree on stack, commands, deps, and owners;
- shared config points to `docs/reference/common-config.md`;
- dependency claims can be traced to config, compose/deploy files, imports,
  proto folders, `go.mod`, or `package.json`.

## Report Shape

```markdown
## SDLC How-To Health Report

Mode: observe | assist | evidence | enforced
Repo: <name>
Scope: <root | service | plugin>

### Steering
- Pass:
- Gaps:
- Conflicts:

### Docs
- Pass:
- Gaps:

### Task / Beads
- Pass:
- Gaps:

### Product Document Governance (when applicable)
- Pass:
- Gaps:

### Service Navigation / Dependencies
- Pass:
- Gaps:

### Safe Fixes Applied
- ...

### Needs Approval
- ...

### Next Step
- ...
```
