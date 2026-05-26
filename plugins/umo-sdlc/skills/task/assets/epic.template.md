<!-- doc-meta -->
> **Status:** active
> **Type:** reference
> **Owner:** UMO SDLC Team
> **Updated:** 2026-05-26

# Epic: <Outcome Title>

**Mandatory rich template.** Every epic created by the `task` skill **must** use this structure. Do not create an epic with a shallow description.

## Source (Mandatory — with section anchors)

- Primary document: `product/prds/001-user-onboarding.md`
- Key sections: `#goals`, `#acceptance-criteria`, `#scope`
- Related BRD: `product/brds/001-regulated-onboarding.md`
- Related ADR: `adr/0007-kyc-provider-selection.md`
- Jira: REG-312

## Outcome (One paragraph — business or engineering result)

<Clear statement of the measurable result this epic delivers.>

## Scope (Included work)

- <bullet list of what is in scope>

## Non-goals (Explicitly excluded)

- <bullet list of what is out of scope for this epic>

## Independent Unit Contract (Mandatory)

**Files this epic owns / will create or modify:**
- `services/user-service/src/domain/onboarding/...`
- `services/user-service/src/api/onboarding/...`

**Interfaces / ports this epic defines or consumes:**
- `OnboardingPort`, `KycProviderPort`

**Explicit non-overlap statement:**
This epic does not touch payment instrument linking logic (owned by a separate epic) or backoffice UI surfaces.

## Child Tasks (with wave grouping)

### Wave 1 (Independent — can start immediately)

- T-101: ...
- T-102: ...

### Wave 2 (Depends on Wave 1 output or review gate)

- T-103: ...

## Acceptance Criteria (Observable completion conditions)

- <criterion mapped to source PRD section>

## Risks and Open Decisions

- <risk or human decision point>

## Suggested Execution

- First ready work: `bd ready` after dependencies are set
- Parallelizable groups: see Wave 1 above
- Fresh-session handoff: yes — each child task description contains full context and spec links

## Verification / Evidence on Close

- All child tasks closed with evidence
- Quality gates passed on changed services
- Docs updated (passport, catalog, spec if needed)
- Source PRD/BRD traceability preserved in every task description

---

**Do not delete or shorten this template.** Agents must populate every section with real references.