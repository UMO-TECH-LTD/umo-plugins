# JIRA Issue Creation Policy

This file is the authoritative source for the linkage rules and orphan-warning protocol that govern every `createJiraIssue` call. Load it before executing any creation operation in `jira-sync-back` Operation D.

## Core principle

**Every JIRA issue must have a parent**, except Epics (which are always root-level). The agent must never silently create an unlinked issue. A Sub-task can never be created without a parent under any circumstances.

---

## Linkage matrix

| New issue type | Required parent | Allowed alternative parent | Orphan permitted? |
|----------------|-----------------|---------------------------|-------------------|
| Sub-task | Task / Story / Bug (`fields.parent`) | — | **Never — hard block** |
| Task | Story or Epic (`fields.parent` if next-gen, else Epic Link) | `is part of` link to Story/Epic | Warning + explicit approval only |
| Story | Epic (`fields.parent` / Epic Link) | — | Warning + explicit approval only |
| Bug | Story / Task / Epic (parent or Epic Link) | `relates to` an existing issue | Warning + explicit approval only |
| Epic | — (Epics are root-level) | — | Always require explicit approval |

---

## Parent resolution order

When creating an issue, resolve the parent key using this priority order:

1. **Explicit `--parent <KEY>` flag** in the command input.
2. **Currently claimed bead's `jira:` label** — if invoked from inside `/work`, the active bead's JIRA key is the natural parent for sub-tasks.
3. **`--under <bead-id>` argument** — read the target bead's `jira:` label.
4. **None found** → trigger the orphan warning (see below).

---

## Orphan warning protocol

When no parent is resolved (or when explicitly creating an Epic), show this message and **stop until the developer responds**:

```
WARNING: You are about to create a {type} that is not linked to any existing JIRA item.

Per STD-JIRA, every issue should sit under a parent:
  Sub-task ← Task / Story / Bug
  Task / Bug ← Story / Epic
  Story ← Epic

To provide a parent, re-run:
  /umo-jira-tracker:create {type} --parent <JIRA-KEY>

If you still want to create this {type} without a parent, provide a justification
and type the exact phrase: create unlinked

Justification (one line — will be appended to the issue description):
```

**Parsing the developer's response:**

- If the response contains the exact phrase `create unlinked` AND a non-empty justification line: extract the justification and proceed.
- Any other response (including just typing "yes", "ok", or "proceed"): cancel with `Cancelled. Re-run with --parent <KEY> to link to an existing issue.`
- The justification is appended to the issue description as:

```markdown
> **Created unlinked**: {justification}
```

---

## Sub-task hard block

Sub-tasks have an unconditional rule: **no parent = no creation**. Do not show the orphan warning for Sub-tasks — instead show a hard block:

```
ERROR: Sub-tasks must always be linked to a parent issue.
Provide the parent with: /umo-jira-tracker:create sub-task --parent <JIRA-KEY>
```

There is no override phrase for Sub-tasks.

---

## Epic creation special case

Epics are root-level (no parent required by JIRA schema), but they should still be rare inside a developer sprint session. Always require explicit approval:

```
You are about to create an Epic. Epics are top-level items and should usually
be created by a product manager or team lead.

Epic title: {summary}

Are you sure? Type 'create epic' to proceed, or 'cancel' to abort.
```

Only the exact phrase `create epic` proceeds.

---

## After successful creation

1. JIRA returns the new issue key (e.g. `CWN-5678`).
2. Immediately call the `jira-sync` upsert path for the new key:
   - Build bead fields (title, type, labels) per `jira-sync/references/mapping.md`.
   - Find parent bead by `jira:{PARENT-KEY}` label.
   - `bd create` the new bead with parent linkage.
3. Report to developer:

```
Created {type} {NEW-KEY}: {summary}
  JIRA:  https://yourorg.atlassian.net/browse/{NEW-KEY}
  Bead:  {bead-id} created with parent → {PARENT-BEAD-ID}

Start working on it now? Run:
  /umo-jira-tracker:work {NEW-KEY}
```

---

## Sprint field constraint

`customfield_10020` (sprint) **cannot be set during issue creation**. The Jira REST API silently ignores it in the `createJiraIssue` payload without returning an error.

**Always use the create-then-edit pattern** (implemented in Operation D of `jira-sync-back/SKILL.md`):

1. Create the issue without a sprint field.
2. Immediately call `editJiraIssue` with `customfield_10020: { "id": {sprintId} }`.

Sprint ID resolution order:
1. Inherit from the parent issue's active sprint (`fields.customfield_10020[0].id`).
2. Fall back to `jira.defaultSprintId` in `.umo/jira-tracker.json`.
3. Skip if neither is available.

**Never include `customfield_10020` in a `createJiraIssue` call** — it will be silently dropped and you will not know the issue landed in the backlog instead of the intended sprint.

---

## Validation checklist (run before every createJiraIssue call)

- [ ] Issue type is known (Sub-task / Task / Story / Bug / Epic).
- [ ] Parent key is resolved OR orphan/epic approval phrase was given.
- [ ] Sub-task never proceeds without a parent (hard block enforced).
- [ ] Epic only proceeds after `create epic` phrase.
- [ ] Justification appended to description if unlinked.
- [ ] Developer saw and approved the creation preview (Operation D in jira-sync-back SKILL.md).
- [ ] Sprint field will be set via a separate `editJiraIssue` call after creation (never in `createJiraIssue`).
