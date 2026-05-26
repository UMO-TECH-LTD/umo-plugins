<!-- doc-meta -->
> **Status:** active
> **Type:** reference
> **Owner:** UMO SDLC Team
> **Updated:** 2026-05-26

# Before / After: Task Decomposition Examples

This document shows the difference between shallow task descriptions (what agents often produce today) and the rich, spec-traceable descriptions required by the new `task` skill.

Example source: `docs/product/prds/001-user-onboarding.md`

---

## Example 1: User Onboarding Task (Regulated Domain)

### Before (Shallow — rejected)

```
Task: Implement user onboarding

Add KYC verification flow.
```

Problems:
- No link to the source PRD or specific section.
- No acceptance criteria.
- No file list or independence contract.
- No verification command.
- No traceability.

### After (Rich — required)

```
# Task: Implement KYC Document Verification Step

## Source
- Parent epic: E-15 (User Onboarding)
- Source document: `product/prds/001-user-onboarding.md#acceptance-criteria-4.1`
- Related BRD: `product/brds/001-regulated-onboarding.md#scope`
- Jira: REG-312

## Outcome
User can upload government ID and pass automated + manual KYC verification with clear status transitions and audit logging.

## Independent Unit Contract
**Files this task modifies:**
- `services/user-service/src/domain/onboarding/kyc.ts`
- `services/user-service/src/db/schema/kyc_verification.ts` (add `verified_at` column only)

**Interfaces:**
- Implements `KycVerificationPort`

**Non-overlap:**
This task does **not** touch payment instrument linking (Task T-22) or address verification (Task T-23). No file overlap with siblings.

## Wave / Parallelism
Can run in parallel with T-20 (email verification) and T-21 (phone verification).

## Acceptance Criteria
- [ ] Document upload succeeds with supported formats
- [ ] Automated OCR + face match passes for valid documents
- [ ] `verified_at` timestamp is set on manual approval
- [ ] All paths covered by unit tests + contract tests

## Verification
- `bun test services/user-service/src/domain/onboarding/__tests__/kyc.test.ts`
- `tsc --noEmit`
- Manual review of PRD section 4.1 acceptance criteria

## Docs Updates
- Update `services/user-service/docs/spec.md` (onboarding section)
```

---

## Example 2: Epic Level

### Before (Shallow)

```
Epic: Wallet Lifecycle Management

Implement the wallet lifecycle features from the PRD.
```

### After (Rich)

See the full rich epic template in `assets/epic.template.md`. It includes Source with section anchors, Independent Unit Contract, Wave Grouping, and explicit traceability to the PRD.

---

## Why This Matters

- Shallow tasks lose context between agent sessions.
- Rich tasks allow any agent (or human) to pick up the work with full understanding.
- The `task` skill now **enforces** the rich structure so that the high-quality PRDs/BRDs produced by the `product` skill are not wasted.

This reference should be loaded by the `task` skill whenever decomposition is performed.