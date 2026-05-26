---
name: task
description: Turns accepted UMO specs, PRDs, BRDs, proposals, ADRs, incidents, and review findings into rich, traceable Beads epics/tasks/spikes with explicit spec references, independent unit contracts, wave grouping, and verification. Use when creating or refining bead trees, or handing execution to agents.
paths:
  - "**/AGENTS.md"
  - "**/docs/proposals/**"
  - "**/docs/product/prds/**"
  - "**/docs/product/brds/**"
  - "**/docs/spec.md"
  - "**/docs/backlog.md"
  - "**/docs/incidents/**"
  - "plugins/umo-sdlc/**"
---

# UMO Task Decomposition (Spec → Beads)

Use this skill when an accepted specification, PRD, BRD, proposal, ADR, incident, or review finding is ready to become executable work in Beads.

This skill **replaces** the previous `planning` skill. It enforces **spec traceability**, **independent unit contracts**, and **standard rich structure** so that agents never produce shallow "header + 2 sentences" beads.

**Important:** When using this skill, **always** load and follow:
- `references/decomposition-examples.md` (before/after examples of rich vs shallow tasks)
- `references/beads-issue-shape.md` (epic/task/spike shapes)
- `references/beads-label-taxonomy.md` (label conventions)
- `assets/epic.template.md` and `assets/task.template.md` (mandatory rich templates — every field must be populated)

These files are part of the skill context. The agent must consult them to produce correct, traceable output.

## Core Principle

**Specs are contracts.** Every bead description must contain a direct, section-anchored link back to the source document + an "Independent Unit Contract" so that work can be executed in parallel by multiple humans + agents without collisions.

## When to Use

- After a PRD/BRD/proposal is marked `accepted`.
- When turning a service `spec.md` or `backlog.md` into Beads.
- When an incident or review finding requires corrective tasks.
- When refining an existing bead tree to add missing traceability.

## The Spec → Epic/Task Decomposition Playbook (Mandatory Steps)

When the user says "this is ready to plan" or "decompose this spec", follow these steps **in order**:

### Step 1: Identify the Source Contract
- Read the full source document (PRD, BRD, proposal, ADR, spec.md, or incident).
- Note the exact file path and the most relevant sections (e.g. `product/prds/001-wallet-lifecycle-management.md#goals`, `product/prds/001-wallet-lifecycle-management.md#acceptance-criteria`).

### Step 2: Define the Epic (Outcome)
- Create **one epic** per major outcome.
- The epic description **must** use the rich `epic.template.md`.
- Fill **every** field, especially:
  - `## Source` with file + section anchors.
  - `## Independent Unit Contract` (what the whole epic owns, files it touches, interfaces).
  - `## Wave Grouping` (which child tasks can run in parallel).

### Step 3: Decompose into Independent Child Tasks
For each child task:
- The task must be **small enough** for a focused agent session (1–3 files, clear acceptance criteria).
- The task description **must** use the rich `task.template.md`.
- Mandatory fields that were previously optional:
  - `## Source` → exact section link(s) in the PRD/BRD.
  - `## Independent Unit Contract` → list of files this task will create/modify + interfaces it exposes or consumes + explicit statement that it does **not** overlap with sibling tasks.
  - `## Wave / Parallelism` → "Can run in parallel with Task X and Y" or "Requires review gate after Wave 1".
  - `## Acceptance Criteria` → mapped 1:1 to specific criteria in the source spec.
  - `## Verification` → concrete command or evidence (e.g. `bun test`, `tsc --noEmit`, "PRD section 4.2 satisfied").

### Step 4: Add Dependencies and Waves
- Use `bd dep add` so that `bd ready` shows the intended first work.
- Explicitly document waves in the epic (Wave 1 = independent tasks that can start immediately; Wave 2 = tasks that need output from Wave 1 or a human review gate).

### Step 5: Labels and Human Decision Points
- Apply standard labels (phase, source, service/domain, size, quality-gate).
- Create `decision` beads for any open human choices.

### Step 6: Output Summary
After creating the tree, report:
- Source document + key sections used.
- Epic ID and title.
- Number of child tasks + wave grouping.
- First ready task(s).
- Any remaining human decisions.

## Rich Templates (Mandatory)

The templates in `assets/` are now **mandatory**. Agents must populate every section with real content and real spec references. Shallow descriptions are rejected.

See:
- `assets/epic.template.md`
- `assets/task.template.md`

## Daily Usage Examples

**PO hands off a PRD**:
> "PRD 001-wallet-lifecycle-management is accepted. Ready to plan."

→ You load this skill, read the PRD, produce one epic + 6–8 traceable child tasks with section links and independent contracts.

**Developer picks up work**:
> `bd ready` shows Task T-42.

→ The task description already contains the exact PRD section, the files to touch, the acceptance criteria, and the verification command.

## Guardrails

- Never create a bead tree without reading the full source spec first.
- Never omit the `## Source` or `## Independent Unit Contract` sections.
- Never encode long-form requirements inside Beads — keep the source document as the single source of truth and reference it.
- Always ask for human approval on priority, scope, and risky cross-team dependencies before creating large trees.

## Output

After any task decomposition work, produce a concise report containing the source artifact, beads created (grouped by epic/task), dependencies, first ready work, labels, open decisions, and whether execution can start in a fresh agent session.