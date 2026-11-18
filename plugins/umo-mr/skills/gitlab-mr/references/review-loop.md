# Review loop — `/mr` Phase 8

Runs on its own right after `/mr` creates or updates an MR. It also runs when
the `umo-mr` hook reports that an MR was created some other way. It ends in
one of two states: **converged**, or a **handoff** that says what is still
red. It never merges, and it never fills the human Approve slot.

## Converged

All of these hold for the **same** commit, the MR's current head SHA:

1. The MR has no merge conflicts.
2. The pipeline whose `sha` is that head SHA has finished `success`. A green
   pipeline on an older SHA does not count.
3. The review agent's summary note was written for that SHA (its stats
   `head_sha`, or its `run <UTC time>` is later than the push) and its
   recommendation is an approve (`APPROVE`, `APPROVE WITH MINOR CHANGES`).
4. Every finding the note lists as open is either fixed in a later push,
   answered in its thread (see Triage), or `Minor` / `Info` with a reply.
   No `Critical` or `Major` finding is left without a fix or a reply.

## Find the review agent

It assigns itself as a reviewer on the MR. Do not add it yourself.

- Summary note: one note whose body starts with `### <name>-mr-reviewer`
  (`saas-mr-reviewer`, `proto-mr-reviewer`, …). The bot rewrites this one note
  on every run. Judge it by the run time inside it and by `updated_at`, not by
  `created_at`.
- Machine-readable block in the same note: `<!-- <name>-mr-reviewer:stats {json} -->`
  with `mr.head_sha`, `review.recommendation` and `findings[]`
  (`key`, `severity`, `status`, `location`). Prefer it to parsing prose.
- Inline findings: resolvable discussions from the bot whose first note starts
  with `[<agent> · Critical|Major|Minor|Info]`.

If no summary note appears within 15 minutes after the pipeline for the head
SHA finished, post one top-level comment whose first line is `/code-review`
as plain text (no code span, not a reply in a thread). GitLab's Re-request
review does not start the bot. Post it once per head SHA.

Not every repo has a review agent. When no bot is among the MR's reviewers
and the MR has never had a `-mr-reviewer` note, the repo has none: drop
conditions 3 and 4, do not post `/code-review`, and say "no review agent on
this repo" in the report.

## One check

Run one check, then wait 180 seconds before the next one. Use `glab` from the
repo root (`:id` is the URL-encoded project path), or the GitLab MCP when
`glab` is not available.

```bash
glab api "projects/:id/merge_requests/<iid>"              # sha, has_conflicts
glab api "projects/:id/merge_requests/<iid>/pipelines"    # keep the row whose sha == head
glab api "projects/:id/merge_requests/<iid>/notes?per_page=100&sort=desc"
glab api "projects/:id/merge_requests/<iid>/discussions?per_page=100"
```

- Pipeline `running` / `pending` / `created`: wait.
- Pipeline `failed`: read the failed jobs (`glab ci trace <job-id>`). Fix a
  cause that this MR introduced. A cause outside the MR (a dead mirror, a
  broken shared runner, a red `main`) is a handoff: report it and do not patch
  around it in this MR.
- Conflicts: rebase the feature branch onto the target and push with
  `--force-with-lease`. Never force-push the target branch.

## Triage each open finding

Check it against the code first. A bot finding can be wrong.

| Severity | Valid | Not valid |
|---|---|---|
| `Critical`, `Major` | Fix it, commit (conventional, same Jira key), push, start a new check. | Reply in its thread with the evidence: file and line, test, decision record. |
| `Minor`, `Info` | Fix it when the fix is small and inside the MR's scope. Otherwise reply with what you did instead (for example, "stated in the MR description"). | Reply with the evidence. |

Rules for threads:

- Reply under the bot's own thread. Do not resolve it and do not edit the
  bot's notes: the bot closes a finding when it no longer reproduces, and the
  human reviewer resolves or waives what is left.
- Do not write in a thread a human has written in. Report it to the developer
  instead.
- Do not start a second summary note.
- One reply per finding per head SHA. Do not repeat a reply that is already
  there.

## Budget and handoff

Stop after 6 fix pushes, 45 minutes, or 40 checks, whichever comes first. A
check without a push still counts toward time and checks. At the budget, or
when the next step needs a human (a product decision, a thread a human wrote
in, a failure outside the MR), hand off.

## Report

End the command with one short report, converged or not:

- MR URL and head SHA.
- Pipeline for that SHA: status and link.
- Review agent: recommendation and run time.
- Each finding: fixed in `<sha>`, answered (one line why), or still open.
- The human reviewer slot: still to be filled by a person who is not the
  author. Say this every time; the loop never replaces it.

## Opt out

Skip this phase only when the developer said so in the request ("just open
the MR", "don't wait for CI"). Then say in the report that CI and the review
agent were not watched.
