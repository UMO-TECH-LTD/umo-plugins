# JQL Reference for jira-sync

## Setup presets

`/umo-jira-tracker:setup` offers these presets — stored as `jira.syncJql` in `.umo/jira-tracker.json`:

| Preset | JQL |
|--------|-----|
| All open assigned tickets (default) | `assignee = currentUser() AND statusCategory != Done` |
| One flow, everything serving it | `issuekey in portfolioChildIssuesOf("{FLOW-KEY}")` |
| One slice | `parent = {SLICE-KEY} OR issuekey = {SLICE-KEY}` |

The all-open preset returns every unresolved issue assigned to you. The flow
preset returns everything serving that flow **across all projects** — Slices,
Tasks, Bugs, and the Requests filed against other teams — which is the shape the
parent chain was designed to give you.

**There is no sprint preset.** The Sprint field is unused org-wide: heartbeats do
not open and close containers, and tasks stay open until they are merge-ready.

## Config override

The user can set `jira.syncJql` in `.umo/jira-tracker.json` to any JQL. Re-run `/umo-jira-tracker:setup` to switch presets, or edit the file directly. The `/sync` command's `--jql` flag overrides for a single run without touching the config.

## Recently-Done extension (automatic)

`jira-sync` Phase 0 augments the configured JQL with a recently-closed window so the pull can detect issues that reached a terminal state in JIRA while the developer was offline (status drift). Build the effective query as:

```
({configured-jql}) OR (assignee = currentUser() AND statusCategory = Done AND updated >= {sync.recentlyDoneWindow})
```

`statusCategory = Done` is the right filter here even though the terminal *status*
differs by type — `Done` on a Task, Slice or Flow, `Closed` on a Request, and
`Retired` on anything withdrawn all sit in the Done **category**. The pull
distinguishes them when it closes the bead; see `mapping.md` → Status
reconciliation.

`sync.recentlyDoneWindow` defaults to `-14d` and lives under the `sync` block in `.umo/jira-tracker.json`. Skip the extension when:

- The developer passed `--jql` (treat their query as exact).
- The configured JQL already contains `statusCategory = Done` (would be redundant).

Example expanded query when the user has the default preset:

```
(assignee = currentUser() AND statusCategory != Done)
OR
(assignee = currentUser() AND statusCategory = Done AND updated >= -14d)
```

## The canonical queries

These come from the org's work-tracking encoding and are worth offering by name.

### Flow view / cost ledger

Everything serving a flow, wherever it lives — one query, all projects. This is
Premium-only and is the reason the parent chain carries no companion field.

```
issuekey in portfolioChildIssuesOf("{FLOW-KEY}")
```

### What is still fake

A slice's open dependencies — the Requests that are still promises rather than
working software.

```
parent = {SLICE-KEY} AND type = Request AND status not in (Closed, Retired)
```

Nobody maintains a dependency list; the open Requests *are* the list.

### Promise board

Mocks past their expiry, across a project. The due date on a Request is the
`needed-by`, and after the contract is agreed it doubles as the mock expiry.

```
type = Request AND status = "Mock Available" AND due < now()
```

### Orphans

Issues below Flow level with no parent. The org runs a standing orphan detector;
this is the same question, scoped to your project.

```
project = {KEY} AND type in (Task, Bug, Request) AND parent is EMPTY AND statusCategory != Done
```

### Tech-health backlog

A squad's standing flat list. Anyone may file a Task here.

```
parent = "{TH-KEY}-S0" ORDER BY Rank ASC
```

## Atlassian MCP call

```
CallMcpTool -> Atlassian / searchJiraIssuesUsingJql
  cloudId: "{cloudId}"
  jql: "{effective JQL}"
  fields: ["summary","status","priority","issuetype","parent","assignee","description","comment","resolution","duedate","updated"]
  maxResults: 100
```

- `resolution` drives the recently-closed branch and carries the mandatory reason on a `Retired` issue.
- `duedate` is the `needed-by` on a Request. It is meaningless on a Task and should be ignored there.
- **`parent` is the only structural field.** Do not request `customfield_10014` (Epic Link) or `sprint` — neither is part of the encoding.

If the result set reaches `maxResults`, paginate with `startAt` until `total` is exhausted.

## Handling missing fields

- `fields.parent` may be null on a **Flow** (it is the root) — that is correct. On a Task, Bug or Request it means an orphan: leave the parent bead unset and surface it in the report rather than passing over it silently.
- A parent may sit outside the JQL scope. Fetch it with `getJiraIssue` so the chain can be walked up to the Flow; if it still cannot be resolved, omit the `jira-flow:` label rather than guessing.
- `fields.description` may be null — leave the `Acceptance Criteria` section empty with a `_(none)_` placeholder.
- `fields.resolution` may be null on a `Retired` issue. Resolution is mandatory there, so close the bead anyway and warn — it is a data defect worth naming.
