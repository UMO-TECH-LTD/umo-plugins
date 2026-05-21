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
| `CWN-1234` | Look up bead by label `jira:CWN-1234`; if not found, prompt to run `/sync` first |
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
Working on: [CWN-1234] Add Kafka retry logic
  JIRA: https://yourorg.atlassian.net/browse/CWN-1234
  Type: Story  |  Status: In Progress  |  Priority: Medium
  Sprint: Sprint 12

Acceptance Criteria (from JIRA):
  1. Retry up to 3 times with exponential back-off
  2. Dead-letter queue on final failure
  3. Metrics emitted per retry attempt

Notes (from bead):
  (empty)

Claim this bead and start working? (yes/no)
```

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
- Offer to use `/umo-jira-tracker:create sub-task --parent {KEY}` for any discovered sub-tasks.
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
Bead CWN-1234 is ready.

Next steps:
  Implement the feature, then:
  /umo-jira-tracker:commit  — create conventional commits
  /umo-jira-tracker:mr      — create MR and update JIRA
  /umo-jira-tracker:create sub-task --parent CWN-1234  — if you found sub-tasks
```

## Mid-flow: sub-task detection

During the discussion, if the agent identifies a logical sub-task that warrants a separate JIRA ticket (e.g., "this needs a separate migration step"), proactively offer:

```
This looks like a separate sub-task. Want me to create a new Sub-task under CWN-1234?
Run: /umo-jira-tracker:create sub-task --parent CWN-1234
Or just say "create sub-task for <description>" and I'll handle it.
```

Invoke the `jira-sync-back` creation path with `parentKey = CWN-1234` on confirmation.
