---
name: mr-review-orchestrator
description: Orchestrates a 4-persona MR review on a GitLab merge request. Fetches diff, runs code/compliance/security/standards passes, deduplicates, posts to GitLab. Entry point for reviews.
---

# MR Review Orchestrator

Coordinates a complete merge request review. Use as the main entry point.

## When to use

- "Review MR !123 in cfd-bank/saas"
- "Run a full review on this merge request"
- Any request mentioning MR review

## Input

- **Project:** GitLab project path or ID
- **MR IID:** merge request number (e.g., `!123`)

If not provided, ask the user.

## Steps

### 1. Fetch MR

Use GitLab MCP tools to get MR metadata and full diff (changed files, diff content, branches, author).

### 2. Brain recall

```
david_recall("recent review patterns for [project]")
david_recall("known false positives for [project]")
```

### 3. Run 4 persona passes

Analyze the full diff four times, each with a different focus. Load the corresponding skill for each:

1. `/mr-code-review` — logic, performance, tests, patterns
2. `/mr-compliance-audit` — VARA, ISO 27001, SOC 2
3. `/mr-security-scan` — SAST, SCA, secrets
4. `/mr-standards-guard` — ADRs, architecture, contracts

### 4. Deduplicate

- Same file+line flagged by multiple personas → keep highest severity, note all personas
- Brain recalled false positive for a pattern → suppress or mark `[SUPPRESSED]`

### 5. Post to GitLab

- **Inline discussions** on diff lines per finding
- **Summary note** with verdict table:

```markdown
## DAVID Review Summary

| Persona | Findings | Verdict |
|---------|----------|---------|
| Code Reviewer | 3 (1 high, 2 medium) | REQUEST_CHANGES |
| Compliance Auditor | 0 | APPROVE |
| Security Scanner | 1 (1 medium) | APPROVE |
| Standards Guardian | 2 (1 high, 1 low) | REQUEST_CHANGES |

**Overall: REQUEST_CHANGES**
```

### 6. Brain save

```
david_remember({
  type: "observation",
  title: "MR Review: [project] ![iid] — [verdict]",
  content: "[finding count], [key issues]",
  namespace: "code-review"
})
```
