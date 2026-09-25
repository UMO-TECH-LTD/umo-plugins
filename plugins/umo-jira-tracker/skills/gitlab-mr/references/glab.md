# glab CLI Reference

## Install

```bash
brew install glab          # macOS
# or download from https://gitlab.com/gitlab-org/cli/-/releases
```

## Authenticate

```bash
glab auth login
# or set environment variable (non-interactive, e.g. CI):
export GITLAB_TOKEN="<your-token-with-api-scope>"
# On macOS put in ~/.zshenv so GUI apps (Cursor) see it
```

Check status:

```bash
glab auth status
```

## Resolve project

From the repo root — `glab` uses the current directory's Git remote by default; no `-R` needed unless operating on another project:

```bash
git remote get-url origin
```

Auto-resolve project ID (store in `.umo/jira-tracker.json` `gitlab.projectId` after first resolution):

```bash
REPO_NAME=$(git remote get-url origin | sed 's/.*\/\([^/]*\)\.git/\1/')
glab api "projects?search=${REPO_NAME}&membership=true" \
  | python3 -c "import json,sys; p=json.load(sys.stdin); [print(x['id'], x['path_with_namespace']) for x in p]"
```

Present the matches to the developer and ask which numeric ID is correct. Persist the choice.

## Check for an existing open MR

```bash
glab mr list --source-branch "<branch-name>"
```

If one exists, show the web URL (`glab mr view <iid> --web`).

## Create MR (non-interactive)

```bash
glab mr create \
  --target-branch "{target-branch}" \
  --source-branch "$(git branch --show-current)" \
  --title "{MR title}" \
  --description "$(cat <<'EOF'
{MR description markdown}
EOF
)" \
  --yes \
  --no-editor
```

Shortcuts:

- **`--fill`** — title/description from commits; use with **`--yes`** to skip prompts.
- **`--fill --fill-commit-body`** — multi-commit bodies in description.

**Avoid** `--fill` if you need a custom template; use `--title` and `--description` instead.

## After creation

```bash
glab mr view --web
# or
glab mr list --source-branch "$(git branch --show-current)"
```

## Phase 8 tooling gate

Phase 8 of `/umo-jira-tracker:mr` needs a working GitLab client. Check it once
before polling:

```bash
command -v glab >/dev/null 2>&1 && glab auth status
```

If `glab` is missing or unauthenticated **and** GitLab MCP is unavailable,
Phase 8 cannot run — report that the MR was created but CI/review must be
watched manually, and end the command. That is a graceful degradation, not an
error to retry.

## Phase 8 budget script (`scripts/phase8-budget.sh`)

Phase 8's loop budget (6 fix→push iterations, 2700s wall clock, 40 polls) is
enforced by a POSIX `sh` script shipped with this skill at
`scripts/phase8-budget.sh`, so the count is not left to the agent's memory.
Zero dependencies (`date`, `mkdir`, `rm`, shell builtins only) — runs under
`dash` and `bash`/`sh` on Linux and macOS.

The loop's poll interval is a flat **180 seconds** between every two checks in
8b and 8c — no backoff, no shorter first pass. CI in this org rarely changes
state faster than that, so a tighter cadence spends wall clock and poll count
re-reading the same `running`. Wait it out in **one** call, backgrounded — a
foreground `sleep` that long is blocked on Claude Code, and chaining shorter
ones is a banned workaround, not a fallback. Step 8b of
`/umo-jira-tracker:mr` has the exact mechanism; follow it rather than
improvising one here.

```bash
sh scripts/phase8-budget.sh reset     {project-id}-{iid}   # FIRST, once per run
sh scripts/phase8-budget.sh poll      {project-id}-{iid}   # every 8b/8c check
sh scripts/phase8-budget.sh iteration {project-id}-{iid}   # BEFORE a fix push
sh scripts/phase8-budget.sh status    {project-id}-{iid}   # read-only report
```

**Step 8a must call `reset` once, unconditionally, before the first `poll`.**
The key is deterministic and the state file outlives the command, so a prior
run of `/umo-jira-tracker:mr` on the same MR would leave an expired clock
behind and the next run's first `poll` would report
`BUDGET EXCEEDED: wall-clock` immediately — a false handoff with no monitoring
at all. Phase 8 is one bounded run per invocation; always start clean.

| Subcommand | Effect | Exit 0 | Exit 1 |
|---|---|---|---|
| `poll` | creates state on first call, increments `polls` | within budget | any limb exceeded |
| `iteration` | increments `iterations` **only** if allowed; never overshoots the cap | fix push permitted | cap or clock already blown — go to Step 8d |
| `status` | reads, never writes | always (even over budget) | — |
| `reset` | deletes the state file | always | — |

### What `status` reports

`status` splits the elapsed clock, so a handoff shows *where* the 45 minutes
went instead of only how many are gone:

```
status | poll 10/40 | elapsed 2520s/2700s | polling 1440s | remediation 900s | since-last 180s | iterations 2/6 | OK
```

- **`polling`** — time in gaps of **≤360s** between two counted calls: one of
  8b/8c's flat 180s sleeps plus the check around it.
- **`remediation`** — time in gaps **>360s**: reading a failed job's log,
  editing the ticket, waiting on a developer's answer, building and pushing a
  fix. The poll counter does not move during any of this, but the clock does.
- **`since-last`** — elapsed minus the two above: the stretch after the last
  `poll`/`iteration`, not yet classified because `status` is read-only and
  never counts as activity itself. It is usually whatever you are doing right
  now.

Quote the whole line in the Step 8d/8e report. `elapsed 2520s` next to `poll
10/40` invites "polling was slow"; the split says plainly that 24 minutes went
on the loop's own sleeps at 180s each and 15 on fixing things, which tells
whoever picks the MR up whether a retry would help.

The 360s cut-off is `POLL_GAP_SECONDS` in the script: one poll interval plus a
full extra interval of slack for the cycle's own overhead — the GitLab call,
the script, and the agent's turn between them. It is **not** 3x the interval
(540s), even though 3x is what the old 30–60s cadence used, because that
overhead is an absolute quantity that does not grow when the sleep does:
scaling the ratio up would buy 360s of slack nothing needs and blind the field
to every remediation block under nine minutes — including the ~6min human wait
and ~10min CI investigation the split exists to surface. Keeping the slack in
the same absolute range as before (120s then, 180s now) rather than scaling it
with the interval keeps a normal poll cycle safely inside `polling` while
leaving the smallest reported remediation block at six minutes. These are report-only counters: they enforce nothing, and no limb of
the budget is measured against them.

### Why `MAX_POLLS=40` looks unreachable

At a flat 180s per poll, the 2700s wall clock allows about **15 polls** before
it exhausts — so on a run that does nothing but poll, `wall-clock` always
trips first and the poll count stops somewhere near 15/40. Any remediation
time makes that fewer still. This is expected, not a mis-set constant:
`MAX_POLLS` is a **backstop**, not the binding limb. It catches the case the
clock cannot — a loop polling far faster than the documented cadence (a
skipped `sleep`, a tight retry around a failing call, a confused agent
re-checking in a burst), where 40 polls can arrive long before 45 minutes do.
Leave it at 40. If a real run ever reports `BUDGET EXCEEDED: polls`, the bug
to look for is a skipped or silently-failed 180s poll wait, not a budget that
is too small.

Exit **2** means the script was called wrong (missing/unknown subcommand or
missing key) — distinct from exit 1, and not a reason to skip the gate. Exit
**3** means the script's *environment* is broken — its state directory or lock
is unusable (unwritable `$TMPDIR`, wedged filesystem). That is neither usage
nor budget: treat it exactly like "the script cannot be located" and fall back
to manual `date +%s` bookkeeping.

State: `${TMPDIR:-/tmp}/umo-phase8/{key}.state`, one file per MR, deliberately
outside the git working tree so it can never be committed. Plain KEY=VALUE
lines: `start_time=` / `iterations=` / `polls=` carry the budget,
`last_activity_at=` / `poll_seconds=` / `remediation_seconds=` carry the
`status` breakdown. The key is sanitized to `[A-Za-z0-9._-]`. Corrupt or
truncated state self-heals into a fresh budget on the next `poll`/`iteration`
— but only the three enforcement fields can trigger that: a damaged or absent
attribution field just falls back to a default, because losing a reporting
counter must never restart a wall clock the loop has already spent.

**Parallel sessions on one machine.** State is isolated per MR key, so
concurrent Phase 8 runs on *different* MRs never interfere — no coordination
needed. On the *same* key, every mutation (`poll`, `iteration`, `reset`) is
serialized by an advisory `mkdir`-based lock at `{key}.lock`, so concurrent
callers cannot lose an increment; `status` is read-only and takes no lock. A
waiter reclaims a lock **only** on the evidence of a valid `acquired_at` stamp
older than 10s — it never breaks a lock on weaker evidence, because "no stamp
written yet" cannot be told apart from a live holder that has not been
scheduled yet, and guessing there evicts live holders under load. So a normal
crash (stamp already written) self-heals within 10s, while a holder killed in
the one statement between `mkdir` and its stamp write leaves a lock nobody
breaks: waiters retry for the configured number of attempts (`LOCK_MAX_TRIES`,
one second apart — roughly half a minute) and then exit 3, and the caller falls back to
manual bookkeeping per the exit-3 contract. That is slower but safe — no
corruption and no false budget claim.
Two sessions on the *same* MR still isn't a supported configuration, though —
whichever reaches Step 8a last resets the shared budget.

Reaching exactly 6 iterations is allowed and still leaves polling open, so the
6th fix's pipeline and review pass are still verified; only a 7th fix push is
refused.

If the script cannot be located (plugin layout differs by host —
`$CLAUDE_PLUGIN_ROOT` is exported for hooks, not guaranteed for a skill's
ad-hoc Bash calls), fall back to manual `date +%s` bookkeeping as described in
Step 8a. That is not a fatal error.

## Poll pipeline status (used by `/umo-jira-tracker:mr` Phase 8b)

**Primary** — native `glab`, no external JSON tooling. `glab` embeds its own
jq engine (gojq), so `--jq` works with no `jq` or `python3` on `PATH`:

```bash
glab ci status --branch "$(git branch --show-current)" --output json --jq '.pipeline.status'
```

The JSON is `{"jobs": [...], "pipeline": {...}}` — status at
`.pipeline.status`, id at `.pipeline.id`. `--output json` is **incompatible
with `--live`, `--wait`, and `--compact`**; never combine them (and
`--live`/`--wait` would block the poll loop anyway). With no pipeline, the
command exits non-zero and prints
`{"error":{"message":"no pipeline found for branch ..."}}` — treat that as
`none`, not as a tooling failure.

**Fallback** (kept deliberately: use it when the installed `glab` predates
`ci status --jq`, or when `ci status --branch` resolves the branch's latest
pipeline while this project's MR uses merge-request / merged-results
pipelines, so the two disagree):

```bash
glab api "projects/{project-id}/merge_requests/{iid}/pipelines"
```

That returns a JSON array, newest first. Use the row whose `sha` equals
`git rev-parse HEAD`, not the first `success`. Note that
`glab api` has **no** `--jq` flag, so this fallback path needs an external
`jq` (`glab api ... | jq -r '.[0].status'`) or `python3` to extract a field,
unlike the primary native-command path above, which needs neither.

Pipeline-level `status` is one of `created`, `waiting_for_resource`,
`preparing`, `pending`, `running`, `success`, `failed`, `canceled`, `skipped`,
`scheduled` (or no pipeline at all, which both snippets above surface as
`none` — an error object from `ci status`, an empty array from `glab api`).
Treat `success` as green; treat `none`/`skipped` as "no CI gate to wait on"
(proceed as if green); treat `failed` as needing the failed-job lookup below;
treat anything still in-flight (`created`/`waiting_for_resource`/`preparing`/
`pending`/`running`/`scheduled`) as "wait one 180s poll interval, then poll
again".
For `canceled`, follow Step 8b's guard exactly: GitLab auto-cancels
a pipeline superseded by a newer push, so a `canceled` entry right after one
of Phase 8's own fix pushes is usually just the stale, superseded run. Re-poll
**once**, one poll interval later, for the pipeline on the current HEAD and
follow *its* status if one exists; only if `canceled` is still the latest
pipeline after that single re-poll is it something a code fix can't resolve —
then stop and report (Step 8d) rather than looping on it.

**Failed job(s) and their logs.** The same `ci status` call already carries
the job list, so no separate `glab api .../jobs` lookup and no JSON parser is
needed:

```bash
glab ci status --branch "$(git branch --show-current)" --output json \
  --jq '.jobs[] | select(.status == "failed") | "\(.id) \(.name) \(.stage)"'
glab ci trace {job-id-or-name}     # accepts a job id or a job name; -p pins a pipeline
```

**Fallback** (older `glab`, or when you already have a pipeline id from the
`glab api` path above):

```bash
glab api "projects/{project-id}/pipelines/{pipeline-id}/jobs?scope[]=failed"
glab ci trace {job-id}
```

## List / reply / resolve MR discussions (used by Phase 8c)

**Primary — native `glab mr note`.**

> **Experimental.** glab's own help says: "This feature is an experiment and
> is not ready for production use. It might be unstable or removed at any
> time." Fall back to the `glab api` calls below if it errors or is gone.

**Identify the review agent first** (once per Phase 8 run). The human-comment
exclusion is unenforceable without knowing which author is the bot, and the
agent self-assigns itself as a *reviewer* per `code-review.md`:

```bash
glab mr view {iid} --output json --jq '.reviewers[].username'
```

Authors in that set are the review agent; **any other author is a human**.
Prefer a bot account name declared in `.umo/jira-tracker.json` when one
exists; otherwise use this reviewers-list heuristic. An empty list means the
agent hasn't self-assigned yet — never guess a username.

```bash
# Unresolved, non-system threads, one line each
glab mr note list {iid} --state unresolved --output json \
  --jq '.[]
        | select(any(.notes[]; .system == false))
        | . as $d
        | [$d.notes[] | select(.system == false)] as $n
        | ($n | max_by(.created_at)) as $newest
        | ([$n[] | .position | select(. != null)] | first) as $pos
        | "id=\($d.id)"
          + " | authors=\([$n[] | .author.username] | unique | join(","))"
          + " | newest=\($newest.created_at)"
          + " | unresolved=\(any($d.notes[]; .resolvable and (.resolved == false)))"
          + " | \($pos.new_path // "general"):\($pos.new_line // "-")"
          + " | \($newest.body)"'

# One thread's full exchange, when you need to judge it
glab mr note list {iid} --output json --jq '.[] | select(.id == "{discussion-id}") | .notes'

# Reply, then resolve — never resolve without replying first
glab mr note create {iid} --reply {discussion-id} -m "{reply text}"
glab mr note resolve {iid} {discussion-id}
```

- The projection deliberately reads the **whole `notes[]` array**, never
  `notes[0]`. `notes[0]` is the note that *opened* the thread, so it hides a
  human who replied to an agent-opened thread (breaking the human-comment
  exclusion), reports the wrong timestamp for the review-freshness check, and
  contradicts the any-resolvable-note resolution rule below. `max_by(.created_at)`
  also makes the "newest note" independent of GitLab's array ordering.
- Pass the **full** `id` to `--reply`/`resolve`. Both accept an 8+ character
  prefix, but prefixes can be ambiguous and then error; keep the short prefix
  for display only.
- Argument order is MR first, discussion second: `resolve {iid} {discussion-id}`.
- Human-readable mode (drop `--output json`) prints an **8-character
  discussion-id prefix** per non-system thread — good for showing a developer.
- Filters: `--state all|resolved|unresolved`, `--type all|general|diff|system`,
  `--file <path>`. `--type` takes one value, so it cannot exclude system notes
  by itself — that's what `select(any(.notes[]; .system == false))` is for. Use
  `--state all` for the freshness check and to tell "agent never posted" from
  "agent posted and everything is resolved"; `--state unresolved` hides the
  agent's newest note when it sits on an already-resolved thread.
- The JSON shape matches the REST discussions payload: each element has `id`,
  `individual_note`, and `notes[]`, and each note has `author.username`,
  `body`, `created_at`, `system`, `resolvable`, `resolved`, and `position`
  (`new_path` / `new_line`) for diff notes.
- `glab mr note list` exposes no paging flag; it matched
  `glab api --paginate`'s thread count on every MR checked, so treat it as
  complete. If you ever doubt it, cross-check with the paginated fallback
  below before declaring zero unresolved threads.
- `--jq` here needs no external `jq`/`python3` either (embedded gojq).

**Fallback — raw API (not experimental; the path to use if `glab mr note`
breaks or is removed in a future `glab`).** Each discussion has an `id` and a
`notes` array; `resolvable` and `resolved` live on each **note**, not on the
discussion itself — a discussion is unresolved when any of its resolvable
notes has `resolved: false`. That rule is authoritative on every path;
`--state unresolved` above is a convenience filter over it.

**`--paginate` is mandatory here.** GitLab returns 20 items per page and an MR
collects a system note per push, so real unresolved review threads drop off
page 1 on a longer Phase 8 run — without it the loop sees "zero unresolved
threads" and converges falsely at Step 8e.

```bash
glab api --paginate "projects/{project-id}/merge_requests/{iid}/discussions"
```

`glab api` has no `--jq`, so filtering here needs an external `jq` or
`python3`. `--paginate` emits one array per page, so slurp them first:
`... | jq -s 'add | map(select(any(.notes[]; .system == false)))'`.

**Reply to a discussion** (always do this before resolving — never resolve
silently; the body may not start a line with `/`, which GitLab reads as a
quick action):

```bash
glab api -X POST "projects/{project-id}/merge_requests/{iid}/discussions/{discussion-id}/notes" \
  -f body="{reply text}"
```

**Resolve (or unresolve) a discussion** — `resolved` is boolean, so pass it
with `-F` (raw/typed field), not `-f` (which sends a string):

```bash
glab api -X PUT "projects/{project-id}/merge_requests/{iid}/discussions/{discussion-id}" \
  -F resolved=true
```

## Troubleshooting

| Issue | What to try |
|-------|-------------|
| `401` / auth | `glab auth login` or set `GITLAB_TOKEN` |
| Wrong project | `glab mr create -R group/subgroup/repo ...` |
| Editor opens | Pass `--description "..."` and `--no-editor` |
| Can't find project | Use numeric ID via `glab api projects?search=<name>` |
