---
name: jira-bead-bridge
description: Claim a bead, guide the discuss→decide→store loop, draft or refine acceptance criteria, and push implementation notes back to JIRA. Use when starting work on a ticket or when the developer wants to discuss implementation approach with AI.
paths:
  - ".umo/jira-tracker.json"
  - "**/.beads/**"
---

# JIRA Bead Bridge

Bridges the "what am I building?" discussion with the local Beads database and JIRA. The developer enters with a ticket key or bead id; they exit with a claimed bead, refined AC, and optionally updated JIRA description.

## Trigger

Invoked by `/umo-jira-tracker:work`.

## Step 1 — Resolve the target

Parse the input:

| Input form | Resolution |
|------------|------------|
| `PAY-1234` | Look up bead by label `jira:PAY-1234`; if not found, prompt to run `/sync` first |
| `<bead-id>` | `bd show {id} --json`; extract `jira:` label for JIRA key |
| `--ready` | `bd ready --json`; present the list and ask the developer to pick one |
| (empty) | `bd ready --json`; present the top 5 and ask |

If a JIRA key is resolved, fetch fresh details from JIRA:

```
CallMcpTool -> Atlassian / getJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{KEY}"
```

## Step 2 — Present context

Show a structured summary:

```
Working on: [PAY-1234] [IC-S2] Retry publishes survive a broker restart
  JIRA:  https://umotech.atlassian.net/browse/PAY-1234
  Type:  Task  |  Status: In Progress  |  Priority: Medium
  Slice: PAY-1200 — [IC-S2] Client can see their status
  Flow:  PAY-900 — [IC] Client onboarding

Acceptance Criteria (from JIRA):
  1. Retry up to 3 times with exponential back-off
  2. Dead-letter queue on final failure
  3. Metrics emitted per retry attempt

Notes (from bead):
  (empty)

Claim this bead and start working? (yes/no)
```

### Step 2b — Resume a ticket that is not in a startable state

The Task workflow is `To Do → In Progress → Done` plus a global `Retired`. If the
ticket is already **In Progress**, claim and continue.

If it sits anywhere else and the developer wants to resume, resolve the available
transitions live (`getTransitionsForJiraIssue`) and offer the move:

```
{KEY} is currently "{status}". Move it to In Progress before claiming? (yes/no)
```

- **yes** → delegate to `jira-sync-back` **Operation B**, or **Operation B-multi**
  when no direct edge exists. Either way, one preview covering every step, before
  any of them run. On success, continue to Step 3.
- **no** → continue to Step 3 without changing JIRA status (the bead can still be
  claimed locally).

**Guardrails.** Only Tasks and Bugs are transitioned from here. If the resolved
issue is a **Slice**, a **Flow** or a **Request**, say so and stop: Slice gates are
validated on the board, Flow status is derived from its children, and Request
states are the provider's and consumer's acts. Never offer **Retired** as a way to
get unstuck — it means withdrawn without being completed and is excluded from
every count.

## Step 3 — Claim

On yes:

```bash
bd update {bead-id} --claim --json
```

Report: `Bead {id} claimed. Status: In Progress.`

## Step 4 — Discuss

Open a free-form discussion with the developer:

- Clarify requirements, edge cases, and unknowns.
- Explore implementation options (ask for constraints: language, existing patterns, perf targets).
- Help the developer decide on the approach.
- Ask explicitly: "Shall I refine the acceptance criteria based on our discussion?"

Rules:
- Do not start implementation in this skill — this is planning/AC-refinement only.
- Decompose freely **in Beads**. Steps inside this Task are an engineering artifact and stay in git; they are not synced to Jira.
- Only when a discovered piece is a separate **unit of assignment or delivery** does it need its own Jira Task — and it is a **sibling** under the same Slice, never a child of this ticket. See "Mid-flow: discovered work" below.
- Keep discussion focused on the current ticket; spin off new tickets for scope creep.

## Step 5 — Store decisions in bead

After the discussion converges, offer to update the bead's `## Notes` section with:

- Agreed implementation approach (1–3 sentences).
- Key decisions made and why.
- Refined AC (if changed from JIRA).
- Open questions still to resolve.
- Links to relevant code, ADRs, or prior art.

Format:

```markdown
## Notes

### Approach
<1–3 sentence summary>

### Decisions
- <decision 1> — <reason>
- <decision 2> — <reason>

### Refined AC
1. <refined criterion 1>
2. <refined criterion 2>

### Open questions
- <question> — owner: <dev|team>
```

Execute:

```bash
bd update {bead-id} --description "{jira-zone}\n\n{updated-notes-zone}" --json
```

**Never overwrite the JIRA-sourced zone** — preserve it verbatim above `## Notes`.

## Step 6 — Push back to JIRA (approval-gated)

Offer:

```
Push the refined AC and implementation notes to JIRA as "## Implementation Notes"?
This will append a new section to the JIRA description (existing content is preserved).
Preview:

## Implementation Notes

### Approach
<...>

### Refined AC
<...>

Post to JIRA? (yes/no)
```

On yes, call `jira-sync-back` skill's JIRA description update path:

```
CallMcpTool -> Atlassian / editJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{KEY}"
  fields: {
    "description": "{existing-description}\n\n{implementation-notes-block}"
  }
```

Only post when the developer explicitly approves. Never silently modify JIRA.

## Step 7 — Handoff

```
Bead PAY-1234 is ready.

Next steps:
  Implement the feature, then:
  /umo-jira-tracker:commit  — create conventional commits
  /umo-jira-tracker:mr      — create MR and update JIRA

  Decompose further with `bd create --parent` — steps stay in Beads.
  /umo-jira-tracker:create task --parent PAY-1200  — only if you found a
      separate unit of delivery (sibling under the same Slice)
```

## Mid-flow: discovered work

During the discussion the agent will identify pieces of work that were not in the
original ticket. Most of them are **steps**, and steps live in Beads:

```bash
bd create "Write the migration" --type task --parent {current-bead-id}
```

That is the default and it needs no Jira round-trip. The 01.08 ruling is explicit
that the execution plan inside one task is an engineering artifact living in git.

Escalate to a Jira Task only when the piece is a **unit of assignment or
delivery** — someone will work on it for a meaningful stretch, or QA, the PM, the
EM or the CTO needs to see its status. Then it is a **sibling**, parented to the
same Slice:

```
This looks like a separate unit of delivery rather than a step in PAY-1234.

  Step      → stays in Beads (bd create --parent {bead-id})
  Unit      → its own Task under the same Slice ({SLICE-KEY})

Which is it? (step / unit)
```

On `unit`, invoke the `jira-sync-back` creation path with
`parentKey = {SLICE-KEY}` — resolved by walking from the current ticket to its
parent Slice, **not** the current ticket itself. A Task cannot own a Task; the
Sub-task type does not exist in this org.

You rarely need to force this call. The merge gate settles it: no MR merges
without a Jira Task, so anything that ends in a merge acquires one by definition.
