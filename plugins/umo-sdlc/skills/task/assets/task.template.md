<!-- doc-meta -->
> **Status:** active
> **Type:** reference
> **Owner:** UMO SDLC Team
> **Updated:** 2026-05-26

# Task: <Task Outcome Title>

**Mandatory rich template.** Every task created by the `task` skill **must** use this structure. Shallow descriptions are not accepted.

## Source (Mandatory — exact section links)

- Parent epic: E-42
- Source document: `product/prds/001-wallet-lifecycle-management.md#acceptance-criteria-3.2`
- Related BRD section: `product/brds/001-regulated-onboarding.md#scope`
- Jira story: REG-312-4

## Outcome (Specific, measurable result)

<One sentence describing exactly what this task delivers.>

## Starting Context (Files, commands, constraints)

- Relevant files: `services/user-service/src/domain/onboarding/kyc.ts`
- Existing commands: `bun run db:generate`
- Constraints: Must not modify payment instrument linking logic

## Independent Unit Contract (Mandatory)

**Files this task will create or modify:**
- `services/user-service/src/domain/onboarding/kyc.ts`
- `services/user-service/src/db/schema/kyc_verification.ts` (add one column only)

**Interfaces / ports:**
- Implements `KycVerificationPort`

**Explicit non-overlap with siblings:**
This task does **not** touch payment instrument linking (Task T-22) or address verification (Task T-23). No file overlap.

## Wave / Parallelism

- Can run in parallel with: T-20, T-21
- Requires review gate after: Wave 1 complete

## Acceptance Criteria (Mapped to source spec)

- [ ] Criterion 4.1 from PRD is satisfied
- [ ] Unit test covers happy path + rejection path
- [ ] No new linter errors introduced

## Verification (Concrete evidence)

- `bun test services/user-service/src/domain/onboarding/__tests__/kyc.test.ts`
- `tsc --noEmit -p services/user-service/tsconfig.json`
- Manual review of PRD section 4.1

## Dependencies

- Blocks: T-24
- Blocked by: none
- Related: T-22 (payment linking)

## Docs Updates Required

- Update `services/user-service/docs/spec.md` (onboarding section)
- No passport changes

## Do Not Change (Explicit boundaries)

- Do not touch payment instrument tables
- Do not modify any backoffice UI code

## Human Review Evidence on Close

- Code review approved
- All acceptance criteria checked against source PRD
- Quality gates passed

---

**Do not create this task with missing sections.** The `task` skill enforces this template.