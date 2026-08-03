# JIRA Issue Creation Policy

This file is the authoritative source for what this plugin may create in JIRA and the linkage rules that govern every `createJiraIssue` call. Load it before executing any creation operation in `jira-sync-back` Operation D.

Read `../../../references/work-tracking-model.md` for the model. This file is the enforcement.

## Core principle

**This plugin creates Tasks and Bugs, under a Slice.** Nothing else.

Every issue it creates must have a parent, and that parent must be a **Slice** —
the parent chain is the single structural edge in the org's encoding, and an issue
that does not reach a Flow through its parents belongs to no flow and appears in
no cost ledger.

---

## Creatable types

| New issue type | Required parent | Orphan permitted? |
|----------------|-----------------|-------------------|
| **Task** | a **Slice** (`fields.parent`) | Warning + `create unlinked` phrase + justification |
| **Bug** | the **Slice** it broke, while that slice is open; otherwise the flow's standing defects-&-health slice | Warning + `create unlinked` phrase + justification |

## Types this plugin refuses

| Requested | Response |
|---|---|
| **Story** | Hard refusal — the type does not exist in this org |
| **Sub-task** | Hard refusal — the type does not exist in this org |
| **Epic** | Hard refusal — the epic slot is the Slice, created by the flow PM |
| **Slice** | Hard refusal — created by the flow PM |
| **Flow** | Hard refusal — created by the flow PM |
| **Request** | Hard refusal — created by the requesting PM or TL |

### Story and Sub-task — the type does not exist

There is no override phrase. Show:

```
ERROR: "{type}" is not an issue type in this organisation.

The five types are Flow, Slice, Task, Request and Bug.

  Story    → dev work is a Task. Create a Task under the Slice instead.
  Sub-task → private breakdown lives in the description as checkboxes, or in
             Beads. If it is a real unit of assignment, it is a sibling Task
             under the same Slice, not a child.

Re-run: /umo-jira-tracker:create task --parent <SLICE-KEY>
```

### Flow, Slice, Request, Epic — not this plugin's to create

Also no override phrase, but the reason is different and worth stating: these
carry content a coding agent is not positioned to author.

```
ERROR: this plugin does not create {type}s.

  Slice   — carries the demo statement, the inherited/new AC split, the
            dependency register and the scope declarations. Authored by the
            flow PM.
  Flow    — carries a flow-catalogue entry and a PM/TL pair. Authored by the
            flow PM.
  Request — carries a product AC, a technical contract, a needed-by date and a
            mock owner, and starts a 2-working-day acknowledgement SLA.
            Authored by the requesting PM or TL.

Ask on the board, then run /umo-jira-tracker:sync to pull it into Beads.
```

---

## Parent resolution order

When creating an issue, resolve the parent key using this priority order:

1. **Explicit `--parent <KEY>` flag** in the command input.
2. **The claimed bead's Slice** — if invoked from inside `/work`, walk from the
   active bead to its Slice. Note this is the claimed bead's *parent*, not the
   claimed bead itself: a Task cannot own a Task.
3. **`--under <bead-id>` argument** — read that bead's `jira:` label, then resolve
   to its Slice the same way.
4. **None found** → trigger the orphan warning (see below).

### Validating the parent

Before creating, fetch the resolved parent and check its type:

```
CallMcpTool -> Atlassian / getJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{PARENT-KEY}"
```

| Parent type | Action |
|---|---|
| **Slice** | proceed |
| **Task / Bug / Request** | the requested parent is a level-0 issue. Offer its Slice instead (see below) |
| **Flow** | a Task cannot hang directly off a Flow. Ask which of the Flow's Slices it belongs to |

When the parent is a level-0 issue:

```
{PARENT-KEY} is a {type}, not a Slice — a Task cannot sit under another
level-0 issue (that would be a Sub-task, which does not exist here).

Its Slice is {SLICE-KEY}: {slice summary}

Create this {type} under {SLICE-KEY} instead? (yes/no)
```

**Cross-project parents are legitimate.** A provider's Task may be parented to a
consumer's Slice in another project so the flow that caused the work pays for it.
Never reject a parent because its project key differs.

---

## Orphan warning protocol

When no parent is resolved, show this message and **stop until the developer responds**:

```
WARNING: You are about to create a {type} with no parent.

Every issue below Flow level belongs to a Slice — the parent chain is what puts
it in a flow's rollup and cost ledger. An issue with no parent trips the org's
orphan detector, which alarms you and your TL.

To provide a parent, re-run:
  /umo-jira-tracker:create {type} --parent <SLICE-KEY>

If this is tech debt with no obvious home, its home is your squad's standing
tech-health slice [TH-<KEY>-S0]. Anyone may file a Task there.

If you still want to create this {type} unparented, provide a justification
and type the exact phrase: create unlinked

Justification (one line — will be appended to the issue description):
```

**Parsing the developer's response:**

- If the response contains the exact phrase `create unlinked` AND a non-empty justification line: extract the justification and proceed.
- Any other response (including just typing "yes", "ok", or "proceed"): cancel with `Cancelled. Re-run with --parent <SLICE-KEY> to link to a slice.`
- The justification is appended to the issue description as:

```markdown
> **Created unlinked**: {justification}
```

---

## Summary grammar

The summary is not free text. Build it as:

```
[{SLICE-COORDINATE}] {outcome}
```

Take the coordinate from the parent Slice's own prefix — `[IC-S2]`, dash and never
slash, so the name stays safe if it ever appears in a file name.

| Type | Grammar |
|---|---|
| **Task** | imperative verb phrase |
| **Bug** | the symptom, not the diagnosis |

Banned in either: layer names, person names, status words, and "part 2 / misc /
fixes". If the developer's title breaks the grammar, propose a rewrite in the
preview and show the original next to it.

---

## Fields

Set: `project`, `summary`, `issuetype`, `parent`, `priority`, `assignee`, `description`.

**Never set**, on any issue this plugin creates:

| Field | Why |
|---|---|
| Sprint (`customfield_10020`) | unused org-wide — heartbeats do not open and close containers |
| Story points | unused org-wide — velocity is measured from consistently-sized counts |
| Original estimate / time tracking | cost is time-in-status, measured not estimated |
| **Due date** | meaningless on a Task. It is the `needed-by` on a Request and nothing else |
| Epic Link (`customfield_10014`) | superseded by the native `fields.parent` |
| Labels | the org's encoding carries no label taxonomy — the parent chain does the work |

`Blocks` is the only link type in the encoding. This plugin does not create links;
if a developer needs one, it belongs on the board.

---

## After successful creation

1. JIRA returns the new issue key (e.g. `PAY-5678`).
2. Immediately call the `jira-sync` upsert path for the new key:
   - Build bead fields (title, type, labels) per `jira-sync/references/mapping.md`.
   - Find parent bead by `jira:{PARENT-KEY}` label.
   - `bd create` the new bead with parent linkage.
3. Report to developer:

```
Created {type} {NEW-KEY}: {summary}
  JIRA:  https://umotech.atlassian.net/browse/{NEW-KEY}
  Slice: {PARENT-KEY} — {parent summary}
  Bead:  {bead-id} created with parent → {PARENT-BEAD-ID}

Start working on it now? Run:
  /umo-jira-tracker:work {NEW-KEY}
```

---

## Validation checklist (run before every createJiraIssue call)

- [ ] Issue type is **Task** or **Bug**. Every other type was refused.
- [ ] Parent is resolved and its type is **Slice** — or the `create unlinked` phrase and a justification were given.
- [ ] Summary carries the slice coordinate and follows the type's grammar.
- [ ] No Sprint, story points, estimate, due date, Epic Link or label in the payload.
- [ ] Justification appended to the description if unlinked.
- [ ] Developer saw and approved the creation preview (Operation D in jira-sync-back SKILL.md).
