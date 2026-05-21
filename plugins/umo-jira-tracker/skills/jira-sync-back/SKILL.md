---
name: jira-sync-back
description: Single owner of all JIRA mutations — comments, transitions, description edits, and issue creation. Always previews the payload and waits for developer approval. Used by /mr, /close, /create, and inline sub-task prompts in /work. Enforces the creation-policy linkage matrix.
paths:
  - ".umo/jira-tracker.json"
---

# JIRA Sync-Back

This skill is the **single chokepoint** for every mutation sent back to JIRA. Nothing is written to JIRA without showing the developer a preview and receiving explicit approval.

Load `references/creation-policy.md` when any issue creation is requested.

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

```
CallMcpTool -> Atlassian / getTransitionsForJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{KEY}"
```

Find the transition whose `name` matches the configured value (e.g. `"In Review"` or `"Done"`). If no match, list available transitions and ask the developer to pick one.

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

Used by: `/work` (push implementation notes), `/create` (append unlinked justification).

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

  Description preview:
  {first 200 chars}

Create issue? (yes/no)
```

### Execute (on yes)

```
CallMcpTool -> Atlassian / createJiraIssue
  cloudId: "{cloudId}"
  fields: {
    "project": { "key": "{defaultProjectKey}" },
    "summary": "{summary}",
    "issuetype": { "name": "{issuetype}" },
    "parent": { "key": "{PARENT-KEY}" },    // omit if no parent and orphan approved
    "priority": { "name": "{priority}" },
    "description": "{description}"
  }
```

On success, receive the new issue key (e.g. `CWN-5678`).

### Round-trip to Beads

After successful creation, immediately upsert the new issue into beads using the same logic as `jira-sync` Phase 3:

1. Build bead fields from the new issue (type, title, labels, description).
2. `bd create` with parent linkage if the parent bead exists locally.
3. Report: `Bead created for {NEW-KEY}.`

---

## Combined flows

### `/mr` complete flow

1. Operation A: comment `MR created: {MR_URL}\n\n### Changes\n{bullet-list}` — ask approval.
2. Operation B: transition to `jira.transitionOnMr` — ask approval.

Both previews shown together before any action. Developer can approve all, approve individually, or skip either.

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
