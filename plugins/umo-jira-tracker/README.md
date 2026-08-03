# umo-jira-tracker

Automates the daily developer JIRA workflow by linking JIRA issues to a local [Beads](https://beads.umo.dev) (`bd`) database, guiding bead-by-bead implementation, creating GitLab MRs, and syncing outcomes back to JIRA.

It encodes the org's work-tracking model — five issue types, native Premium hierarchy, no custom fields. The model reference is [`references/work-tracking-model.md`](references/work-tracking-model.md); the binding source is `engineering/way-of-working/how-we-track-work.md` in the `sdlc-control-plane` meta-repo.

## The model in one screen

```
FLOW (level 2, the unit of value and cost)
  └── SLICE (the epic slot, the unit of handover)
        ├── TASK      (level 0 — engineering-internal, 1–2 days)
        ├── BUG       (level 0 — defect against something deployed)
        └── REQUEST   (level 0, in the PROVIDER's project, parented
                       cross-project to this slice)
```

**Five types, nothing else.** **Story** and **Sub-task** do not exist: dev work is a Task, full stop, and private breakdown is checkboxes or beads. The **parent chain is the only structural edge** — no flow or slice field to fill, and none to drift. `Blocks` is the only link type.

**Unused fields:** Sprint, story points, original estimate and time tracking, Epic Link. Due date is the `needed-by` on a Request and is meaningless on a Task.

**Terminals differ in meaning even where they share a name.** A Task reaching Done means the PR merged and tests are green; a Request reaching its terminal means **consumer proof** — the mock is retired and the consumer's tests pass against the real thing, which only the consumer can declare. **Retired** — withdrawn without being completed — is global, requires a Resolution, and is excluded from every count.

## What this plugin does not do

- **It does not create Flows, Slices or Requests.** They carry demo statements, inherited-versus-new AC splits, dependency registers, contracts, mock owners and due dates. The flow PM and the tech leads author them on the board.
- **It does not sync your execution plan to Jira.** The steps inside one Task are an engineering artifact and live in git. Decompose freely with `bd create --parent`; no bridge is built, because dual maintenance is drift.
- **It does not transition Jira on MR creation.** Task Done is the merged-PR automation's call, and it fires on merge.
- **It does not mirror the bead tree.** Beads and Jira are not two views of one thing.

## Slash commands

| Command | Purpose |
|---------|---------|
| `/umo-jira-tracker:setup` | First-run wizard: verify tools, write `.umo/jira-tracker.json` |
| `/umo-jira-tracker:sync [--dry-run] [--jql "..."] [--pull-only\|--push-only]` | Two-way sync: pull JIRA→Beads, then promote unsynced beads → JIRA, then reconcile status drift |
| `/umo-jira-tracker:work [KEY\|bead-id\|--ready]` | Claim a bead, discuss AC with AI, push refinements back to JIRA |
| `/umo-jira-tracker:create task\|bug --parent <SLICE-KEY>` | Create a JIRA Task or Bug under a Slice |
| `/umo-jira-tracker:commit` | Group staged changes into conventional commits, generate MR description |
| `/umo-jira-tracker:mr` | Create a GitLab MR and sync JIRA (comment + description) |
| `/umo-jira-tracker:close [bead-id]` | Close the bead and transition JIRA |

## Skills

| Skill | Purpose |
|-------|---------|
| `jira-tracker-setup` | Tool verification + config writer |
| `jira-sync` | JIRA → Beads pull (Phase A of `/sync`) |
| `jira-push` | Beads → JIRA promotion (Phase B of `/sync`) |
| `jira-bead-bridge` | Claim, discuss, refine, push AC back to JIRA |
| `gitlab-mr` | glab / GitLab MCP MR creation reference |
| `jira-sync-back` | All JIRA mutations: comments, transitions, issue creation |

## Prerequisites

| Tool | Purpose | How to get |
|------|---------|------------|
| `bd` | Local Beads CLI | Follow your org's Beads install guide |
| `glab` | GitLab CLI for MR creation | `brew install glab` or see [glab docs](https://gitlab.com/gitlab-org/cli) |
| Atlassian MCP | JIRA read/write | Configure in Cursor Settings → MCP |
| GitLab MCP (optional) | Alternative MR creation | Configure `@zereight/mcp-gitlab` in Cursor Settings → MCP |

The Jira instance must be **Premium** — the Flow level sits above the epic, which Standard cannot express.

### glab authentication

```bash
glab auth login
# or set GITLAB_TOKEN / GITLAB_ACCESS_TOKEN with api scope in your shell (~/.zshenv on macOS)
export GITLAB_TOKEN="<your-token>"
```

### Atlassian MCP

Add to your Cursor / Claude `mcp.json`:

```json
{
  "mcpServers": {
    "Atlassian": {
      "url": "https://mcp.atlassian.com/v1/mcp",
      "headers": {}
    }
  }
}
```

No API key is stored in this plugin. Authentication is handled by the MCP host.

### GitLab MCP (optional)

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

## Squad projects

Projects match squads, one team backlog each.

| Key | Project |
|---|---|
| PLAT | Platform |
| DATA | Data |
| AI | AI |
| EXP | Experience *(squad: Customer Experience)* |
| CRY | Crypto |
| PAY | Payments |
| CARD | Cards |
| FIN | Financial Core *(squad: Transactions & Accounting)* |
| CMP | Compliance/Support |
| BO | Backoffice Portal |

## Per-repo configuration

Run `/umo-jira-tracker:setup` to generate `.umo/jira-tracker.json`. The file is safe to commit (no secrets).

During setup you choose the `/sync` scope:

| Scope | JQL |
|-------|-----|
| All open assigned issues (default) | `assignee = currentUser() AND statusCategory != Done` |
| One flow — everything serving it, across projects | `issuekey in portfolioChildIssuesOf("{FLOW-KEY}")` |
| One slice | `parent = {SLICE-KEY} OR issuekey = {SLICE-KEY}` |

Example config:

```json
{
  "jira": {
    "cloudUrl": "https://umotech.atlassian.net",
    "defaultProjectKey": "PAY",
    "syncJql": "assignee = currentUser() AND statusCategory != Done",
    "transitionOnClose": "Done"
  },
  "gitlab": {
    "remote": "origin",
    "projectId": null,
    "targetBranch": "dev",
    "mrTool": "glab"
  },
  "beads": {
    "labelPrefix": "jira",
    "titleFormat": "[{key}] {summary}",
    "containerTypes": ["Flow", "Slice"],
    "workTypes": ["Task", "Bug", "Request"],
    "creatableTypes": ["Task", "Bug"]
  },
  "sync": {
    "direction": "both",
    "skipLabel": "jira-skip",
    "recentlyDoneWindow": "-14d"
  }
}
```

## JIRA → Beads mapping (pull direction)

Pull handles all five types.

| JIRA type | Bead type | Parent bead |
|-----------|-----------|-------------|
| Flow | epic | none — Flow is the root |
| Slice | epic | Flow-bead |
| Task / Bug | task | Slice-bead |
| Request | task | Slice-bead — the **consumer's** slice, cross-project |

Bead title format: `[PAY-1234] [IC-S2] <JIRA summary>` — the slice coordinate the summary already carries is preserved.

Bead labels: `jira:PAY-1234`, `jira-type:task`, `jira-status:in-progress`, `jira-parent:PAY-1200`, `jira-flow:PAY-900` (derived by walking the parent chain), `jira-origin:bead` (only on beads promoted via push).

Pull also includes a **recently-closed window** (`sync.recentlyDoneWindow`, default `-14d`) so issues that reached Done, Closed or Retired while you were offline still trigger a local bead close — with a reason that preserves which terminal it was.

## Beads → JIRA mapping (push direction)

Push handles two types, and that asymmetry is the point.

| Bead `type` | Parent context | Result |
|-------------|----------------|--------|
| `task` / `chore` / `feature` | parent resolves to a **Slice** | **Task** — create |
| `bug` | parent resolves to a **Slice** | **Bug** — create |
| any | parent is a Task, Bug or Request | **refused** — that would be a Sub-task. Leave it in Beads, or push it as a sibling under the same Slice |
| `epic` | any | **refused** — Slices and Flows are the flow PM's to author |
| any | no parent | orphan warning; suggests the squad's `[TH-<KEY>-S0]` tech-health slice, then requires `create unlinked` |
| `decision` | any | always skipped (ADRs stay local) |

**A push that promotes nothing is a normal outcome.** Most beads are steps inside an existing Task, and steps stay in git. Promote a bead only when it has become a **unit of assignment or delivery** — and you rarely need to decide manually, because the merge gate promotes anything that ends in a merge.

Full classification rules: `skills/jira-push/references/bead-type-mapping.md`.

### Opt-out label

| Label | Effect |
|-------|--------|
| `jira-skip` | Force-exclude this bead from push entirely. Configurable via `sync.skipLabel` |

There is no opt-**in** label. The classifier already declines anything that is not a unit of delivery; a label to override that would defeat the rule it exists to enforce.

### Status drift (Phase C)

After pull and push complete, `/sync` reconciles any bead that is **closed locally** but whose linked JIRA issue is still open, offering to transition it to `jira.transitionOnClose`. It checks the issue first — if the MR is merged, the org automation has already flipped the Task to Done.

## Local bead workflow

```bash
# Decompose freely — these stay in git
bd create "Investigate the retry path" --type task --parent bd-30
bd create "Write fixtures" --type task --parent bd-30

# Promote only when something became a unit of delivery
/umo-jira-tracker:sync
```

Use `bd label add <id> jira-skip` to keep a bead out of JIRA permanently.

## Naming standard and the merge gate

### Branch

```
{type}/{JIRA-KEY}-{short-description}
```

| Component | Required | Notes |
|-----------|----------|-------|
| `type` | Yes | `feat`, `fix`, `hotfix`, `chore`, `refactor`, `test`, `docs`, `ci`, `perf`, `build` |
| `JIRA-KEY` | Yes | e.g. `PAY-1234` |
| `short-description` | Yes | 2–5 words, kebab-case |

Multiple JIRA keys: `feat/PAY-1234-PAY-1235-login-refactor`

**Examples:** `feat/PAY-1234-add-kafka-retry`, `fix/CARD-567-null-pointer-on-transfer`

### MR title

```
{type}(scope): lowercase imperative subject (JIRA-KEY)
```

Conventional Commits with the JIRA key in parentheses at the **end** — commitlint-safe, and CI checks for the key. Example: `feat(publisher): add kafka retry (PAY-1234)`.

### Commit

`type(scope): description` — [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/). Include the JIRA key in the footer (`Closes: PAY-1234`) or the branch name.

### JIRA summary

```
[{SLICE-COORDINATE}] {outcome}
```

Dash in the coordinate, never slash, so names stay safe if they appear in file names. A **Task** summary is an imperative verb phrase; a **Bug** summary is the symptom, not the diagnosis.

### The merge gate

**No MR merges without a JIRA Task, and the merge commit references it.** This is what makes bead promotion automatic — anything that ends in a merge has a Task by definition — and it is what the merged-PR automation reads to flip the Task to Done. `/mr` will not build a keyless branch or title.

### Forbidden

| Pattern | Why forbidden |
|---------|---------------|
| Branch or MR title without a JIRA key | Fails CI, cannot merge, and the Done automation has nothing to key off |
| Names like `tmp`, `wip`, `test`, `my-branch` | No context |
| Layer names, person names, status words, "part 2 / misc / fixes" in a JIRA summary | Coordinates and outcomes only — nothing mutable |
| Multiple unrelated tasks in one branch | Violates atomic MR principle |
| Direct commits to `main`, `dev`, `release` | Bypasses review |

## JIRA issue creation rules

This plugin creates **Tasks and Bugs, under a Slice**. Story and Sub-task are refused because the types do not exist; Epic, Slice, Flow and Request are refused because they are authored by the flow PM or the requesting PM/TL. Creating an issue with no parent trips the org's orphan detector, so it requires a justification and the phrase `create unlinked`.
