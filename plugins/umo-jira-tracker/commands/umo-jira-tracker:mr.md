---
description: End-to-end MR workflow — parse intent, auto-choose branch via protected + open-MR heuristic, commit changes, push and create a GitLab MR immediately, sync JIRA, then offer to watch CI and the review agent and fix valid findings until both are clean (Phase 8, opt-in per MR) before reporting the command done. Uses glab (preferred) or GitLab MCP. The JIRA Task key is mandatory in both the branch and the MR title. Ported from the UMO saas repo /mr workflow.
---

# /umo-jira-tracker:mr

## Naming standard

- **Branch format:** `{type}/{JIRA-KEY}-{short-description}` — short-description is 2–5 words in kebab-case. (e.g. `feat/PAY-1234-add-kafka-retry`)
- **MR title format:** `{type}(scope): lowercase imperative subject (JIRA-KEY)` — Conventional Commits with the JIRA key in parentheses at the **end**, which keeps the title commitlint-safe. (e.g. `feat(publisher): add kafka retry (PAY-1234)`)

The scope is optional; the type and the trailing key are not.

## The merge gate — why the key is mandatory

**No MR merges without a JIRA Task, and the merge commit references the task.**
This is an org-level backstop, and it is load-bearing in two directions:

- It is what makes bead-to-Jira promotion automatic. Decompose freely in Beads;
  anything that ends in a merge acquires a Jira Task by definition, so nobody has
  to make a judgment call about when a step became a unit of delivery.
- It is what the **merged-PR automation keys off**. The automation flips the Task
  to `Done` when the MR merges, reading the key from the branch and title. A CI
  check fails an MR whose title carries no valid key.

So this command does **not** proceed without a key. If none can be resolved, help
the developer create or find the Task rather than working around it — see
Phase 1c.

For MR creation internals (glab flags, GitLab MCP call), use the `gitlab-mr` skill from your skills list.

---

# Create Merge Request

## Overview

End-to-end MR workflow: parse intent from natural language, manage branches, organize changes into logical conventional commits, **push and create a GitLab MR immediately**, and sync JIRA. Do **not** wait for a commit-plan or MR-preview approval — the developer's request is the approval. JIRA mutations still require explicit approval (Phase 7).

**MR creation need not be the finish line.** After the MR is opened this command *offers* to keep going — see **Phase 8**, which is opt-in per MR while it is still being validated. If the developer accepts, it watches the pipeline and the review agent, fixes what is genuinely wrong, and only reports the task complete once the latest pipeline is green and the review agent has no unresolved comments left (or the iteration/time budget in Phase 8 runs out first, in which case it hands off with a status report instead of claiming done). If they decline, the command ends at the created MR and says so.

## Phase 1: Parse Input and Clarify

### Step 1a — Detect active bead

Before parsing user input, check for a currently claimed bead:

```bash
bd claimed --json 2>/dev/null
# fallback if 'claimed' subcommand is not available:
bd list --status in-progress --json 2>/dev/null
```

If a claimed bead is found, extract its JIRA key from the `jira:` label (e.g. label `jira:PAY-1234` → key `PAY-1234`). Treat this as the **candidate JIRA key**.

### Step 1b — Reconcile with user input

Extract the following from the user's free-form input. Ask only when a value is truly ambiguous.

| Parameter | How to detect | Default |
|-----------|---------------|---------|
| **JIRA key** | Regex `[A-Z]+-\d+` in input (e.g. `PAY-1234`) | Candidate from active bead (step 1a) |
| **Branch strategy** | Explicit keywords: "current branch", "new branch", "rename branch"; otherwise | **Auto** (Phase 2 heuristic) |
| **Target branch** | Keywords: "target dev", "target main", "into develop" | `dev` (from `.umo/jira-tracker.json` `gitlab.targetBranch`) |
| **MR dependency** | Phrases like "depends on !1234", "after !1234 merges", "blocked by !1234" | None — see Phase 6.5 |
| **Additional context** | Anything else the developer wrote | None |

**JIRA key reconciliation rules:**

- User provided a key **and** it matches the active bead → use it, no confirmation needed.
- User provided a key **different** from the active bead's key → show both and ask:
  ```
  Active bead: [PAY-1234] {bead title}
  You mentioned: PAY-9999
  Which JIRA Task should this MR be linked to? (PAY-1234 / PAY-9999)
  ```
- No key in user input, active bead found → use the bead key and report it post-fact (no yes/no gate).
- No key in user input, no active bead → go to **Step 1c**.

Do **not** ask "new vs current vs rename" on empty input. Do not ask for target branch when config/default applies. The Task is the one thing worth stopping for — see Step 1c.

### Step 1c — No JIRA key resolved

Do not proceed. The MR cannot merge without a Task, and a CI check will fail the
title regardless, so continuing here only produces an MR that has to be renamed.

```
This MR needs a JIRA Task — no MR merges without one, and the merge commit
references it. The merged-PR automation also reads the key from the branch and
title to flip the Task to Done.

  1. Give me the key, if the Task already exists.
  2. Create one now:
     /umo-jira-tracker:create task --parent <SLICE-KEY> --title "..."
  3. If this is tech debt with no obvious home, its home is your squad's
     standing tech-health slice [TH-<KEY>-S0].

Which?
```

If the developer insists on an MR with no key, say plainly that it will fail the
CI title check and will not merge, and stop. Do not build a keyless branch name
or title.

## Phase 2: Branch Setup

### Resolve current branch and target

```bash
git branch --show-current
```

Store as `{current-branch}`. Target is `{target-branch}` from Phase 1 / `.umo/jira-tracker.json` (default `dev`).

### Branch heuristic (no asking)

Explicit developer overrides always win when clear ("use current branch", "rename …", "create new branch").

Otherwise, decide automatically:

1. **Protected / target branch** — if `{current-branch}` equals `{target-branch}`, or is `main`, `master`, or `dev`:
   - Warn briefly: feature work should be on a separate branch.
   - **Always create a new branch** (see below). Do not ask for confirmation. Do not stay on the protected branch unless the developer explicitly overrides.

2. **Otherwise** — treat `{current-branch}` as the developer's feature branch. Detect open MRs (**glab preferred**, GitLab MCP fallback):

```bash
glab mr list --source-branch "{current-branch}"
```

If `glab` is unavailable, use GitLab MCP:

```
CallMcpTool -> gitlab / search
  scope: "merge_requests"
  search: "{current-branch}"
  project_id: "{gitlab-project-id}"
  state: "opened"
```

- **No open MR** for this source branch → **reuse** `{current-branch}` (developer-created feature branch).
- **Open MR exists** → **reuse** `{current-branch}`; show the MR URL; push and update that MR path — do **not** create a second branch or a duplicate MR.

If neither tool is available and the branch is not protected: reuse `{current-branch}` and mention `glab mr list` after auth.

### Create new branch (when heuristic says create)

Naming convention: `{type}/{JIRA-KEY}-{short-description}` (short-description: 2–5 words, kebab-case)

Available types: `feat`, `fix`, `hotfix`, `chore`, `refactor`, `test`, `docs`, `ci`, `perf`, `build`

- The JIRA key is mandatory: `feat/PAY-1234-add-kafka-retry`
- Multiple JIRA keys: `feat/PAY-1234-PAY-1235-login-refactor`
- Derive `{short-description}` from the JIRA summary (if fetched in Phase 3) or from the diff, stripping the slice coordinate prefix — it is already carried by the key. Do **not** stop to confirm the branch name.

```bash
git checkout -b {branch-name}
```

### Rename current branch (only when the developer explicitly asks)

```bash
git branch -m {old-name} {new-name}
```

## Phase 3: Fetch JIRA Context

The key is mandatory by now (Phase 1c). If the Atlassian MCP is available:

1. Get the cloud ID (once per session):

```
CallMcpTool -> Atlassian / getAccessibleAtlassianResources
```

2. Fetch the ticket:

```
CallMcpTool -> Atlassian / getJiraIssue
  cloudId: "{cloudId}"
  issueIdOrKey: "{JIRA-KEY}"
```

3. Extract and store for later use:
   - **Summary** (for the MR title and branch name — drop the slice coordinate prefix)
   - **Description** (for "What this MR does?" and "Why?")
   - **Acceptance criteria** (for "How to Test")
   - **Type** (Task or Bug — drives the branch type prefix)
   - **Parent Slice key and summary** (for the MR description's JIRA Task line)

Check the type while you are here. If the key resolves to a **Slice**, **Flow** or **Request**, stop and say so: an MR delivers a Task or fixes a Bug, and linking it to a container would put the wrong thing in front of the merged-PR automation.

If the Atlassian MCP is unavailable, continue with the key the developer gave — the branch and title still carry it, which is what CI and the automation need. Build the description from commit messages and developer input instead.

Also check the currently claimed bead for context (Notes, Refined AC) to enrich the MR description.

## Phase 4: Commit Changes

```bash
git status
```

- **If working tree is clean:** skip to the divergence check at the end of this phase (commits already exist on the branch).
- **If there are uncommitted changes:** follow Steps 4.1–4.5 below to create well-structured commits.

### Step 4.1: Analyze Changes

Gather information about all uncommitted work:

```bash
git status
git log --oneline -10
git diff HEAD
```

Read the content of each changed file to understand what was implemented.

### Step 4.2: Categorize Changes by Topic

Group related changes into logical commits. Consider:

- **By feature**: All files related to a single feature together
- **By layer**: Sometimes separating domain/service/infra makes sense
- **By type**: Tests separate from implementation, docs separate from code
- **Dependencies first**: Config/dependency changes before code that uses them

Each commit must be:
- **Atomic**: Can be reverted independently
- **Buildable**: Code compiles/runs after this commit
- **Logical**: Changes belong together conceptually

### Step 4.3: Plan Commits Internally

For each commit, determine:

| Attribute | Description |
|-----------|-------------|
| **Type** | `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert` |
| **Scope** | Optional — affected area (e.g., `auth`, `api`, `config`) |
| **Breaking** | Does it break backward compatibility? Add `!` if yes |
| **Description** | Imperative mood, concise summary |
| **Files** | List of files to include in this commit |
| **Order** | Sequence matters — dependencies before dependents |

Do **not** present a commit plan and wait for "yes/no/adjust". Plan silently, then execute in Step 4.4.

For multi-line commit messages, use heredoc syntax:

```bash
git commit -m "$(cat <<'EOF'
feat(auth): add user authentication service

Implement JWT-based authentication with refresh token support.

Closes: #123
EOF
)"
```

**Later adjustment** — only if the developer asks after commits exist:

- **"merge 2 and 3"** — combine commits
- **"split commit 2"** — break into smaller commits
- **"change type of commit 1 to chore"** — modify commit type
- **"add file X to commit 2"** — reassign files
- **"reorder: 2, 1, 3"** — change commit sequence

### Step 4.4: Execute Commits Immediately

For each planned commit, in order:

1. **Stage specific files:**
   ```bash
   git add <file1> <file2> ...
   ```

2. **Create commit with conventional message:**
   ```bash
   git commit -m "type(scope): description"
   ```

3. **Verify before proceeding to next:**
   ```bash
   git log -1 --stat
   ```

4. **Report progress (post-fact, not a gate):**
   ```
   Commit 1/N created: feat(auth): add user authentication service
   Commit 2/N created: feat(api): add login and logout endpoints
   ...
   ```

### Step 4.5: Post-commit Verification

After all commits are created (or if the working tree was already clean), verify the branch has diverged from the target:

```bash
git log {target-branch}..HEAD --oneline
```

If there are zero commits ahead of the target, warn the developer: "No commits to include in the MR. Aborting." and stop.

### Commit Message Reference

| Type | When to Use |
|------|-------------|
| `feat` | New feature for users |
| `fix` | Bug fix for users |
| `docs` | Documentation only |
| `style` | Formatting, whitespace |
| `refactor` | Code restructuring, no behavior change |
| `perf` | Performance improvement |
| `test` | Adding/fixing tests |
| `build` | Build system, dependencies |
| `ci` | CI/CD configuration |
| `chore` | Maintenance, tooling |
| `revert` | Reverting previous commit |

- **Description**: Imperative mood ("add" not "added"), lowercase, no period
- **Body**: Explain motivation and context, wrap at 72 characters
- **Breaking changes**: Add `!` after type/scope (`feat(api)!: change response format`) or footer (`BREAKING CHANGE: description`)

## Phase 5: Push

Build MR title and description internally (see templates below), then **push immediately** — do not wait for preview approval.

```bash
git push -u origin HEAD
```

Report branch and draft title briefly after push (informational only).

## Phase 6: Create MR

Use this order:

1. **GitLab MCP** (when available and working) — see the `gitlab-mr` skill → `references/mcp.md`
2. **`glab` CLI** (when MCP is unavailable or fails) — see the `gitlab-mr` skill from your skills list
3. **Manual** — copy title and description into the GitLab UI

If an open MR already exists for the source branch (Phase 2), do not create a duplicate — push updates and report the existing URL (update description via GitLab tools only when needed).

### Resolve project ID

If `gitlab.projectId` is null in `.umo/jira-tracker.json`, resolve it now:

```bash
REPO_NAME=$(git remote get-url origin | sed 's/.*\/\([^/]*\)\.git/\1/')
glab api "projects?search=${REPO_NAME}&membership=true" \
  | python3 -c "import json,sys; p=json.load(sys.stdin); [print(x['id'], x['path_with_namespace']) for x in p]"
```

If multiple matches, pick the one matching the remote path; if still ambiguous, ask once. Persist the numeric ID to `.umo/jira-tracker.json` `gitlab.projectId`.

### With GitLab MCP

Read `user.gitlabUserId` from `.umo/jira-tracker.json`. Include `assignee_ids` if set:

```
CallMcpTool -> gitlab / create_merge_request
  id: "{gitlab-project-id}"
  title: "{MR title}"
  source_branch: "{source-branch}"
  target_branch: "{target-branch}"
  description: "{MR description}"
  assignee_ids: ["{user.gitlabUserId}"]   // omit if null in config
```

Report the MR URL to the developer on success.

### With glab (fallback when MCP is unavailable)

Run from the **repository root** (where `origin` points at the GitLab project). Read the `gitlab-mr` skill (from your skills list) for full flags and troubleshooting.

**Non-interactive create** (after push):

Read `user.gitlabUserId` from `.umo/jira-tracker.json`. If set, add `--assignee`:

```bash
glab mr create \
  --target-branch "{target-branch}" \
  --source-branch "{source-branch}" \
  --title "{MR title}" \
  --description "{MR description markdown}" \
  --assignee "{user.gitlabUsername}" \
  --yes \
  --no-editor
```

Omit `--assignee` if `user.gitlabUsername` is null in config.

On success, print the MR URL (`glab mr view` or the command output).

### Without GitLab MCP or glab

Output the MR title and description as a copyable markdown block so the developer can create the MR manually in the GitLab UI.

## Phase 6.5: Set Merge-Request Dependencies (if this MR must not merge before another)

Some changes ship as several MRs — often across several services — that must merge
in a specific order (a schema-then-consumer chain, a producer-before-reader
migration). GitLab can enforce that order directly: a merge request with a
**blocking merge request dependency** cannot be merged until its blocker merges.
Set this whenever an order actually matters — do not ask on every MR.

**Skip dependency detection (Steps 6.5a-6.5c) — no questions, no API calls —
when** Step 6.5a finds nothing explicit or bd-labeled, and Step 6.5b's diff is
single-unit (see below). Most MRs are independent; the point is to catch the
risky multi-service case, not to interrogate every MR. Step 6.5d is not part
of this skip — it runs independently (see below) so that even an MR with no
blockers of its own becomes discoverable by whatever depends on it later.

### Step 6.5a — Collect dependency candidates, in priority order

Stop at the first level that produces a result — do not also check lower
levels once one has answered:

1. **Explicit (works with no bead and no JIRA linkage — always take this
   first)**: the developer's/orchestrator's own input to *this* invocation
   named a blocker (see the **MR dependency** row in Phase 1b, e.g. "depends
   on !1234", "after !1234 merges"). Extract the referenced IID(s), treat them
   as confirmed, and skip straight to Step 6.5c — do not run 6.5a.2, 6.5a.3, or
   the 6.5b nudge.
2. **Bead blocker labels** (only when Phase 1a found an active bead): run
   `bd show <bead-id> --json` and take its still-open "blocked by"
   dependencies. For each blocker bead, check whether it already carries a
   `gitlab-mr:<iid>` label (`bd show <blocker-id> --json`) — the label a
   previous run of this command left on it in Step 6.5d. A label names that
   blocker's MR IID. Found labels are confirmed; skip the 6.5b nudge.
3. **JIRA delivery history** (only when neither of the above found anything,
   and the Atlassian MCP is available): re-read the JIRA Task description
   fetched in Phase 3 for prior "MR delivery" entries this command appended in
   earlier runs (Phase 7, Operation C). Collect any MR references found there
   as **candidates** only — never apply them without confirmation in 6.5b (if
   6.5b does not run — single-unit diff — these candidates are simply
   dropped; sharing a JIRA key does not by itself imply merge order, so do not
   apply them any other way).

### Step 6.5b — the multi-service nudge

If Step 6.5a found nothing confirmed, check whether the diff spans more than
one **unit** — a top-level repo directory that contains changed source,
ignoring root-level files with no directory and conventionally non-code dirs
(`docs/`, `.github/`, etc.) — except that in a monorepo where everything lives
under one shared root (e.g. `saas`'s `services/`), the unit is the first two
path segments (`services/<name>`) instead of just the root:

```bash
git diff {target-branch}..HEAD --name-only
```

If it spans more than one unit, ask once, before applying anything:

```
This MR touches N services ({list}). Does it depend on another MR that must merge
first? If so, give me its !iid so I can set a GitLab merge request dependency.
```

If Step 6.5a.3 produced JIRA-history candidates, list them in this same
question instead of asking blind. A single-unit diff with nothing confirmed in
6.5a skips this question entirely.

No answer, or the developer says there is no dependency → proceed with none,
skip Step 6.5c and 6.5d.

### Step 6.5c — apply

The MR from Phase 6 already exists (this phase runs after it). For each
confirmed blocking IID:

1. Resolve the **blocker's** global `id` (not its `iid` — the dependent side of
   the relation is addressed by `iid` in the URL path, so only the blocker's
   `id` is needed):

   ```bash
   glab api "projects/{project-id}/merge_requests/{blocker-iid}" \
     | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])"
   ```

2. Create the block relation (the new MR is blocked by the other), addressing
   the new MR by its own `iid` in the path:

   ```bash
   glab api -X POST "projects/{project-id}/merge_requests/{new-iid}/blocks?blocking_merge_request_id={blocker-global-id}"
   ```

   **`blocking_merge_request_id` takes the blocker's numeric `id` field, not
   its `iid`.** Passing the `iid` returns a misleading `403 Lacking
   permissions to the blocking merge request` even when you have full access —
   that 403 means "wrong id shape", not "no permission". See the `gitlab-mr`
   skill's dependency reference for tier requirements and cross-project
   behavior; a genuine tier-related 403 means the project can't create this
   relation at all — say so plainly and stop, do not silently skip. Same if
   `glab` is unavailable: report the intended dependency (`!{new-iid} should
   be blocked by !{blocker-iid}`) and stop — do not silently drop it, since
   GitLab MCP has no equivalent tool for this relation today.
   Manual fallback in either case: ask the developer to set the dependency by
   hand and mark the MR **Draft** themselves (this command never toggles
   Draft) — see the convention this mirrors in
   `repos/saas/.cursor/skills/compliance-skills/implement-loop/reference/risky-changes.md`
   (path relative to the `sdlc-control-plane` meta-repo root; describe the
   same convention inline if working outside that checkout). That convention
   pairs Draft with the same GitLab dependency this step sets — Draft is what
   the developer adds on top, not a substitute for it.

3. Report each dependency set plainly: `!{new-iid} now blocked by
   !{blocker-iid} — GitLab will refuse to merge it first.`

See the `gitlab-mr` skill's dependency reference for the read-back call
(`GET .../blocks`) and its limits.

### Step 6.5d — record for future dependents

Runs unconditionally whenever an MR was created in Phase 6 and a bead is
active in Phase 1a — regardless of whether 6.5a-6.5c found or set any
dependency. A first-in-chain MR has no blockers of its own, but it still needs
to be discoverable once something else depends on *it*; skip this step and
that discovery never happens. Label the active bead:

```bash
bd label add <bead-id> gitlab-mr:{new-iid}
```

No active bead → nothing to record here; the JIRA "MR delivery" trail this
command already writes in Phase 7 is the fallback record the next run's Step
6.5a.3 will read.

## Phase 7: JIRA Update (requires approval)

Execute when the Atlassian MCP is available.

> **Do not transition the JIRA Task.** Two reasons, each sufficient on its own. Creating an MR does not mean the work is finished — the developer may open several MRs for one Task. And **Task Done belongs to the merged-PR automation**, which fires on merge and reads the key from the branch and title; transitioning from here would race it and claim a state this command has not verified. `/umo-jira-tracker:close` handles the explicit case.

Delegate to the `jira-sync-back` skill `/mr` complete flow, which performs:

1. **Operation A — Comment**: post an MR-created comment to the JIRA ticket.

   Draft:
   ```markdown
   MR created: {MR_URL}

   ### Changes
   - {commit message 1}
   - {commit message 2}
   ```

2. **Operation C — Description update**: append (or extend) the MR delivery section in the JIRA ticket description with the MR URL, branch, one-line summary, and commit list.

Both previews are shown together before any action. Developer can approve both, approve individually, or skip either.

If the developer declines the JIRA update entirely, skip it.

## Phase 8: Wait for Review & CI, Converge

**Phase 8 is opt-in — ask first (Step 8·ask), and run it only on a clear yes.**
Once the developer has opted in, the command is not finished when Phase 6
created the MR: do not report
this task complete, and do not hand control back to the developer as "done",
until Step 8e's convergence condition holds — or Step 8d fires first (budget
exhausted, or the loop hits a state no further push can resolve), which ends
the command in a reported handoff instead of a claimed completion. This is a
change from Phases 1–7: those run once; Phase 8 is a poll-fix-repeat loop.

**What "done" means here** — both, true at the same time, on the current HEAD:

1. The MR's latest pipeline is green, or gate-less per Step 8b (no failed
   required jobs, and not merely absent because it hasn't been created yet).
2. The review agent (the bot that self-assigns itself as reviewer on the MR,
   per this org's MR-approval procedure — `engineering/ship/code-review.md` in
   the `sdlc-control-plane` meta-repo, or the equivalent doc in whatever repo
   this MR lives in) has left **zero unresolved discussion threads**.

This loop only fills the automated half of `MR-APPROVALS`. It never waits for
or substitutes the **human** Approve slot — that stays a person's job. Do not
merge the MR from this command.

### Step 8·ask — Offer Phase 8 (run this before Step 8·0)

Phase 8 is new and still being validated in real use, so it does not start on
its own. Ask the developer, in conversation, and wait for the answer:

```
MR is up: {MR_URL}

I can keep going from here: watch the pipeline and the review agent, fix what
is genuinely wrong, and only call this done once CI is green and the review
agent has no unresolved threads (Phase 8 — up to 6 fix pushes, 45 minutes,
checking every 3 minutes). Or I stop here and you take CI and review yourself.

Phase 8 is new, so it's opt-in for now. Enable it for this MR?
```

- **Clear yes** → go to Step 8·0 and continue exactly as documented.
- **No, or anything that isn't a clear yes** — "not now", "later", a question,
  a change of subject, silence, an answer you are not sure about → **skip
  Phase 8 entirely.** Do not run Step 8·0's tooling check, do not poll once
  "just to see", do not re-ask. Report as in Step 8·skip and end the command.

Never assume yes. This is the one gate in the command where a non-answer means
no: the rest of `/umo-jira-tracker:mr` treats the developer's original request
as its approval, but that request predates this offer and cannot consent to a
45-minute loop that pushes code on their behalf.

Ask once. If the developer opts out here and then asks for CI watching later
in the same session, that request *is* the yes — start at Step 8·0.

### Step 8·skip — Developer declined Phase 8

Report this and end the command. Same shape as the no-tooling path in Step 8·0
below, with the reason changed:

- The MR **was created successfully** in Phase 6 — repeat its web URL. That
  part of this command's job is done, and Phases 1–7 succeeded as reported.
- Phase 8 monitoring was **skipped at the developer's request** — not because
  tooling was missing, and not because anything failed.
- They watch CI and the review agent themselves in the GitLab UI, and the
  human Approve slot of `MR-APPROVALS` is outstanding as always.
- Re-running `/umo-jira-tracker:mr` is not how to start it later — just ask.

This is a normal, successful outcome of the command. Do not present it as a
failure, a degradation, or a warning, and do not editorialise about the
developer's choice.

### Step 8·0 — Tooling gate (run this before Step 8a)

Only reached once the developer has opted in at Step 8·ask. Phase 8 needs a
working GitLab client — check once, up front:

```bash
command -v glab >/dev/null 2>&1 && glab auth status
```

- **`glab` present and authenticated** → use the `glab` commands in 8b/8c.
- **`glab` missing or unauthenticated, but GitLab MCP is available** → use the
  MCP calls in `references/mcp.md` for every poll in this phase instead.
- **Neither** → Phase 8 cannot run. Do **not** error out, hang, or retry.
  Report the following and end the command there:
  - The MR **was created successfully** in Phase 6 — repeat its web URL. That
    part of this command's job is done.
  - Phase 8's automated CI/review monitoring cannot run, because no GitLab
    tooling is available (`glab` not installed or not authenticated, GitLab
    MCP not configured).
  - The developer needs to watch CI and the review agent manually in the
    GitLab UI, and the human Approve slot of `MR-APPROVALS` is outstanding as
    always.
  - How to enable this next time: `glab auth login` or set `GITLAB_TOKEN`
    (see the `gitlab-mr` skill → `references/glab.md`), or configure GitLab
    MCP (`references/mcp.md`).

This is an expected degradation path, not a crash: Phases 1–7 succeeded and
are reported as such.

### Step 8a — Set a budget

The budget is **6 fix→push iterations, 45 minutes (2700s) of wall-clock time,
or 40 total polls — whichever comes first.** An "iteration" is one push of a
code fix in response to something found in 8b or 8c; pure re-polls with no
push don't count as an iteration, but the wall-clock and poll-count limbs keep
running through them regardless. Every check in 8b or 8c is a poll, pushed or
not. Hitting any limb routes to Step 8d, not to a silent retry.

<!-- These three numbers are also hard-coded as MAX_ITERATIONS / MAX_SECONDS /
MAX_POLLS in skills/gitlab-mr/scripts/phase8-budget.sh, which carries a
matching comment pointing back at this section. Change one, change the other. -->

**Preferred: let `phase8-budget.sh` keep the count.** It ships with this
plugin at `skills/gitlab-mr/scripts/phase8-budget.sh`. Locate it once:

```bash
# 1. If the host exports a plugin root, it's under there:
ls "$CLAUDE_PLUGIN_ROOT/skills/gitlab-mr/scripts/phase8-budget.sh"
# 2. Otherwise: it ships alongside this command inside the same plugin, so use
#    the plugin/skill directory you loaded this command and the gitlab-mr skill
#    from — <plugin-root>/skills/gitlab-mr/scripts/phase8-budget.sh — or find
#    it by name in your plugin/skill file listing.
```

`$CLAUDE_PLUGIN_ROOT` is set for *hook* invocations and is not guaranteed for
ad-hoc Bash calls made while executing a skill, so treat method 1 as a
shortcut, not a requirement.

Call the resolved path `{budget}`, and use `{project-id}-{iid}` (both already
resolved in Phase 6) as `{key}` — the script sanitizes the key to
`[A-Za-z0-9._-]`, so a path-style project id works too; just use the *same*
key for every call in this run:

```bash
sh {budget} reset     {project-id}-{iid}   # FIRST, once — see below
sh {budget} poll      {project-id}-{iid}   # every 8b/8c check, pushed or not
sh {budget} iteration {project-id}-{iid}   # BEFORE pushing a fix — the gate
sh {budget} status    {project-id}-{iid}   # read-only; 8d/8e report + time split
```

**Call `reset` once, unconditionally, here — before the first `poll`.** The
key is deterministic and the state file outlives the command (days on macOS,
until reboot on Linux), so a *previous* run of `/umo-jira-tracker:mr` on this
same MR would otherwise leave a state file whose clock is long expired, and
your very first `poll` would report `BUDGET EXCEEDED: wall-clock` and send
Phase 8 straight to a false handoff without ever monitoring this run's CI or
review. Phase 8 is one bounded run per invocation, so always start it clean —
do not try to distinguish "resuming" from "starting fresh".

Exit codes: **`0`** = within budget, carry on. **`1`** = `BUDGET EXCEEDED` →
go to Step 8d now. **`2`** = you called the script wrong (bad or missing
argument) — fix the call; this is *not* budget exhaustion, and it is not a
reason to skip the gate. **`3`** = the script's *environment* is broken (its
state directory or lock is unusable, e.g. an unwritable `$TMPDIR`) — neither
usage nor budget: treat it exactly like "the script cannot be located" and use
the manual fallback below. Echo the line each call prints (e.g. `poll
7/40 | elapsed 1200s/2700s | iterations 1/6 | OK`) so the developer can see the
count.

**Never narrate elapsed time from a `poll` line alone.** `poll 10/40 | elapsed
2520s/2700s` invites the reading "polling has eaten 42 of my 45 minutes",
which is almost always false: the clock also covers reading job logs, editing
the ticket, waiting on a developer's answer and pushing fixes — during all of
which the poll counter does not move. `status` is the subcommand that
separates them:

```
status | poll 10/40 | elapsed 2520s/2700s | polling 1440s | remediation 900s | since-last 180s | iterations 2/6 | OK
```

`polling` is the loop's own sleep-and-check gaps (≤360s each — one 180s sleep
plus overhead), `remediation` is the long gaps where you were off doing
something else, `since-last` is the stretch after your last counted call. So
that line says: 24 minutes in the loop's own sleeps, 15 fixing things, 3 since
the last check. Whenever you tell the developer how much of the budget is
gone — mid-loop or in the 8d/8e report — take the numbers from `status`, not
from a `poll` line, and give them the split. It is report-only: no limb of the
budget is measured against these counters.

At a flat 180s per poll the clock, not the poll count, is what runs out: 2700s
allows about **15 polls**, so expect to reach Step 8d somewhere around
`poll 15/40`. Seeing `poll 15/40` next to an exhausted clock is normal and
does not mean you under-polled — `MAX_POLLS=40` is a backstop for a loop that
skips its `sleep`, not a target to reach.

State lives in `${TMPDIR:-/tmp}/umo-phase8/`, one file per MR key, outside the
git tree. Because it is keyed per MR, concurrent Phase 8 runs on **different**
MRs on the same machine never interfere. Mutations on the same key are
serialized by an advisory lock, so two sessions on the same MR cannot corrupt
each other's counters or lose an increment — but note that two sessions on the
*same* MR is not a supported configuration: whichever one reaches Step 8a last
resets the shared budget. Both remain bounded; the counts just won't mean what
a single run's would. If the lock itself is unusable the script exits `3`, and
you fall back to manual bookkeeping — it never proceeds unsynchronized.

`iteration` refuses with exit 1 *without* incrementing when the iteration cap
is already reached or the clock is already blown, so the counter can never
overshoot 6. Reaching exactly 6 is allowed and still leaves polling open — the
6th fix's pipeline and review pass still get verified; only a *7th* fix is
refused.

**Fallback if the script cannot be located or run** (any reason at all — the
deployment's plugin layout doesn't resolve to a path you can find, no shell
available, or it exits `3`): this is not fatal. Fall back to manual
bookkeeping — capture the
current epoch time (`date +%s`) as `{start-time}` before the first poll, then
check `date +%s` against `{start-time}` on every poll, not only after a push,
and keep the iteration and poll counts yourself. Say out loud which poll
number you're on each time (e.g. "poll 7/40"). On this path nothing enforces
the wall clock except you actually calling `date +%s` and comparing it
correctly every time; the poll count is the backstop, since it stays accurate
just by counting your own tool calls in this phase. Hitting 40 polls routes to
Step 8d exactly like hitting the iteration or time limit.

**This is not a one-time check.** Do not treat this budget as background
context to remember — re-check it at every single point in 8b and 8c that is
about to start a new iteration or take another poll, *before* acting, not
after: one `poll` call per check, one `iteration` call before every fix push
(or the equivalent manual check on the fallback path). Both 8b and 8c below
carry an explicit "check 8a first" reminder at
each such point for exactly this reason: each individual fix along the way
will look worth doing in isolation (that's what makes this loop attractive to
keep running), so the gate has to be checked proactively before committing to
iteration N+1 or the next poll, not discovered retroactively after already
doing it.

### Step 8b — Poll the pipeline

**The poll interval is a flat 180 seconds.** Between every two checks in 8b
and 8c, without exception.

No shorter first interval, no backoff, no adaptive tightening when something
looks nearly done — a fixed three minutes, every cycle. CI in this org is slow
enough that a faster cadence just wakes you up to read the same `running` you
read last time, burning wall clock and poll count on nothing.

<a id="poll-wait"></a>
**How to actually wait.** Run the wait as a single one-shot **backgrounded**
sleep — on Claude Code, the Bash tool with `run_in_background: true` (on
Cursor, the terminal-command tool's `is_background: true` does the same):

```bash
sleep 180
```

A backgrounded call returns immediately — that is not the wait finishing.
**Do not run the next `poll`, or any other Phase 8 tool call, until the
completion notification for that `sleep` actually arrives.** Returning to work
on the same turn spends none of the interval and puts your next poll seconds
after the last one, which is the failure this whole section exists to prevent.

Two things will not work, and one of them is a trap:

- **Do not foreground it.** On Claude Code a long leading `sleep` is blocked
  outright by the Bash tool: `sleep 180` on its own, without
  `run_in_background`, does not run — so a wait you *believe* happened did
  not.
- **Do not chain shorter sleeps** to add up to 180s once the foreground call
  is refused. That is the obvious improvisation and it is explicitly a banned
  workaround, not a fix. A blocked `sleep` is never permission to poll faster,
  and "the sleep wouldn't run" is not a reason the cadence changed.

On any other host, if a one-shot backgrounded wait isn't available, use that
host's equivalent wait mechanism: the requirement is a fixed 180 seconds of
*not polling*, in one wait, not the `sleep` builtin specifically.

This is the only interval in Phase 8. Everywhere below that says "wait one
poll interval", "check again", or "re-poll", it means exactly this — 180
seconds, waited the way described just above.

See `gitlab-mr` skill → `references/glab.md` / `references/mcp.md` for the
exact calls, including the fallbacks. Every check here is a poll — run
`sh {budget} poll {project-id}-{iid}` (Step 8a) first, and stop for Step 8d if
it exits 1. Primary command:

```bash
glab ci status --branch "$(git branch --show-current)" --output json --jq '.pipeline.status'
```

`glab` embeds its own jq engine, so `--jq` needs **no** external `jq` or
`python3`. The JSON is `{"jobs": [...], "pipeline": {...}}` — the pipeline
status is `.pipeline.status`, its id `.pipeline.id`. Never combine
`--output json` with `--live`, `--wait`, or `--compact`; they are documented as
incompatible (and `--live`/`--wait` would block this loop anyway).

When no pipeline exists, `glab ci status` exits non-zero and prints
`{"error":{"message":"no pipeline found for branch ..."}}` — treat that as
`none` below, not as a tooling failure.

Fallback (older `glab` without `ci status --jq`, or a status that disagrees
with the MR page because this project uses merge-request/merged-results
pipelines rather than branch pipelines): the raw
`glab api "projects/{project-id}/merge_requests/{iid}/pipelines"` path in
`references/glab.md`. Or with GitLab MCP: `get_merge_request` with
`include: ["pipelines"]` (`url` or `project_id` + `merge_request_iid`).

- **No pipeline at all** (`none`) — the **no-CI-configured check**, distinct
  from 8c's review-freshness check below (don't conflate the two): if you
  have just pushed (Phase 6's initial push, or any Phase 8 fix push), GitLab
  may not have created the new pipeline yet — treat this the same as "still
  running" below and re-poll, do **not** jump straight to 8c off a single
  `none`. Only once you've confirmed `none` on at least two polls, spaced one
  full poll interval (180s) apart, with no intervening push, is it safe to
  conclude this MR genuinely has no CI pipeline configured — then go to 8c.
- **`skipped`**: this MR has no CI gate to wait on — go straight to Step 8c.
- **Still running** (`pending`/`running`/`created`/`waiting_for_resource`/
  `preparing`/`scheduled`): wait one poll interval (180s, backgrounded — see
  [how to wait](#poll-wait) above) and check again. Does not count as an
  iteration, but the wall-clock and poll-count limbs of Step 8a's budget do
  **not** pause for
  this — run `sh {budget} poll {project-id}-{iid}` (or, on the manual
  fallback path, check `date +%s` against `{start-time}` and your poll count)
  on every single re-check here, the same as the "review agent hasn't posted"
  branch in 8c. A pipeline that never leaves this state (stuck queued, e.g.
  `waiting_for_resource`) is exactly the case those limbs exist to catch —
  once either is hit, stop and go to Step 8d, do not keep waiting for it to
  resolve on its own.
- **`success`**: move to Step 8c.
- **`failed`**: fetch the failing job(s) and their logs — the same
  `glab ci status` call already carries the job list, so this needs no extra
  JSON tooling either:

  ```bash
  glab ci status --branch "$(git branch --show-current)" --output json \
    --jq '.jobs[] | select(.status == "failed") | "\(.id) \(.name) \(.stage)"'
  glab ci trace {job-id-or-name}          # accepts an id or a job name
  ```

  Fallback (older `glab`): `glab api "projects/{project-id}/pipelines/{pipeline-id}/jobs?scope[]=failed"`.
  Or with MCP: `get_pipeline` (`include: ["jobs"]`, `job_status: "failed"`)
  then `get_job` (`include: ["log"]`) per failing job.

  **Before diagnosing or fixing anything: check Step 8a's budget first** — run
  `sh {budget} iteration {project-id}-{iid}` (or the manual check) *now*, and
  if it exits 1, do not start this fix — go to Step 8d instead, even though
  this specific failure looks fixable. Only once it exits 0 (budget remains,
  and this fix is now counted): diagnose the root cause (don't guess — read the actual
  failure), fix it in code, commit, push. That `iteration` call already
  recorded this as one Step 8a iteration — don't call it again for the same
  push. A fresh pipeline starts automatically on push — loop back to the top
  of 8b. Only re-run without a code change when the failure is a verified
  infra flake (say so explicitly when you do this; it still counts as an
  iteration, so it still goes through the `iteration` gate first).
- **`canceled`**: GitLab auto-cancels a pipeline superseded by a newer push —
  so right after one of your own Step 8a fix pushes, the pipeline you land on
  may just be the stale, now-superseded run, not the current one. Re-poll
  once, one poll interval later (180s, backgrounded — see
  [how to wait](#poll-wait)), for the pipeline on the current
  HEAD before concluding anything. If a fresh pipeline for the current HEAD exists,
  follow **its** status instead — this was never really "canceled" from this
  loop's point of view. Only if `canceled` is still the latest pipeline after
  that one re-poll: this is not something a fix can resolve by pushing — go
  straight to Step 8d and report it, regardless of remaining budget. (Step
  8d's trigger below covers this: budget exhaustion is one way in, "nothing
  left to push at" is the other.)

### Step 8c — Poll review-agent discussions

Only once the pipeline is green or gate-less (8b). Every listing here is a
poll — run `sh {budget} poll {project-id}-{iid}` (Step 8a) first and stop for
Step 8d if it exits 1.

**First, once per Phase 8 run: identify the review agent.** You cannot apply
the human-comment exclusion without knowing which author is the bot. The
review agent self-assigns itself as a *reviewer* on the MR per
`code-review.md`, so read the MR's reviewer list:

```bash
glab mr view {iid} --output json --jq '.reviewers[].username'
```

Call that set `{agent-usernames}`. A comment author in that set is the review
agent; **any other author is a human**. If `.umo/jira-tracker.json` declares a
known bot account, prefer that name; otherwise use this reviewers-list
heuristic. If the list is empty (the agent hasn't self-assigned yet), that is
the "review agent hasn't posted anything yet" branch below — do not guess a
username, and do not treat unknown authors as the bot.

Then list the threads:

```bash
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
```

This projects the **whole `notes[]` array**, not `notes[0]`, and that is
load-bearing — do not simplify it back:

- `authors=` lists *every* non-system author on the thread, so a human who
  replied on a thread the review agent started is visible. `notes[0]` alone
  would hide them and the loop could act on a thread a human is in.
- `newest=` is `max_by(.created_at)`, which is what the review-freshness
  check needs — the thread's *latest* note, not the one that opened it. It is
  computed by timestamp rather than array position, so it does not depend on
  GitLab's notes ordering either way.
- `unresolved=` is `any(.notes[]; .resolvable and (.resolved == false))` —
  exactly the rule stated below, evaluated over all notes.
- `id=` is the **full** discussion id, which is what to pass to `--reply` and
  `resolve`. Show its first 8 characters to the developer if you like, but
  send the full id programmatically: a prefix can be ambiguous and errors.

To read a whole thread's exchange before judging it, fetch just that thread's
notes: `glab mr note list {iid} --output json --jq '.[] | select(.id == "{id}") | .notes'`.

> `glab mr note` is **experimental**: glab itself states "This feature is an
> experiment and is not ready for production use. It might be unstable or
> removed at any time." If it errors or is missing, drop to the
> `glab api .../discussions` fallback below — that path is not experimental.

Human-readable mode (`glab mr note list {iid} --state unresolved`, no
`--output json`) prints an **8-character discussion-id prefix** per non-system
thread — fine for showing a developer, but prefer the full `id` from JSON for
`--reply`/`resolve`. It also supports `--type`
(`all`/`general`/`diff`/`system`) and `--file <path>` filters — but `--type`
takes a single value, so it cannot exclude system notes on its own; that's
what the `select(any(.notes[]; .system == false))` above is for.

Fallback (non-experimental) — **`--paginate` is mandatory here**: GitLab
returns 20 items per page, and an MR accumulates a system note per push, so
real unresolved review threads fall off page 1 on a longer run and the loop
would see "zero unresolved threads" and converge falsely at Step 8e.

```bash
glab api --paginate "projects/{project-id}/merge_requests/{iid}/discussions"
```

`glab api` has **no** `--jq` flag, so this fallback needs an external `jq` or
`python3` to filter — unlike the native path above, which needs neither. With
`--paginate` it emits one JSON array per page, so slurp them
(`jq -s 'add | ...'`). Or with GitLab MCP: `get_merge_request` with
`include: ["discussions"]`.

The resolution rule is unchanged whichever path you use, and the JSON keeps
the same shape on both: each discussion holds a `notes` array; a note carries
`author`, `resolvable`, and `resolved` — the discussion itself has neither
field, so treat a discussion as unresolved when any of its resolvable notes
has `resolved: false`. `--state unresolved` is a convenience filter over that
rule, not a replacement for it; the per-note `resolvable`/`resolved` values
are in the output above so you can verify rather than trust the flag.

**After any push in this phase (from 8b or 8c), the review agent needs time to
re-review the new HEAD** — the **review-freshness check**, distinct from 8b's
no-CI-configured check above. A discussion list with zero unresolved threads
immediately after a push may just mean the agent hasn't looked at the new
commit yet, not that it approved it. Before treating that as convergence,
confirm at least one of: the review agent has posted a note whose timestamp is
after the push (that's the `newest=` field above — the thread's latest note,
not its first), its overall Approve/verdict reflects the current HEAD SHA, or
one bounded re-poll (one poll interval later) still shows nothing new — in the
last case, note that explicitly in the eventual report rather than silently
assuming approval.

For this check, and for telling "the agent has never posted" apart from "the
agent posted and everything is already resolved", run the same listing with
`--state all` instead of `--state unresolved` — the agent's newest note (the
one whose timestamp you need) may well sit on a thread that is already
resolved, which the unresolved filter hides. Same for the raw-API fallback:
`.../discussions` returns every thread, so filter it yourself.

- **Review agent hasn't posted anything yet**: it self-assigns on MR creation
  per `code-review.md` — wait one poll interval (180s, backgrounded — see
  [how to wait](#poll-wait)) and re-check. **This branch never pushes
  anything, so the iteration counter stays at 0 for as long as
  you sit here — the wall-clock and poll-count limbs of Step 8a's budget are
  the only things that can end this loop.** Run
  `sh {budget} poll {project-id}-{iid}` (or, on the manual fallback path,
  check `date +%s` against `{start-time}` **and** your poll count) on every
  single re-check here — same as the "still running" branch in 8b — not just
  when it "feels" like a while
  has passed. Once either limit is hit, stop regardless of the iteration
  count and go to Step 8d — that's the tooling incident `code-review.md`
  describes; say so in the report rather than waiting forever on a bot that
  isn't coming.
- **A human posted a comment**: do not touch it. This loop only acts on the
  review agent's own threads — never auto-reply to or resolve a human's
  comment. Use the `authors=` field from the listing above: if **any** author
  on the thread is outside `{agent-usernames}`, a human is participating in
  it, even when the review agent opened it — leave the whole thread alone.
  Note it in the status report (Step 8d/8e) and let the developer
  handle it.
- **A thread you already fixed-and-resolved has come back** (reopened, or a
  new discussion on the same file/line asserting the same defect you already
  replied to and resolved earlier in this run — a different comment on the
  same file/line is a new finding, judge it normally below): do not just fix
  it again as if new — that's a tooling anomaly (the review agent
  re-flagging something already addressed), not a genuine new finding.
  Finish this poll's pass over the remaining threads (still-new ones get
  judged normally, per the bullet below), but once that pass is done, do not
  start another fix→push iteration — go straight to Step 8d and report the
  reopened thread there. A reopen means this loop cannot make further
  progress here regardless of remaining budget.
- **Unresolved thread from the review agent** (first time seeing this
  specific finding): read the actual diff/code the comment refers to and
  judge it on its merits — is this a real, in-scope defect (correctness,
  security, a contract it breaks, a standard or ADR it violates), or a false
  positive / stylistic opinion / suggestion outside this MR's scope?
  - **Valid** → **before doing anything else, check Step 8a's budget** — run
    `sh {budget} iteration {project-id}-{iid}` (or the manual check) *now*. A
    single legitimate-looking comment does not override the
    budget — if it exits 1, do not push a fix for it, go
    to Step 8d instead and list it as unresolved. Only once it exits 0:
    fix the code, commit, push (that call already recorded the Step 8a
    iteration), then reply on that thread naming what changed and resolve it.
    Loop back to Step 8b — a new
    pipeline run and a fresh review pass both follow from the push.
  - **Not valid** → reply on the thread with the concrete reason it doesn't
    apply (cite the code, not just an opinion — and note the reply body
    cannot start a line with `/`, which GitLab reads as a quick action), then
    resolve the discussion. Never resolve a thread silently — always reply
    first. This does not count as a Step 8a iteration (no push happened), so
    do not call `iteration` for it.

  Reply and resolve, passing the **full** `id=` from the listing above (both
  commands also accept an 8+ character prefix, but a prefix can be ambiguous
  and then errors — use the full id programmatically and keep the short form
  for what you show the developer):

  ```bash
  glab mr note create {iid} --reply {discussion-id} -m "{reply text}"
  glab mr note resolve {iid} {discussion-id}
  ```

  Same experimental caveat as the listing command. Argument order is
  MR first, discussion second, as above. Fallback (non-experimental) — the raw
  `POST .../discussions/{id}/notes` then `PUT .../discussions/{id} -F resolved=true`
  calls in `references/glab.md`, or MCP `save_merge_request_review` with
  `method: "reply_discussion"` then `"resolve_discussion"` per
  `references/mcp.md`. Reply-before-resolve holds on every path.
- **No unresolved review-agent threads left** (and the "just pushed" check
  above is satisfied where it applies): go to Step 8e.

### Step 8d — Stop and hand off

Reached whenever either is true — stop looping the moment either fires, don't
keep polling to "make sure":

- **Budget exhausted**: any one of Step 8a's three limbs (6 iterations, 45
  minutes, 40 polls) is hit before Step 8e's condition holds.
- **Nothing left to push at**: the loop hits a state no further code push can
  resolve — a pipeline still `canceled` after 8b's one re-poll for the
  current HEAD, or a reopened/duplicate finding (8c, after finishing that
  poll's pass over any other, actually-new threads). Do not wait out the
  rest of the budget once this is confirmed.

Report, without claiming the task is done:

- Current pipeline status (and which job(s) are still failing, if any).
- Every review-agent thread still unresolved, with your assessment of each
  (fix attempted and still failing / genuinely needs a human call / agent
  never appeared / reopened after an earlier fix — see 8c).
- Any human comments the loop left untouched (Step 8c).
- Which limb ended the loop (iterations / clock / poll count / unresolvable
  state), so whoever picks this up knows whether retrying is even likely to
  help. Run `sh {budget} status {project-id}-{iid}` and quote its line — it
  reports the final counters and names the blown limb(s), and never modifies
  anything (it always exits 0, even over budget).
- **Where the time went**, straight from that same `status` line: `polling`
  vs `remediation` vs `since-last` (Step 8a). Say it in words, not just as raw
  seconds — e.g. "45min budget spent: ~9min polling (3 checks at 180s), ~33min
  on the failed `lint` job and waiting for your answer on the CVE, ~3min since
  the last check", or "~42min of it was polling a pipeline that never left
  `waiting_for_resource`". These two read completely differently to whoever
  picks the MR up: a clock burned on remediation means the loop was working
  and a retry may finish the job, while a clock burned on polling means
  nothing was moving and a retry will likely stall the same way. A bare
  `elapsed 2700s/2700s | poll 15/40` hides that distinction and reads as if
  the loop wasted its budget on slow polling.

This is a handoff, not a failure to hide.

### Step 8e — Convergence, command complete

Both hold, true at the same time, on the current HEAD: latest pipeline green or gate-less per
Step 8b, zero unresolved review-agent discussion threads. Report completion —
pipeline status, what (if anything) got fixed along the way (quote
`sh {budget} status {project-id}-{iid}` for the poll/iteration count and the
`polling` / `remediation` / `since-last` split, and read the split out in
words so the elapsed time is attributed rather than left looking like slow
polling), and that the human Approve slot of `MR-APPROVALS` is still
outstanding (this command does not wait for or chase that). Only now is
`/umo-jira-tracker:mr` finished.

---

## MR Title Format

```
{type}(scope): lowercase imperative subject (JIRA-KEY)
```

Conventional Commits with the JIRA key in parentheses at the **end** — this keeps
the title commitlint-safe while still carrying the key that CI checks for and that
the merged-PR automation reads.

- Scope is optional; the type and the trailing key are not.
- Subject is lowercase, imperative, no trailing period.
- Derive the subject from the JIRA summary or the commits, dropping the slice
  coordinate prefix — the key already locates the work.

Example: `feat(publisher): add kafka retry (PAY-1234)`

There is no keyless form. See Phase 1c.

## MR Description Template

```markdown
## JIRA Task
[{JIRA-KEY}](https://umotech.atlassian.net/browse/{JIRA-KEY}) — under slice [{SLICE-KEY}](https://umotech.atlassian.net/browse/{SLICE-KEY})

## What this MR does?
{Auto-generated from JIRA description + bead Notes + commit analysis}

## Why?
{From JIRA ticket context or developer input}

## Changes Made
{Bullet list generated from git log {target-branch}..HEAD --oneline}

## How to Test
{From JIRA acceptance criteria / bead Refined AC if available, otherwise leave placeholder}

## Checklist
- [ ] Added tests
- [ ] Updated documentation
- [ ] Self-reviewed code
```

Omit the slice link from the JIRA Task line if the Task's parent could not be resolved.

## Branch Naming Convention

Format: `{type}/{JIRA-KEY}-{short-description}`

| Type | When to use |
|------|-------------|
| `feat/` | New feature |
| `fix/` | Bug fix |
| `hotfix/` | Critical production fix |
| `refactor/` | Code restructuring |
| `docs/` | Documentation |
| `chore/` | Maintenance, tooling |
| `test/` | Adding or fixing tests |
| `ci/` | CI/CD configuration |
| `perf/` | Performance improvement |
| `build/` | Build system, dependencies |

Derive the type from the JIRA issue type when available:

- **Bug** → `fix/`
- **Task** → from the nature of the change: `feat/`, `refactor/`, `chore/`, `test/`, `docs/`, `ci/`, `perf/`, `build/`. Pick from the diff; ask only if it is genuinely ambiguous.

Flow, Slice and Request never appear here — an MR delivers a Task or fixes a Bug.

## Example Invocations

**Explicit — current branch with a JIRA Task:**

```
/umo-jira-tracker:mr in current branch using JIRA task PAY-1234
```

Parsed: branch strategy = current (explicit), JIRA key = PAY-1234, target = dev. Commits/push/MR run immediately.

**No input — auto branch heuristic:**

```
/umo-jira-tracker:mr
```

On target/protected → create new branch automatically. On a feature branch with no open MR → reuse it. On a feature branch with an open MR → reuse and update. Uses the claimed bead's JIRA key; stops at Phase 1c if there is none. No branch-strategy quiz.

**New branch with a JIRA Task:**

```
/umo-jira-tracker:mr create new branch for PAY-5678
```

Parsed: branch strategy = new (explicit), JIRA key = PAY-5678, target = dev. Agent fetches the JIRA summary to derive the branch name and proceeds immediately.

**No JIRA key available:**

```
/umo-jira-tracker:mr push current branch and create MR
```

No claimed bead, no key in the input → Phase 1c. The command helps the developer find or create the Task, and does not build a keyless branch or title. This is the one stop that survives the no-gates rule.
