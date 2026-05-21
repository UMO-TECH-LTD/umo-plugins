---
name: jira-sync-back
description: Single owner of all JIRA mutations — comments, transitions, description edits, and issue creation. Always previews the payload and waits for developer approval. Used by /mr, /close, /create, and inline sub-task prompts in /work. Enforces the creation-policy linkage matrix.
paths:
  - ".umo/jira-tracker.json"
---

# JIRA Sync-Back

This skill is the **single chokepoint** for every mutation sent back to JIRA. Nothing is written to JIRA without showing the developer a preview and receiving explicit approval.

Load `references/creation-policy.md` when any issue creation is requested.
Load `references/transitions.md` for any status transition — use cached IDs to avoid a live `getTransitionsForJiraIssue` call when the project is known.

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

Used by: `/mr` (→ `transitionOnMr`), `/close` (→ `transitionOnClose`).

### Resolve transition ID

**Step 1 — Check cache first.** Load `references/transitions.md` and look up the project key and configured transition name (e.g. `"In Review"` or `"Done"`). Use the cached transition ID if found — skip the live API call.

**Step 2 — Partial name match.** If the configured name does not exactly match a cached entry, try case-insensitive partial matching (e.g. `"in review"` → `"To Review"` for CWN). Always confirm the match with the developer before executing.

**Step 3 — Live fallback.** Only call `getTransitionsForJiraIssue` when the project is not in `references/transitions.md` or when a previously cached ID returns an error:

```
CallMcpTool -> Atlassian / getTransitionsForJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{KEY}"
```

After a successful live lookup, note the new transition IDs in your response so a developer or agent can update `references/transitions.md`.

If no match is found even after live lookup, list available transitions and ask the developer to pick one.

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

Used by: `/create`, inline sub-task creation from `/work`.

**Always** load `references/creation-policy.md` before executing this operation.

### Enforce linkage

Resolve parent following the matrix in `references/creation-policy.md`:

1. `--parent <KEY>` flag.
2. Currently claimed bead's `jira:` label (if invoked from `/work`).
3. `--under <bead-id>` → read its `jira:` label.
4. None → trigger **orphan warning** (see creation-policy.md).

If the issue type is Sub-task and no parent is resolved: **hard block** — never create unlinked Sub-tasks even with `create unlinked`.

### Preview

```
About to create {type} in project {PROJECT}:

  Summary:  {summary}
  Type:     {issuetype}
  Parent:   {PARENT-KEY}: {parent summary}  (or "NONE — unlinked")
  Priority: {priority}
  Assignee: {user.jiraAccountId display name}  (from config)

  Description preview:
  {first 200 chars}

Create issue? (yes/no)
```

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

On success, receive the new issue key (e.g. `CWN-5678`).

### Sprint assignment (create-then-edit pattern)

`customfield_10020` (sprint) is **silently ignored** by the Jira REST API when included in the `createJiraIssue` payload — it must be set in a separate edit call immediately after creation.

**Resolve sprint ID (in order):**

1. **Parent sprint** — if a parent key was provided, fetch it and read `customfield_10020[0].id`:
   ```
   CallMcpTool -> Atlassian / getJiraIssue
     cloudId: "{cloudId}"
     issueIdOrKey: "{PARENT-KEY}"
   ```
   Extract `fields.customfield_10020[0].id` from the response.
2. **Config default** — if `jira.defaultSprintId` exists in `.umo/jira-tracker.json`, use that value.
3. **Skip** — if neither source has a sprint ID, omit the edit call. The issue will appear in the backlog and can be moved to a sprint manually on the board.

**If a sprint ID was resolved**, call immediately after creation (no extra preview needed — this is a housekeeping step):

```
CallMcpTool -> Atlassian / editJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{NEW-KEY}"
  fields: {
    "customfield_10020": { "id": {sprintId} }
  }
```

Report the outcome:
- Success: `Sprint assigned: {sprint name} (id: {sprintId})`
- Error (e.g. sprint closed): surface the error and instruct the developer to assign the sprint manually on the board.

### Round-trip to Beads

After successful creation, immediately upsert the new issue into beads using the same logic as `jira-sync` Phase 3:

1. Build bead fields from the new issue (type, title, labels, description).
2. `bd create` with parent linkage if the parent bead exists locally.
3. Report: `Bead created for {NEW-KEY}.`

---

## Combined flows

### `/mr` complete flow

> **Important: never trigger a JIRA status transition on MR creation.** A developer may open multiple MRs for a single ticket (partial delivery, follow-up fixes, etc.). Transitioning the ticket status is the sole responsibility of `/close`.

1. Operation A: comment `MR created: {MR_URL}\n\n### Changes\n{bullet-list}` — ask approval.
2. Operation C: append (or extend) the MR delivery section in the JIRA description — ask approval.

Both previews shown together before any action. Developer can approve both, approve individually, or skip either.

### `/close` complete flow

1. Close bead: `bd close {bead-id} --reason "{reason}" --json`.
2. Operation A: comment `Work completed. MR: {MR_URL}\n\n{summary}` — ask approval.
3. Operation B: transition to `jira.transitionOnClose` — ask approval.

### `/create` complete flow

1. Collect summary, type, priority, parent from developer input.
2. Enforce linkage matrix (Operation D prefix).
3. Preview + create (Operation D).
4. Round-trip to Beads.
5. Optionally transition to `In Progress` if the developer is starting work immediately (ask).
