# UMO work-tracking model — the encoding this plugin obeys

This file restates, for agent use, the parts of the org's canonical work-tracking
document that this plugin must not contradict. The binding source is
`engineering/way-of-working/how-we-track-work.md` in the `sdlc-control-plane`
meta-repo. **Where this file and that document disagree, that document wins** —
report the drift rather than following this copy.

Every other file in this plugin links here instead of restating the model.

---

## 1. Five issue types — nothing else

| Type | Level | Created by | What it is |
|---|---|---|---|
| **Flow** | 2 — above the epic | flow PM | one per flow; the unit of value and cost |
| **Slice** | 1 — the (renamed) epic | flow PM | the unit of handover |
| **Task** | 0 | flow TL with the team | engineering-internal unit, ideal 1–2 days |
| **Request** | 0 | requesting PM or TL | the way to ask another team for work; lives in the **provider's** project |
| **Bug** | 0 | anyone | defect against something deployed |

**Types that do not exist.** If a developer or an agent asks for one of these,
refuse and explain:

| Asked for | Answer |
|---|---|
| **Story** | Does not exist. Dev work is a **Task**, full stop. Two level-0 work types would split the counts velocity is calibrated on. |
| **Sub-task** | Does not exist. Private breakdown is checkboxes in the description, or beads in git. |
| **Epic** | The word is not used. The epic *slot* is occupied by **Slice**. |
| **Use-Case** | A writing format, not a ticket. |

This depends on **Jira Premium**: Flow is a custom hierarchy level above the
epic, which Standard cannot express. Level-0 children of a Slice are standard
issues — rankable and countable, with no sub-task tax.

## 2. Fields

**Custom fields: none.** The parent chain carries flow and slice membership.

| Field | Use |
|---|---|
| **Parent** | the one structural edge: Task/Bug → Slice · Slice → Flow · Request → the **consumer's** Slice (cross-project) |
| **Due date** | on **Requests**: the `needed-by`, doubling as mock expiry once the contract is agreed. Optional on Slices/Flows. **Meaningless on Tasks — never set it** |
| **Components** | on provider projects: the capability register |
| **Rank** | board order; engineers pull from the top |
| **Status** | per-type workflows (§4) |
| **Summary** | carries the naming grammar (§6) |
| **Linked issues** | **one link type only: `Blocks`** |

**Explicitly unused — never read, never write:**

- **Sprint** (`customfield_10020`, `sprint in openSprints()`, sprint labels).
  Heartbeats do not open and close containers; tasks stay open until merge-ready.
- **Story points.**
- **Original estimate / time tracking.** Cost is time-in-status — measured, not
  estimated.
- **Epic Link** (`customfield_10014`). The native `fields.parent` is the only
  structural edge.

## 3. Hierarchy

```
FLOW (level 2, in the owning team's project)
  └── SLICE (epic slot)
        ├── TASK      (child)
        ├── BUG       (child)
        └── REQUEST   (in the PROVIDER's project, parented cross-project
                       to this slice + Blocks-links to the tasks it gates)
```

**The parent chain is the single source of truth.** An issue belongs to the flow
its parent chain reaches. No field to fill, no field to drift.

Useful queries:

| Intent | JQL |
|---|---|
| Flow view / cost ledger | `issuekey in portfolioChildIssuesOf("<FLOW-key>")` |
| What is still fake | `parent = <slice> AND type = Request AND status not in (Closed, Retired)` |

An issue created below Flow level with no parent is an **orphan** and trips the
org's orphan detector. This plugin never creates one silently.

## 4. Workflows

| Type | States |
|---|---|
| **Task** | `To Do → In Progress → Done` |
| **Slice** | `Draft → Ready for development → In Progress → Done` |
| **Flow** | `To Do → In Progress → Done` |
| **Request** | `Open → Accepted → Mock Available → Delivered → Done` |

Plus **`Retired`** as a global terminal on every type.

**The Request terminal means something stronger than the others.** Reaching it is
*consumer proof*: the mock is retired and the consumer's tests are green against
the real thing — not merely that the provider shipped. That is why only the
consumer may declare it, and why this plugin never transitions a Request.

> Canon names that terminal **`Closed`**, treating the word as load-bearing.
> **Verified against live Jira on 2026-08-03:** the configured status is `Done`,
> and no `Closed` status exists in the Request workflow. The intent is the same
> under either name and nothing in this plugin depends on it. Flagged for the doc
> owners; not decided here.

Match terminals by **`statusCategory`**, never by the literal word.

**Retired** means the same thing on every type: withdrawn from play without being
completed. Rules:

- **Resolution is mandatory** — `Won't Do` / `Duplicate` / `Superseded` /
  `Cannot Reproduce`. The waste bin always says why.
- Retired is **excluded from every count**. Velocity counts Done only.
- Only the **consumer** retires a Request, and it needs a reason plus a successor
  link.

**Task Done = PR merged and all existing tests green.** Org automation flips the
Task to Done when the MR merges — this plugin must not race it (see §6).

## 5. What this plugin creates, and what it does not

The 01.08 ruling draws the boundary:

> the step-by-step execution plan an agent follows *inside* one task is an
> engineering artifact and lives in git (beads or otherwise). It is **not** synced
> to Jira; no bridge is built. Anything that is a **unit of assignment or
> delivery** — someone works on it for a meaningful stretch, or QA/PM/EM/CTO/CISO
> needs to see its status — exists in Jira as a **Task under the slice**.

So the sync is deliberately asymmetric:

| Direction | Types |
|---|---|
| **Pull** (Jira → beads) | all five |
| **Push** (beads → Jira) | **Task and Bug only**, under an existing Slice |

The plugin **never mints a Flow, a Slice, or a Request.** Those carry demo
statements, contracts, mock owners and due dates that a coding agent is not in a
position to author. Below the Task line, decompose freely in beads and leave it
in git.

## 6. Naming and the merge gate

- **Prefix everything** with the slice coordinate: `[IC]` for a flow, `[IC-S2]`
  for a slice, task, request or bug. Dash, never slash — names stay safe if they
  appear in file names.
- **Title grammar:** Slice is the "after this we can …" sentence · Request is the
  outcome verbatim · **Task is an imperative verb phrase** · **Bug is the symptom,
  not the diagnosis**.
- **Banned in titles:** layer names, person names, status words, "part 2 / misc /
  fixes".
- **The Jira key goes in every branch and MR title** — CI-enforced, and the
  merged-PR automation depends on it.
- **No MR merges without a Jira Task, and the merge commit references the task.**
  This backstop is what makes the promotion rule automatic: a decomposed bead
  that ends in a merge has a Jira Task by definition.

## 7. Squad projects

| Key | Project |
|---|---|
| PLAT | Platform |
| DATA | Data |
| AI | AI |
| EXP | Experience *(squad: Customer Experience)* |
| CRY | Crypto |
| PAY | Payments |
| CARD | Cards |
| FIN | Financial Core *(squad: Transactions & Accounting)* |
| CMP | Compliance/Support |
| BO | Backoffice Portal |

Projects match squads, one team backlog each.
