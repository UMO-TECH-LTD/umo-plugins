<!-- doc-meta -->
> **Status:** active
> **Type:** reference
> **Owner:** UMO Platform Team
> **Updated:** 2026-05-05

# Beads Label Taxonomy

Use labels for filtering and routing. Use structured Beads fields for status,
type, and priority.

## Label Classes

Phase:

- `phase-planning`
- `phase-design`
- `phase-build`
- `phase-test`
- `phase-review`
- `phase-release`

Source:

- `source-proposal`
- `source-research`
- `source-incident`
- `source-review`
- `source-discovery`

Service/domain:

- `svc-<service>`
- `domain-<domain>`

Examples:

- `svc-auth`
- `svc-portal-frontend`
- `domain-payments`
- `domain-compliance`

Component:

- `backend`
- `frontend`
- `api`
- `database`
- `infra`
- `docs`
- `security`
- `observability`

Size:

- `small`
- `medium`
- `large`

Quality gates:

- `needs-tests`
- `needs-docs`
- `needs-review`
- `needs-security-review`
- `needs-compliance-review`

Planning state:

- `needs-decision`
- `needs-research`
- `ready-for-build`
- `blocked-external`

Agent metadata:

- `ai-generated`
- `needs-human-review`
- `auto-generated`

## Rules

- Prefer lowercase hyphenated labels.
- Keep labels stable across epics and children.
- Use labels for filtering, not prose.
- Remove quality-gate labels when the gate is satisfied.
- Do not encode priority, status, or type as labels.
- Do not invent one-off labels unless they will be queried.

## Examples

Proposal implementation epic:

```bash
bd create --title="Implement <proposal title>" --type=epic --priority=2 \
  --labels phase-planning,source-proposal,svc-<service>,frontend,backend,needs-human-review \
  --json
```

Incident follow-up:

```bash
bd create --title="Add <incident follow-up>" --type=task --priority=1 \
  --labels source-incident,domain-<domain>,observability,needs-tests,needs-docs \
  --json
```

Find ready backend work:

```bash
bd ready --json
bd list --label backend,ready-for-build --status open --json
```

