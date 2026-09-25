# GitLab MCP Reference

Use the GitLab MCP as the **preferred** path for MR creation when it is configured and working. Fall back to `glab` if the MCP is unavailable or returns an error.

## Configure GitLab MCP

Add to your Cursor / Claude `mcp.json`:

```json
{
  "mcpServers": {
    "gitlab": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@zereight/mcp-gitlab"],
      "env": {
        "GITLAB_PERSONAL_ACCESS_TOKEN": "${env:GITLAB_PERSONAL_ACCESS_TOKEN}",
        "GITLAB_API_URL": "https://gitlab.com/api/v4"
      }
    }
  }
}
```

## Resolve project ID

Prefer numeric IDs. URL-encoded paths (e.g. `group%2Frepo`) may not work with all tool versions.

If the project ID is not already stored in `.umo/jira-tracker.json`, use the search tool:

```
CallMcpTool -> gitlab / search
  scope: "projects"
  search: "<repo-name>"
```

Pick the matching numeric `id` and persist it to config.

## Check for an existing open MR

```
CallMcpTool -> gitlab / search
  scope: "merge_requests"
  search: "<branch-name>"
  project_id: "<numeric-id>"
  state: "opened"
```

## Create MR

```
CallMcpTool -> gitlab / create_merge_request
  id: "<numeric-project-id>"
  title: "<MR title>"
  source_branch: "<source-branch>"
  target_branch: "<target-branch>"
  description: "<MR description markdown>"
```

Report the returned `web_url` to the developer on success.

## Fallback order

1. GitLab MCP `create_merge_request` (when configured and working).
2. **`glab mr create`** (see `references/glab.md`) when MCP is missing or errors.
3. Manual: output the MR title and description as a copyable block for the GitLab UI.

## Phase 8 tooling gate

Phase 8 of `/umo-jira-tracker:mr` polls CI and the review agent, so it needs
one working GitLab client. Preference order for **polling**:

1. `glab` (installed and `glab auth status` clean) — the native `glab ci
   status` / `glab mr note` commands in `references/glab.md`.
2. **GitLab MCP** (this file) when `glab` is missing or unauthenticated.
3. Neither → Phase 8 cannot run. Report that the MR was created successfully
   in Phase 6, that automated CI/review monitoring is unavailable, and that
   the developer must watch CI and review manually — then end the command. Do
   not error, hang, or retry; this is expected degradation.

## Phase 8 budget script

The loop budget (6 fix→push iterations, 2700s wall clock, 40 polls) is
enforced by `scripts/phase8-budget.sh` in this skill, and it is
**client-agnostic** — use it on the MCP path exactly as on the `glab` path,
one `poll` per MCP poll call and one `iteration` before every fix push:

```bash
sh scripts/phase8-budget.sh reset     {project-id}-{iid}   # FIRST, once per run
sh scripts/phase8-budget.sh poll      {project-id}-{iid}   # every 8b/8c check
sh scripts/phase8-budget.sh iteration {project-id}-{iid}   # BEFORE a fix push
sh scripts/phase8-budget.sh status    {project-id}-{iid}   # read-only report
```

Step 8a calls `reset` once before the first `poll`, so a leftover state file
from an earlier run on the same MR can't make the first poll report
`BUDGET EXCEEDED: wall-clock` and fake a handoff.

Exit `0` = within budget, `1` = `BUDGET EXCEEDED` → Step 8d, `2` = called
wrong (bad/missing argument), which is not budget exhaustion, `3` = the
script's environment is broken (state dir or lock unusable) → fall back to
manual `date +%s` bookkeeping. `status` never modifies state and always exits
0. State lives in `${TMPDIR:-/tmp}/umo-phase8/{key}.state`, outside the git
tree, isolated per MR key — concurrent Phase 8 runs on different MRs on one
machine never interfere, and same-key mutations are serialized by an advisory
lock.

The poll interval is a flat **180 seconds** between every two checks in 8b and
8c — no backoff, no shorter first pass. That is client-agnostic too: an MCP
poll is no cheaper than a `glab` one, and CI in this org rarely changes state
inside three minutes. Wait it out in **one** backgrounded call, per Step 8b of
`/umo-jira-tracker:mr` — a foreground `sleep` that long is blocked on Claude
Code, and chaining shorter ones is a banned workaround. At that cadence the
2700s clock allows ~15 polls, so
`wall-clock` normally trips before `MAX_POLLS=40`; 40 is a backstop against a
loop that skips its sleep, not the binding limb (see `references/glab.md`).

`status` splits the elapsed clock so the Step 8d/8e report shows where the 45
minutes went, not just how many are gone:

```
status | poll 10/40 | elapsed 2520s/2700s | polling 1440s | remediation 900s | since-last 180s | iterations 2/6 | OK
```

`polling` is time in gaps of ≤360s between counted calls (one 180s sleep plus
its check, with a full interval of slack for overhead); `remediation` is time
in longer gaps — log reading, ticket edits, waiting on a developer, building
and pushing a fix — during which the poll counter stands still while the clock
runs; `since-last` is the not-yet-counted remainder after the last
`poll`/`iteration`. This matters as much on the MCP path as on `glab`: MCP
poll calls are the ones the counter tracks, so the same `elapsed`-vs-`poll`
mismatch appears here. Quote the whole line. These are report-only counters
and enforce nothing. Full interface, the `POLL_GAP_SECONDS` rationale, and the
manual fallback: `references/glab.md` → "Phase 8 budget script".

## Poll pipeline status (used by `/umo-jira-tracker:mr` Phase 8b)

`include` takes exactly one facet per call:

```
CallMcpTool -> gitlab / get_merge_request
  url: "<mr-url>"                 # or project_id + merge_request_iid
  include: ["pipelines"]
```

Read the pipeline whose `sha` equals the MR head (`git rev-parse HEAD`), not
the first `success` in the list. The list is newest-first, but an older green
row must not end the wait. No row for that SHA yet → wait one 180s poll
interval and check again (a push may not have created the pipeline).
`skipped` → no CI gate, go straight to discussions. In-flight
(`created`/`waiting_for_resource`/`preparing`/`pending`/`running`/`scheduled`)
→ wait one 180s poll interval, then poll again. `success` on **that SHA** →
move to discussions.
`canceled` → usually just the stale run GitLab auto-cancelled when Phase 8's
own fix push superseded it: re-poll **once** for the current HEAD's pipeline
and follow that if it exists; only if `canceled` is still the latest after
that single re-poll is it unfixable by pushing code — then stop and report
(Step 8d) instead of looping.
`failed` → find the failing job(s) and their logs:

```
CallMcpTool -> gitlab / get_pipeline
  id: "<project-id>"
  pipeline_id: <id>
  include: ["jobs"]
  job_status: "failed"

CallMcpTool -> gitlab / get_job
  id: "<project-id>"
  job_id: <id>
  include: ["log"]
```

`get_job` pages a long log via `byte_offset`/`byte_limit` (max 512000 bytes
per call).

## List / reply / resolve MR discussions (used by Phase 8c)

On the `glab` path, prefer the native `glab mr note list/create/resolve`
commands (`references/glab.md`) — experimental but no-JSON-tooling. These MCP
calls are the equivalent when `glab` is unavailable.

```
CallMcpTool -> gitlab / get_merge_request
  url: "<mr-url>"
  include: ["discussions"]
```

`saas-mr-reviewer` rewrites one summary note in place (`### saas-mr-reviewer ·
run <UTC time>`). Judge that note by `updatedAt` and the `run` time in the
body, not `createdAt`. A review older than the current HEAD push is not this
commit's review. Do not post a second summary, and do not resolve the bot's
threads.

Each discussion carries an `id` (pass as `discussion_id` below — accepts
either the bare id or the full `gid://gitlab/Discussion/<id>` form) and a
`notes` array. Read **every** note in it, not just `notes[0]`: the first note
only opened the thread, so a human who replied to an agent-opened thread is
invisible if you stop there, and the freshness check needs the *newest* note's
timestamp. Identify the review agent from the MR's own `reviewers` list (it
self-assigns as reviewer per `code-review.md`) — `get_merge_request` returns
it; any author outside that set is a human, and a thread with any human author
is off-limits to this loop. `resolvable`/`resolved` live on each **note**, not on the
discussion itself — a discussion is unresolved when any of its resolvable
notes has `resolved: false`. Use each note's `author` to tell the review
agent's own threads apart from a human reviewer's, and never touch the
latter from this loop.

**Reply to a thread** (always before resolving; `body` may not start a line
with `/` — GitLab reads that as a quick action):

```
CallMcpTool -> gitlab / save_merge_request_review
  method: "reply_discussion"
  url: "<mr-url>"
  discussion_id: "<id>"
  body: "<what changed, or why this doesn't apply>"
```

**Resolve it:**

```
CallMcpTool -> gitlab / save_merge_request_review
  method: "resolve_discussion"
  url: "<mr-url>"
  discussion_id: "<id>"
  resolved: true
```
