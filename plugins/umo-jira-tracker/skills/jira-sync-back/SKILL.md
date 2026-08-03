---
name: jira-sync-back
description: Single owner of all JIRA mutations — comments, transitions, description edits, and issue creation. Always previews the payload and waits for developer approval. Used by /mr, /close, /create and /work. Creates Tasks and Bugs under a Slice only, and transitions Tasks and Bugs only; refuses Story, Sub-task, Epic, Slice, Flow and Request. Enforces the creation policy.
paths:
  - ".umo/jira-tracker.json"
---

# JIRA Sync-Back

This skill is the **single chokepoint** for every mutation sent back to JIRA. Nothing is written to JIRA without showing the developer a preview and receiving explicit approval.

Load `../../references/work-tracking-model.md` for the org's encoding — five issue types, the parent chain as the only structural edge, and the fields that are deliberately unused.
Load `references/creation-policy.md` when any issue creation is requested.
Load `references/transitions.md` for any status transition.

**The blast radius of this skill is narrow on purpose.** It creates **Tasks and Bugs under a Slice**, and it transitions **Tasks and Bugs**. Flows, Slices and Requests are authored and moved by the flow PM and the tech leads, on the board — they carry demo statements, contracts, mock owners and due dates that a coding agent is not positioned to author. Refuse them with the reason.

## Shared prerequisites

For every operation:

1. Read `.umo/jira-tracker.json`.
2. Resolve `cloudId` (once per session):

```
CallMcpTool -> Atlassian / getAccessibleAtlassianResources
```

Pick the resource matching `jira.cloudUrl`.

---

## Operation A — Add comment to JIRA issue

Used by: `/mr` (MR created), `/close` (work completed).

### Preview

Show the developer:

```
About to post to JIRA {KEY}:

---
{comment body}
---

Post comment? (yes/no)
```

### Execute (on yes)

```
CallMcpTool -> Atlassian / addCommentToJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{KEY}"
  commentBody: "{body}"
```

### Idempotency

Before posting, check existing comments via `getJiraIssue` and scan for a comment that starts with the same first line (e.g. `MR created: {MR_URL}`). If found, skip and report "comment already exists — skipping".

---

## Operation B — Transition JIRA issue

Used by: `/close` (→ `transitionOnClose`).

> **Not used by `/mr`.** MR creation never transitions JIRA status.

### Guardrails — what may be transitioned

| Type | Transitionable from here? |
|---|---|
| **Task**, **Bug** | yes |
| **Slice** | no — the Draft→Ready and Ready→In Progress gates are validated on the board |
| **Flow** | no — status is derived from its children by roll-up automation |
| **Request** | no — Accept is the provider TL's act, Closed is the consumer's proof, Retired is consumer-owned |

Resolve the issue's type before anything else and refuse the other three with the reason, not just a "no".

Two more rules from `references/transitions.md`:

- **Terminal vocabulary is not interchangeable.** Task and Bug end in **Done**. Only a Request ends in **Closed**, and this plugin does not transition Requests.
- **Retired is not a synonym for Done.** It means withdrawn without being completed, it is excluded from every count, and its Resolution is mandatory. Never reach for it to get an issue out of the way.

### Resolve the transition

Load `references/transitions.md` for the workflow tables, then check that the requested move is an edge in the issue type's workflow. If it is not, stop and explain — do not go looking for a path.

Transition IDs are **not** cached: they are per-project configuration that drifts silently, and a stale ID makes a confident wrong move. Always resolve live:

```
CallMcpTool -> Atlassian / getTransitionsForJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{KEY}"
```

Match on the **target status name**, case-insensitively. If the match is ambiguous or absent, list what Jira actually offers and ask the developer to pick — never guess, and never fuzzy-match across terminals.

If the transition requires a screen (Retired always does), include the required fields — for Retired that means a Resolution of `Won't Do`, `Duplicate`, `Superseded` or `Cannot Reproduce`, chosen by the developer.

### Preview

```
About to transition {KEY} from "{current status}" to "{target status}".

Proceed? (yes/no)
```

### Execute (on yes)

```
CallMcpTool -> Atlassian / transitionJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{KEY}"
  transition: { "id": "{transition-id}" }
```

---

## Operation B-multi — Multi-step transition

Used by: `/work` when resuming a Task or Bug that has no direct edge to **In Progress**.

The same guardrails as Operation B apply: Tasks and Bugs only.

### Build the step plan live

There is no cached list of sequences. Call `getTransitionsForJiraIssue`, see what the current status actually offers, and build the shortest path to the target status. If the only available first hop is a move back toward `To Do`, that is normally the intermediate step.

If no path can be built from what Jira offers, stop and show the developer the available transitions rather than inventing one.

### Preview

Show all steps in one approval gate:

```
About to transition {KEY} from "{current status}" to "{target status}" ({N} steps):

  Step 1: {transition name} (id {id}) → {intermediate status}
  Step 2: {transition name} (id {id}) → {target status}

Proceed? (yes/no)
```

### Execute (on yes)

Run each `transitionJiraIssue` call **in order**, re-fetching the issue (`getJiraIssue`) between steps to confirm it landed where the plan expected before continuing.

```
CallMcpTool -> Atlassian / transitionJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{KEY}"
  transition: { "id": "{step-1-id}" }

// after step 1 succeeds

CallMcpTool -> Atlassian / transitionJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{KEY}"
  transition: { "id": "{step-2-id}" }
```

If any step fails, stop and report which step succeeded and which failed. Do not claim the bead until the developer confirms how to proceed.

---

## Operation C — Edit JIRA description

Used by: `/work` (push implementation notes), `/create` (append unlinked justification), `/mr` (append MR delivery section).

### Preview

Show the full new description or the appended section:

```
About to update description of {KEY}.
New content to append:

---
{new section markdown}
---

Append to JIRA description? (yes/no)
```

### Execute (on yes)

Fetch the existing description first:

```
CallMcpTool -> Atlassian / getJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{KEY}"
```

Append the new section below the existing content:

```
CallMcpTool -> Atlassian / editJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{KEY}"
  fields: {
    "description": "{existing-description}\n\n{new-section}"
  }
```

### MR delivery section format (used by `/mr`)

When called from `/mr`, the section appended to the JIRA description is:

```markdown
## MR Delivery

| MR | Branch | Summary |
|----|--------|---------|
| [{MR_TITLE}]({MR_URL}) | `{source-branch}` | {one-line summary of what was shipped} |

**Changes included:**
- {commit message 1}
- {commit message 2}
- …

> Added {date} by {gitlabUsername from config}
```

If a delivery section already exists (scan the existing description for `## MR Delivery`), append a new table row to the existing table rather than creating a second `## MR Delivery` heading. This supports the multiple-MR-per-ticket workflow.

---

## Operation D — Create JIRA issue

Used by: `/create`, and by `/push` when promoting a bead that has become a unit of delivery.

**Always** load `references/creation-policy.md` before executing this operation.

### Enforce the type

Only **Task** and **Bug** are creatable. Refuse everything else before doing any other work — `creation-policy.md` carries the exact messages:

- **Story**, **Sub-task** — the types do not exist in this org. No override.
- **Epic**, **Slice**, **Flow**, **Request** — authored by the flow PM or the requesting PM/TL. No override.

### Enforce linkage

Resolve the parent following `references/creation-policy.md`:

1. `--parent <KEY>` flag.
2. The claimed bead's **Slice** (if invoked from `/work`) — the claimed bead's parent, not the bead itself.
3. `--under <bead-id>` → read its `jira:` label, then resolve to its Slice.
4. None → trigger the **orphan warning**.

Then **fetch the parent and verify it is a Slice**. If it is a Task, Bug or Request, offer its Slice instead — a level-0 issue cannot own another. If it is a Flow, ask which of its Slices. A parent in a different project is legitimate and must not be "corrected".

### Preview

```
About to create {type} in project {PROJECT}:

  Summary:  [{SLICE-COORDINATE}] {outcome}
  Type:     {Task|Bug}
  Slice:    {PARENT-KEY}: {parent summary}  (or "NONE — unlinked")
  Flow:     {FLOW-KEY}: {flow summary}
  Priority: {priority}
  Assignee: {user.jiraAccountId display name}  (from config)

  Description preview:
  {first 200 chars}

Create issue? (yes/no)
```

If the developer's title does not follow the type's grammar — imperative verb phrase for a Task, symptom rather than diagnosis for a Bug — show the proposed rewrite next to the original.

### Execute (on yes)

Read `user.jiraAccountId` from `.umo/jira-tracker.json`. If present, include the `assignee` field:

```
CallMcpTool -> Atlassian / createJiraIssue
  cloudId: "{cloudId}"
  fields: {
    "project": { "key": "{defaultProjectKey}" },
    "summary": "{summary}",
    "issuetype": { "name": "{issuetype}" },
    "parent": { "key": "{PARENT-KEY}" },    // omit if no parent and orphan approved
    "priority": { "name": "{priority}" },
    "assignee": { "accountId": "{user.jiraAccountId}" },  // omit if not set in config
    "description": "{description}"
  }
```

On success, receive the new issue key (e.g. `PAY-5678`).

### Fields that must never appear in the payload

| Field | Why |
|---|---|
| Sprint (`customfield_10020`) | unused org-wide — heartbeats do not open and close containers, and tasks stay open until merge-ready |
| Story points | unused org-wide — velocity is measured from consistently-sized counts, not estimated |
| Original estimate / time tracking | cost is time-in-status, measured not estimated |
| **Due date** | meaningless on a Task. It is the `needed-by` on a Request and nothing else |
| Epic Link (`customfield_10014`) | superseded by the native `fields.parent` |
| Labels | the encoding carries no label taxonomy — the parent chain does the work |

If a developer asks for one of these, say it is not part of the org's encoding rather than setting it quietly. See `../../references/work-tracking-model.md` §2.

### Round-trip to Beads

After successful creation, immediately upsert the new issue into beads using the same logic as `jira-sync` Phase 3:

1. Build bead fields from the new issue (type, title, labels, description).
2. `bd create` with parent linkage if the parent bead exists locally.
3. Report: `Bead created for {NEW-KEY}.`

---

## Combined flows

### `/mr` complete flow

> **Important: never trigger a JIRA status transition on MR creation.** Two reasons, and both stand on their own. A developer may open several MRs for one ticket, so an MR is not evidence of completion. And **Task Done is the merged-PR automation's call** — it fires on merge, keyed off the Jira key in the branch and MR title. Transitioning from here would race it and claim a state this plugin has not verified.

1. Operation A: comment `MR created: {MR_URL}\n\n### Changes\n{bullet-list}` — ask approval.
2. Operation C: append (or extend) the MR delivery section in the JIRA description — ask approval.

Both previews shown together before any action. Developer can approve both, approve individually, or skip either.

### `/close` complete flow

1. Close bead: `bd close {bead-id} --reason "{reason}" --json`.
2. Operation A: comment `Work completed. MR: {MR_URL}\n\n{summary}` — ask approval.
3. Operation B: transition to `jira.transitionOnClose` — ask approval.

Step 3 is usually a no-op worth checking first: if the MR is already merged, the org automation has flipped the Task to Done. Fetch the issue, and when it is already terminal, report that instead of transitioning.

### `/create` complete flow

1. Collect summary, type, priority and parent from developer input.
2. Refuse any type other than Task and Bug; resolve and verify the parent Slice (Operation D prefix).
3. Preview + create (Operation D).
4. Round-trip to Beads.
5. Optionally transition to `In Progress` if the developer is starting work immediately (ask).

### `/work` resume flow

When `/work` loads a Task or Bug that is not in a startable state:

1. Present context (via `jira-bead-bridge` Step 2).
2. Offer: *"{KEY} is currently '{status}'. Move it to In Progress before claiming?"*
3. On yes: Operation B, or Operation B-multi when no direct edge exists — with the path resolved live.
4. Claim the bead and continue the discuss loop.

Do **not** transition silently — always show the preview, covering every step at once, and wait for approval. If the issue is a Slice, Flow or Request, do not offer a transition at all.
