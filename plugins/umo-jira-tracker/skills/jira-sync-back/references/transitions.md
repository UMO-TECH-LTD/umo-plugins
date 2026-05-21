# JIRA Transition Reference — umotech.atlassian.net

Cached transition IDs for known projects on `cloudId: b347643a-d5fa-4f1c-ba69-4901fdb8717d`.

**How to use:** Look up the transition ID from the table below for the target project and current status, then call `transitionJiraIssue` directly without calling `getTransitionsForJiraIssue` first.

**Fallback:** If the project or current status is not listed here, or if `transitionJiraIssue` returns a 400/404, fall back to `getTransitionsForJiraIssue` and update this file with any new findings.

**Staleness:** Transitions change rarely (board reconfiguration). Re-verify if a previously working transition ID fails.

---

## CWN — Crypto Wallet New

Workflow type: **custom dev workflow** with a QA lane.

### Status map (status name → status ID)

| Status name | Status ID | Category |
|-------------|-----------|----------|
| New | 1 | To Do |
| To do | 10000 | To Do |
| Ready for development | 10270 | To Do |
| In Progress | 3 | In Progress |
| Code Review | 10342 | In Progress |
| Ready for Testing | 10344 | In Progress |
| In Testing | 10345 | In Progress |
| Tested | 10346 | In Progress |
| Testing Blocked | 10351 | In Progress |
| Blocked | 10010 | In Progress |
| ON HOLD | 10004 | In Progress |
| Closed | 6 | Done |
| Reopened | 4 | To Do |

### Transitions

| Transition name | Transition ID | From status(es) | To status |
|----------------|---------------|-----------------|-----------|
| Move To Do | 9 | any (global) | To do |
| Start progress | 11 | To do, New | In Progress |
| To Review | 21 | In Progress | Code Review |
| Ready for Testing | 191 | In Progress | Ready for Testing |
| Ready for Testing | 161 | Code Review | Ready for Testing |
| Start testing | 51 | Ready for Testing | In Testing |
| Tested | 201 | Ready for Testing / In Testing | Tested |
| Reopen | 121 | Ready for Testing | Reopened |
| Testing Blocked | 171 | Ready for Testing | Testing Blocked |
| Blocked | 81 | any (global) | Blocked |
| ON HOLD | 91 | any (global) | ON HOLD |
| Closed | 111 | any (global, needs screen) | Closed |

### Common agent use-cases

| Intent | Transition name | ID |
|--------|----------------|-----|
| Start working on ticket | Start progress | **11** |
| Submit MR for review | To Review | **21** |
| Mark ready for QA | Ready for Testing (from Code Review) | **161** |
| Mark done / close | Closed | **111** _(screen required — include `resolution`)_ |
| Revert to backlog | Move To Do | **9** |

### Multi-step workarounds

> **Code Review → In Progress:** No direct transition exists.
> Workaround: `Move To Do` (id 9) → `Start progress` (id 11).
> Two separate `transitionJiraIssue` calls required.

**Agent shortcut:** When the developer runs `/umo-jira-tracker:work` on a CWN ticket in **Code Review**, offer this sequence automatically via `jira-sync-back` Operation B-multi before claiming the bead.

---

## FFR — Frogfort LT RSD
## CFR — Coreblocks LT RSD

Both FFR and CFR share the same simplified Jira Software workflow.

### Status map

| Status name | Status ID | Category |
|-------------|-----------|----------|
| Backlog | 10002 | To Do |
| Selected for Development | 10003 | To Do |
| In Progress | 3 | In Progress |
| Support & Review | 10006 | In Progress |
| ON HOLD | 10004 | In Progress |
| Done | 10001 | Done |

### Transitions

| Transition name | Transition ID | Notes |
|----------------|---------------|-------|
| Backlog | 11 | global — move to Backlog |
| Selected for Development | 21 | global |
| In Progress | 31 | global |
| Done | 41 | global |
| ON HOLD | 51 | global |
| REVIEW | 71 | global — moves to Support & Review |

### Common agent use-cases

| Intent | Transition name | ID |
|--------|----------------|-----|
| Start working | In Progress | **31** |
| Mark done | Done | **41** |

---

## CWN — "New" status issues (Epic / legacy workflow)

Some older CWN Epics use the classic Jira workflow (status `New`, id 1).

### Transitions available from `New`

| Transition name | ID | To status |
|----------------|-----|-----------|
| Start Progress | 4 | In Progress |
| Resolve Issue | 5 | Resolved _(screen required)_ |
| Close Issue | 2 | Closed _(screen required)_ |

---

## Agent decision tree for Operation B

```
1. Look up project key in this file.
2. If found: use cached transition ID directly.
3. If not found OR transition returns error:
   a. Call getTransitionsForJiraIssue.
   b. Find transition by name (case-insensitive partial match).
   c. If still no match: show available transitions to developer and ask.
   d. Update this file with newly discovered transitions.
4. When config value (e.g. transitionOnMr = "In Review") does not
   match any known transition name, try partial match:
   - "in review" matches "To Review" (CWN) and "REVIEW" (FFR/CFR).
   - "done" matches "Done" (FFR/CFR), "Closed" (CWN).
   Always confirm with developer before using a fuzzy match.
```

---

_Last updated: 2026-05-21 by automated sync from umotech.atlassian.net_
_Sampled issues: CWN-5449 (To do), CWN-5449 (In Progress), CWN-4790 (Code Review), CWN-4200 (Ready for Testing), CFR-19 (Backlog), FFR-92 (In Progress), CWN-257 (New/legacy)_
