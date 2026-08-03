# JIRA Workflow Reference

The four workflows behind the org's five issue types, and the rules for moving
between their states. Read `../../../references/work-tracking-model.md` for the
model these workflows serve.

**No transition IDs are cached here.** They are per-project configuration that
drifts silently, and a stale ID produces a confident wrong move. Resolve every
transition live with `getTransitionsForJiraIssue`, match on the **target status
name** from the tables below, and preview the result before executing.

---

## The workflows

### Task

```
To Do → In Progress → Done
```

Plus **Retired** (global).

**Done means: the MR is merged and all existing tests are green.** Org automation
flips a Task to Done when its MR merges, keyed off the Jira key in the branch and
MR title. This plugin should therefore **not** transition a Task to Done on merge
— it would race the automation and take credit for a state it did not verify.
`/close` transitions only when the developer explicitly asks after the fact.

### Slice

```
Draft → Ready for development → In Progress → Done
```

Plus **Retired** (global).

> **Verified 2026-08-03:** the live status name is `Ready for development`
> (lowercase `d`), reached by a transition *named* `Ready`. This is exactly why no
> transition IDs or names are cached here — match on the target status name from
> the live response, case-insensitively, and never assume the transition and the
> status share a name.

Both forward gates are validated on the board and are not this plugin's business:

- **Draft → Ready for Development** is the product hand-off. A validator blocks it
  while the acceptance-criteria field is empty.
- **In Progress** requires the slice SPEC to exist with its review closed — no
  build without a SPEC link, or an explicit "N/A".

Retiring a Slice **cascades**: its open Requests are retired first, then its
unfinished Tasks. Never retire a Slice from here.

### Flow

```
To Do → In Progress → Done
```

Plus **Retired** (global).

The Jira status is coarse on purpose — the flow's real status is a derived
dashboard line, and the workflow state should follow from its children via
roll-up automation. **Never hand-transition a Flow.**

### Request

```
Open → Accepted → Mock Available → Delivered → Done
```

Plus **Retired** (consumer-owned terminal).

> **Verified against live Jira on 2026-08-03** (`umotech`, transitions on a
> `Delivered` Request): the terminal is **`Done`** (status id `10001`). There is
> **no `Closed` status** in the Request workflow. The canonical document describes
> this terminal as `Closed`, with the word carrying the "consumer proof" meaning.
> The intent is unambiguous either way and the plugin does not transition
> Requests, so nothing here depends on the resolution — but **do not "fix" the
> live workflow or the canon text from this plugin.** The discrepancy is flagged
> for the doc owners.

| State | Meaning |
|---|---|
| **Open** | the provider must acknowledge within 2 working days |
| **Accepted** | target date set; the technical contract is filled in by the provider's tech lead |
| **Mock Available** | a contract-shaped mock is up; expiry = the due date |
| **Delivered** | the real thing is deployed. The consumer is **still on the mock** |
| **Closed** | consumer proof: mock retired, consumer's tests green against the real thing |

**This plugin never transitions a Request.** Accept is the provider tech lead's
act and gated on a filled technical contract; Delivered is the provider's call;
Closed is the consumer's proof; Retired is consumer-owned and needs a reason plus
a successor link. If a developer asks, point them at the board and say why.

---

## Terminal vocabulary

| Type | Success terminal (live) |
|---|---|
| Task | **Done** |
| Slice | **Done** |
| Flow | **Done** |
| Request | **Done** — canon calls this state `Closed`; see the note above |

The *meaning* differs even where the word does not. A Request reaching its
terminal means **consumer proof**: the mock is retired and the consumer's tests
are green against the real thing. That is a much stronger claim than a Task being
merged, which is why only the consumer may make it — and why this plugin does not
transition Requests at all.

**Never fuzzy-match your way to a terminal.** If a configured transition name in
`.umo/jira-tracker.json` does not match what the live workflow offers, say so and
ask.

## Retired

**Retired** is the one shared terminal, and on every type it means the same thing:
**withdrawn from play without being completed.**

- **Resolution is mandatory** — `Won't Do`, `Duplicate`, `Superseded` or
  `Cannot Reproduce`. Note that as of **2026-08-03** the live `Retired` transition
  reports `hasScreen: false`, so Jira will *accept* a Retire with no Resolution.
  The rule is a policy, not a schema constraint: ask the developer for the
  Resolution and set it, rather than relying on Jira to stop you.
- **Retired is excluded from every count.** "All tasks done" at Slice-Done ignores
  retired tasks, and velocity counts Done only.
- Retiring a **Slice** cascades to its open Requests and unfinished Tasks.
- Retiring a **Request** is consumer-only and additionally needs a reason, a
  successor link, and an unwind plan for any live mock.

Given the cascade and the successor-link rules, this plugin retires **Tasks and
Bugs only**, and always with an explicit resolution chosen by the developer:

```
About to Retire {KEY} — "{summary}".

Retired means withdrawn without being completed. It is excluded from velocity
and from the "all tasks done" roll-up, and it is not the same as Done.

Resolution (required):
  1. Won't Do
  2. Duplicate
  3. Superseded
  4. Cannot Reproduce

Choice:
```

---

## Resolving a transition

1. Identify the issue's type and current status (`getJiraIssue`).
2. Look up the target status in the workflow tables above. If the requested move
   is not an edge in that workflow, stop and explain — do not look for a path.
3. Check the guardrails: is this a type this plugin transitions at all? Flow,
   Slice and Request are never transitioned from here.
4. Fetch the live transitions:

```
CallMcpTool -> Atlassian / getTransitionsForJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{KEY}"
```

5. Match on the target status name, case-insensitively. On an ambiguous or absent
   match, list what Jira actually offers and ask the developer to pick — never
   guess.
6. Preview, then execute.

If a transition requires a screen (Retired always does), include the required
fields in the `transitionJiraIssue` payload.

## Multi-step paths

Some workflows have no direct edge between two states — most commonly getting
back to **In Progress** from a review or testing status. There is no cached list
of these: discover the available transitions live, build a step plan, and show
every step in **one** approval gate before executing any of them. See
`../SKILL.md` Operation B-multi.

If a step fails, stop and report which steps succeeded. Do not claim a bead or
report success on a partially-applied path.
